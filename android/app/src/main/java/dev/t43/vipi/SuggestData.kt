package dev.t43.vipi

import android.content.Context
import android.os.Process
import android.util.Log
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Dữ liệu gợi ý từ (4 mô hình, 65 MB, cùng hai danh sách giữ nguyên). ViPiSuggest ánh xạ thẳng các file vào bộ nhớ,
 * mà file trong APK bị nén, nên chép ra filesDir/suggest-<versionCode>/ một lần, ở luồng nền: chép trên luồng chính
 * như dữ liệu của lõi (Core.kt) thì lần mở bàn phím đầu tiên chậm cả giây. Chép vào file tạm rồi đổi tên, đánh dấu
 * xong bằng `.complete` sau cùng; chép dở (hết chỗ, tiến trình bị tắt) thì lần sau chép lại từ đầu. Bản cũ hơn bị xoá.
 * Trong lúc chép, và nếu chép hỏng, bàn phím chạy bình thường, chỉ không có gợi ý.
 */
object SuggestData {
    private const val TAG = "ViPi"
    private val FILES = listOf(
        "SuggestEN.bin", "SuggestNN.bin", "SuggestVI.bin", "SuggestVINN.bin", "keep-words.txt", "keep-words-chat.txt",
    )

    /** Một luồng nền cho việc chép rồi làm nóng mô hình: lượt làm nóng luôn chạy sau khi chép xong. */
    val worker: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread({ Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND); r.run() }, "vipi-suggest")
    }

    /** Ở luồng nền: thư mục dữ liệu đã chép đủ, hoặc null nếu không chép được. */
    fun prepare(context: Context): File? {
        val version = context.packageManager.getPackageInfo(context.packageName, 0).let {
            if (android.os.Build.VERSION.SDK_INT >= 28) it.longVersionCode else @Suppress("DEPRECATION") it.versionCode.toLong()
        }
        val dir = File(context.filesDir, "suggest-$version")
        val marker = File(dir, ".complete")
        if (marker.exists()) return dir
        val started = System.nanoTime()
        context.filesDir.listFiles { f -> f.name.startsWith("suggest-") && f != dir }?.forEach { it.deleteRecursively() }
        return try {
            dir.deleteRecursively()
            dir.mkdirs()
            for (name in FILES) {
                val tmp = File(dir, "$name.tmp")
                context.assets.open("suggest/$name").use { input -> tmp.outputStream().use { input.copyTo(it, 1 shl 16) } }
                if (!tmp.renameTo(File(dir, name))) error("rename $name")
            }
            val tmp = File(dir, ".complete.tmp")
            tmp.writeText("ok")
            if (!tmp.renameTo(marker)) error("rename marker")
            Log.i(TAG, "suggestion data copied in ${(System.nanoTime() - started) / 1_000_000} ms")
            dir
        } catch (e: Throwable) {
            Log.e(TAG, "cannot copy the suggestion data", e)
            dir.deleteRecursively()
            null
        }
    }
}
