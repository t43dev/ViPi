package dev.t43.vipi

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Bảng tạm của ViPi: 6 đoạn chữ vừa chép gần nhất, mỗi đoạn giữ 1 giờ. Chỉ lưu trên máy, trong thư mục
 * không sao lưu của app; không bao giờ gửi đi.
 */
class ClipHistory(context: Context) {
    class Item(val text: String, val at: Long)

    private val file = File(context.noBackupFilesDir, "clipboard.json")
    private var list: List<Item> = load()

    /** Các mục còn hạn, mới nhất trước. */
    fun recent(now: Long = System.currentTimeMillis()): List<Item> {
        val fresh = list.filter { now - it.at < KEEP_MS }
        if (fresh.size != list.size) { list = fresh; save() }
        return list
    }

    /** Thêm một đoạn vừa chép; trùng với mục cũ thì đưa mục đó lên đầu. Trả về true nếu danh sách đổi. */
    fun add(text: String, now: Long = System.currentTimeMillis()): Boolean {
        if (text.isBlank()) return false
        val current = recent(now)
        if (current.firstOrNull()?.text == text) return false
        list = (listOf(Item(text, now)) + current.filter { it.text != text }).take(MAX)
        save()
        return true
    }

    fun remove(text: String) {
        list = list.filter { it.text != text }
        save()
    }

    fun clear() {
        list = emptyList()
        file.delete()
    }

    private fun load(): List<Item> = runCatching {
        val a = JSONArray(file.readText())
        (0 until a.length()).map { a.getJSONObject(it).let { o -> Item(o.getString("text"), o.getLong("at")) } }
    }.getOrDefault(emptyList())

    private fun save() {
        val a = JSONArray()
        list.forEach { a.put(JSONObject().put("text", it.text).put("at", it.at)) }
        runCatching { file.writeText(a.toString()) }
    }

    companion object {
        const val MAX = 6
        const val KEEP_MS = 60 * 60 * 1000L
    }
}
