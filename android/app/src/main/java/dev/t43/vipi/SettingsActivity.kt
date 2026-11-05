package dev.t43.vipi

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import dev.t43.vipi.core.fuzzyOptions

/** Cài đặt và hướng dẫn bật bàn phím. Giao diện tiếng Anh, dựng bằng code cho gọn. */
class SettingsActivity : Activity() {
    private lateinit var prefs: Prefs
    private lateinit var status: TextView
    private lateinit var learned: TextView
    private val dp by lazy { resources.displayMetrics.density }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(20), px(28), px(20), px(28))
        }
        root.addView(TextView(this).apply {
            text = "ViPi"
            textSize = 30f
            typeface = Typeface.DEFAULT_BOLD
        })
        root.addView(note("Vietnamese Telex and Chinese Pinyin on one keyboard."))

        section(root, "Set up")
        status = note("")
        root.addView(status)
        root.addView(button("Turn on ViPi in Settings") { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) })
        root.addView(button("Switch to ViPi") {
            (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
        })
        root.addView(EditText(this).apply {
            hint = "Try it here"
            minLines = 2
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = px(8)
        })

        section(root, "Vietnamese")
        root.addView(note("Vietnamese and English are one keyboard: ViPi tells them apart as you type, so treen becomes trên and server stays server. Tap the globe key to switch to Chinese and back; hold it for more choices and these settings. Hold a key on the top row for its number. Word lists from Vikey."))
        root.addView(toggle("Check spelling", Prefs.SPELL_CHECK, true,
            "Only add marks where they make a real Vietnamese syllable, so words like \"class\" stay as typed."))
        root.addView(toggle("Restore non-Vietnamese words", Prefs.RESTORE, true,
            "When a word ends and is not Vietnamese, put back the keys you typed: user, data, more."))
        root.addView(toggle("Modern tone placement", Prefs.MODERN_TONE, false, "hoà, khoẻ, thuý instead of hòa, khỏe, thúy."))

        section(root, "Chinese")
        root.addView(toggle("Traditional characters", Prefs.TRADITIONAL, false, "头发 becomes 頭髮."))
        root.addView(toggle("Learn the words I pick", Prefs.LEARN, true, "Words you pick come first next time. Stored only on this phone."))
        learned = note("")
        root.addView(learned)
        root.addView(button("Clear learned words") {
            Core.loaded()?.clearLearned()
            Core.learnedWordsFile(this).delete()
            refresh()
        })
        root.addView(toggle("Full-width punctuation", Prefs.FULL_WIDTH, true, "，。？！ while typing Chinese."))
        root.addView(note("Fuzzy pinyin"), LinearLayout.LayoutParams(-1, -2).apply { topMargin = px(10) })
        for (option in fuzzyOptions()) {
            root.addView(CheckBox(this).apply {
                text = option.label
                isChecked = option.id in prefs.fuzzy
                setOnCheckedChangeListener { _, on ->
                    prefs.fuzzy = if (on) prefs.fuzzy + option.id else prefs.fuzzy - option.id
                }
            })
        }

        section(root, "Appearance")
        root.addView(RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            val current = prefs.theme
            for ((label, theme) in listOf("System" to KeyboardView.Theme.SYSTEM, "Light" to KeyboardView.Theme.LIGHT, "Dark" to KeyboardView.Theme.DARK)) {
                addView(RadioButton(this@SettingsActivity).apply {
                    text = label
                    id = View.generateViewId()
                    isChecked = theme == current
                    setOnCheckedChangeListener { _, on -> if (on) prefs.theme = theme }
                })
            }
        })
        if (android.os.Build.VERSION.SDK_INT >= 31) root.addView(toggle("Material You colors", Prefs.MATERIAL_YOU, false,
            "Use your wallpaper's accent color for the Enter key and highlights instead of ViPi red."))
        root.addView(toggle("Show key popup", Prefs.KEY_POPUP, true, "Show a larger letter above the key you press."))

        section(root, "Keyboard")
        root.addView(note("On large screens (an unfolded phone or a tablet)"), LinearLayout.LayoutParams(-1, -2).apply { topMargin = px(6) })
        root.addView(RadioGroup(this).apply {
            orientation = RadioGroup.VERTICAL
            val current = prefs.largeLayout
            for ((label, l) in listOf(
                "Split: one half on each side of the fold" to KeyboardView.LargeLayout.SPLIT,
                "Wide: one keyboard in the middle" to KeyboardView.LargeLayout.WIDE,
                "Floating: drag it anywhere by the bar on top" to KeyboardView.LargeLayout.FLOATING,
            )) {
                addView(RadioButton(this@SettingsActivity).apply {
                    text = label
                    id = View.generateViewId()
                    isChecked = l == current
                    setOnCheckedChangeListener { _, on -> if (on) prefs.largeLayout = l }
                })
            }
        })
        root.addView(toggle("Vibrate on key press", Prefs.HAPTICS, true, null))
        root.addView(toggle("Auto-capitalize", Prefs.AUTO_CAP, true, "Start sentences with a capital letter."))
        root.addView(toggle("\".\" shortcut", Prefs.DOUBLE_SPACE, true, "Double-tap the space bar for a period and a space."))

        section(root, "About")
        root.addView(note("ViPi is free software under GPL-3.0. Typing stays on this phone."))
        root.addView(button("Source code on GitHub") {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/t43dev/ViPi")))
        })

        setContentView(ScrollView(this).apply { addView(root) })
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        val enabled = imm.enabledInputMethodList.any { it.packageName == packageName }
        val current = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD) ?: ""
        status.text = when {
            !enabled -> "1. Turn on ViPi under On-screen keyboards. 2. Switch to it."
            !current.startsWith("$packageName/") -> "ViPi is on. Switch to it to start typing."
            else -> "ViPi is your keyboard."
        }
        val n = Core.loaded()?.learnedCount()?.toInt() ?: 0
        learned.text = if (n == 0) "No learned words yet." else "$n learned words and phrases."
    }

    private fun px(v: Int) = (v * dp).toInt()

    private fun section(root: LinearLayout, title: String) {
        root.addView(TextView(this).apply {
            text = title
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xFFC8102E.toInt())
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = px(26); bottomMargin = px(4) })
    }

    private fun note(s: String) = TextView(this).apply {
        text = s
        textSize = 14f
        alpha = 0.75f
    }

    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setOnClickListener { action() }
    }

    private fun toggle(label: String, key: String, default: Boolean, detail: String?): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, px(8), 0, px(4))
        }
        box.addView(Switch(this).apply {
            text = label
            textSize = 16f
            isChecked = prefs.bool(key, default)
            gravity = Gravity.CENTER_VERTICAL
            setOnCheckedChangeListener { _, on -> prefs.set(key, on) }
        })
        if (detail != null) box.addView(note(detail).apply { textSize = 13f })
        return box
    }
}
