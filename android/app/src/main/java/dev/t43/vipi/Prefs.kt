package dev.t43.vipi

import android.content.Context
import android.content.SharedPreferences
import dev.t43.vipi.core.InputMode

/** Cài đặt người dùng (SharedPreferences "vipi"). */
class Prefs(context: Context) {
    val sp: SharedPreferences = context.getSharedPreferences("vipi", Context.MODE_PRIVATE)

    /** Chế độ đang dùng; lần đầu là tiếng Anh, tự nhận diện sẽ sang tiếng Việt khi gõ chữ Việt. */
    var mode: InputMode
        get() = runCatching { InputMode.valueOf(sp.getString("mode", null) ?: "") }.getOrDefault(InputMode.ENGLISH)
        set(v) {
            val e = sp.edit().putString("mode", v.name)
            if (v != InputMode.CHINESE) e.putString("latin", v.name)
            e.apply()
        }

    /** Việt hay Anh lần cuối, để quay lại từ tiếng Trung. */
    val latin: InputMode
        get() = runCatching { InputMode.valueOf(sp.getString("latin", null) ?: "") }.getOrDefault(InputMode.ENGLISH)

    fun bool(key: String, default: Boolean) = sp.getBoolean(key, default)
    fun set(key: String, value: Boolean) = sp.edit().putBoolean(key, value).apply()

    val modernTone get() = bool(MODERN_TONE, false)
    val spellCheck get() = bool(SPELL_CHECK, true)
    val restore get() = bool(RESTORE, true)
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
        const val TRADITIONAL = "traditional"
        const val LEARN = "learnWords"
        const val FULL_WIDTH = "fullWidthPunctuation"
        const val HAPTICS = "haptics"
        const val AUTO_CAP = "autoCapitalize"
        const val DOUBLE_SPACE = "doubleSpacePeriod"
        const val FUZZY = "fuzzy"
    }
}
