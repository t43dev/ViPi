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
        versionCode = 2
        versionName = "0.1.1"
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

val vipiAssets = tasks.register<Sync>("vipiAssets") {
    from(rootProject.file("../Resources")) {
        include("vietnamese-syllables.txt", "pinyin-words.bin", "pinyin-abbrev.bin", "bigram.bin", "s2t.bin",
            "autoswitch-vi.bin", "autoswitch-en.bin")
    }
    into(layout.buildDirectory.dir("generated/vipiAssets/vipi"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(cargoNdk, CargoNdkTask::outputDir)
        variant.sources.java?.addGeneratedSourceDirectory(uniffiBindgen, UniffiBindgenTask::outputDir)
        variant.sources.assets?.addStaticSourceDirectory(layout.buildDirectory.dir("generated/vipiAssets").get().asFile.absolutePath)
    }
}

tasks.named("preBuild") { dependsOn(vipiAssets) }
