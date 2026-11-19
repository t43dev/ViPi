import org.gradle.process.ExecOperations
import javax.inject.Inject

plugins {
    id("com.android.application")
}

android {
    namespace = "dev.t43.vipi"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "dev.t43.vipi"
        minSdk = 26
        targetSdk = 36
        versionCode = 19
        versionName = "0.4.0"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
    }

    // khoá ký bản phát hành: biến môi trường (scripts/android-release.sh đọc từ .env); không có thì APK chưa ký
    val keystore = providers.environmentVariable("ANDROID_KEYSTORE").orNull
    signingConfigs {
        if (keystore != null) create("release") {
            storeFile = file(keystore)
            storePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").get()
            keyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS").orElse("vipi").get()
            keyPassword = storePassword
        }
    }

    buildTypes {
        release {
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("net.java.dev.jna:jna:5.18.1@aar")
}

// Lõi Rust (../../core): thư viện .so cho từng ABI bằng cargo-ndk, và mã Kotlin sinh bằng uniffi.
// Dữ liệu bộ gõ (../../Resources) được chép vào assets lúc build, không lưu hai lần trong git.
val coreDir = rootProject.file("../core")
val coreSources = fileTree(coreDir) { include("src/**", "Cargo.toml", "Cargo.lock", "uniffi.toml") }

abstract class CargoNdkTask : DefaultTask() {
    @get:InputFiles abstract val sources: ConfigurableFileCollection
    @get:Input abstract val ndkDir: Property<String>
    @get:Input abstract val crateDir: Property<String>
    @get:Input abstract val abis: ListProperty<String>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @get:Inject abstract val exec: ExecOperations

    @TaskAction
    fun build() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        exec.exec {
            workingDir(crateDir.get())
            environment("ANDROID_NDK_HOME", ndkDir.get())
            // thư viện được phát hành công khai: không để lộ đường dẫn của máy build
            environment("RUSTFLAGS", "--remap-path-prefix=${System.getProperty("user.home")}=/home --remap-path-prefix=${File(crateDir.get()).parent}=/vipi")
            commandLine(listOf("cargo", "ndk") + abis.get().flatMap { listOf("-t", it) } +
                listOf("-o", out.absolutePath, "build", "--release", "--features", "uniffi"))
        }
    }
}

abstract class UniffiBindgenTask : DefaultTask() {
    @get:InputFiles abstract val sources: ConfigurableFileCollection
    @get:Input abstract val crateDir: Property<String>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @get:Inject abstract val exec: ExecOperations

    @TaskAction
    fun generate() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        val crate = crateDir.get()
        // uniffi đọc mô tả giao diện từ thư viện chưa strip (bản debug cho máy build)
        exec.exec { workingDir(crate); commandLine("cargo", "build", "--features", "uniffi") }
        val lib = listOf("so", "dylib").map { File(crate, "target/debug/libvipi_core.$it") }.first { it.exists() }
        exec.exec {
            workingDir(crate)
            commandLine("cargo", "run", "--features", "bindgen", "--bin", "uniffi-bindgen", "--", "generate",
                "--library", lib.absolutePath, "--language", "kotlin", "--no-format", "--out-dir", out.absolutePath)
        }
    }
}

val cargoNdk = tasks.register<CargoNdkTask>("cargoNdk") {
    sources.from(coreSources)
    ndkDir.set(androidComponents.sdkComponents.ndkDirectory.map { it.asFile.absolutePath })
    crateDir.set(coreDir.absolutePath)
    abis.set(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
    outputDir.set(layout.buildDirectory.dir("rustJniLibs"))
}

val uniffiBindgen = tasks.register<UniffiBindgenTask>("uniffiBindgen") {
    sources.from(coreSources)
    crateDir.set(coreDir.absolutePath)
    outputDir.set(layout.buildDirectory.dir("generated/uniffi"))
}

// Mô hình gợi ý từ (65 MB, không lưu trong git): scripts/suggest-models.sh tải về build/suggest, hoặc
// VIPI_SUGGEST_MODELS chỉ tới thư mục khác. Thiếu thì dừng build: APK không có chúng thì không có gợi ý, tự sửa lỗi gõ.
val suggestModels = providers.environmentVariable("VIPI_SUGGEST_MODELS").map { File(it) }
    .orElse(rootProject.layout.projectDirectory.dir("../build/suggest").asFile).get()
val suggestModelFiles = listOf("SuggestEN.bin", "SuggestNN.bin", "SuggestVI.bin", "SuggestVINN.bin")

val vipiAssets = tasks.register<Sync>("vipiAssets") {
    val models = suggestModels
    val names = suggestModelFiles
    doFirst {
        val missing = names.filter { !File(models, it).isFile }
        if (missing.isNotEmpty()) throw GradleException(
            "Word suggestion models missing in $models: ${missing.joinToString()}. Run scripts/suggest-models.sh " +
                "from the repository root (or set VIPI_SUGGEST_MODELS to a directory that has them).")
    }
    from(rootProject.file("../Resources")) {
        include("vietnamese-syllables.txt", "pinyin-words.bin", "pinyin-abbrev.bin", "bigram.bin", "s2t.bin",
            "autoswitch-vi.bin", "autoswitch-en.bin", "autoswitch-pairs.bin")
        into("vipi")
    }
    // gợi ý từ: chép ra filesDir ở luồng nền (SuggestData.kt), cùng các danh sách giữ nguyên
    from(models) { include(names); into("suggest") }
    from(rootProject.file("../Resources")) { include("keep-words.txt", "keep-words-chat.txt"); into("suggest") }
    into(layout.buildDirectory.dir("generated/vipiAssets"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(cargoNdk, CargoNdkTask::outputDir)
        variant.sources.java?.addGeneratedSourceDirectory(uniffiBindgen, UniffiBindgenTask::outputDir)
        variant.sources.assets?.addStaticSourceDirectory(layout.buildDirectory.dir("generated/vipiAssets").get().asFile.absolutePath)
    }
}

tasks.named("preBuild") { dependsOn(vipiAssets) }
