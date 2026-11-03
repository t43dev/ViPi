package dev.t43.vipi

import android.content.Context
import android.content.SharedPreferences
import dev.t43.vipi.core.InputMode

/** Cài đặt người dùng (SharedPreferences "vipi"). */
class Prefs(context: Context) {
    val sp: SharedPreferences = context.getSharedPreferences("vipi", Context.MODE_PRIVATE)

    var mode: InputMode
        get() = runCatching { InputMode.valueOf(sp.getString("mode", null) ?: "") }.getOrDefault(InputMode.VIETNAMESE)
        set(v) = sp.edit().putString("mode", v.name).apply()

    /** Thứ tự dùng gần nhất của ba chế độ (phím quả địa cầu quay về chế độ trước, như ⌃⇧ trên macOS). */
    var recent: List<InputMode>
        get() {
            val saved = (sp.getString("recent", null) ?: "").split(",")
                .mapNotNull { runCatching { InputMode.valueOf(it) }.getOrNull() }
            return (saved + InputMode.entries).distinct()
        }
        set(v) = sp.edit().putString("recent", v.joinToString(",") { it.name }).apply()

    fun bool(key: String, default: Boolean) = sp.getBoolean(key, default)
    fun set(key: String, value: Boolean) = sp.edit().putBoolean(key, value).apply()

    val modernTone get() = bool(MODERN_TONE, false)
    val spellCheck get() = bool(SPELL_CHECK, true)
    val restore get() = bool(RESTORE, true)
    val autoSwitch get() = bool(AUTO_SWITCH, false)
    val traditional get() = bool(TRADITIONAL, false)
    val learn get() = bool(LEARN, true)
    val fullWidth get() = bool(FULL_WIDTH, true)
    val haptics get() = bool(HAPTICS, true)
    val autoCap get() = bool(AUTO_CAP, true)
    val doubleSpacePeriod get() = bool(DOUBLE_SPACE, true)

    var fuzzy: Set<String>
        get() = sp.getStringSet(FUZZY, emptySet()) ?: emptySet()
        set(v) = sp.edit().putStringSet(FUZZY, v).apply()

    companion object {
        const val MODERN_TONE = "modernTone"
        const val SPELL_CHECK = "spellCheck"
        const val RESTORE = "restoreNonVietnamese"
        const val AUTO_SWITCH = "autoSwitch"
        const val TRADITIONAL = "traditional"
        const val LEARN = "learnWords"
        const val FULL_WIDTH = "fullWidthPunctuation"
        const val HAPTICS = "haptics"
        const val AUTO_CAP = "autoCapitalize"
        const val DOUBLE_SPACE = "doubleSpacePeriod"
        const val FUZZY = "fuzzy"
    }
}
