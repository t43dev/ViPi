package dev.t43.vipi

import android.content.Context
import android.util.Log
import dev.t43.vipi.core.ViPiComposer
import java.io.File

/**
 * Lõi bộ gõ dùng chung trong tiến trình (bàn phím và màn hình cài đặt).
 * Dữ liệu trong APK bị nén, nên lần đầu chép ra filesDir/res-<versionCode>/ rồi lõi Rust đọc thẳng bằng mmap.
 */
object Core {
    private const val TAG = "ViPi"
    private val FILES = listOf(
        "vietnamese-syllables.txt", "pinyin-words.bin", "pinyin-abbrev.bin", "bigram.bin", "s2t.bin",
        "autoswitch-vi.bin", "autoswitch-en.bin",
    )

    @Volatile
    private var composer: ViPiComposer? = null

    /** Lõi đã nạp, hoặc null nếu chưa nạp. */
    fun loaded(): ViPiComposer? = composer

    @Synchronized
    fun composer(context: Context): ViPiComposer? {
        composer?.let { return it }
        return try {
            val dir = resources(context.applicationContext)
            val started = System.nanoTime()
            ViPiComposer(dir.absolutePath).also {
                composer = it
                Log.i(TAG, "core loaded in ${(System.nanoTime() - started) / 1_000_000} ms")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "cannot load the input engine", e)
            null
        }
    }

    fun learnedWordsFile(context: Context): File = File(context.filesDir, "pinyin-user.json")

    private fun resources(context: Context): File {
        val version = context.packageManager.getPackageInfo(context.packageName, 0).longVersionCodeCompat()
        val dir = File(context.filesDir, "res-$version")
        val marker = File(dir, ".complete")
        if (!marker.exists()) {
            context.filesDir.listFiles { f -> f.name.startsWith("res-") && f != dir }?.forEach { it.deleteRecursively() }
            dir.mkdirs()
            for (name in FILES) {
                context.assets.open("vipi/$name").use { input ->
                    val tmp = File(dir, "$name.tmp")
                    tmp.outputStream().use { input.copyTo(it, 1 shl 16) }
                    tmp.renameTo(File(dir, name))
                }
            }
            marker.writeText("ok")
        }
        return dir
    }

    @Suppress("DEPRECATION")
    private fun android.content.pm.PackageInfo.longVersionCodeCompat(): Long =
        if (android.os.Build.VERSION.SDK_INT >= 28) longVersionCode else versionCode.toLong()
}
