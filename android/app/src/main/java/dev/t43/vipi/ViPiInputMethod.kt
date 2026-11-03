package dev.t43.vipi

import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.os.SystemClock
import android.text.InputType
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import dev.t43.vipi.core.InputMode
import dev.t43.vipi.core.KeyInput
import dev.t43.vipi.core.KeyOutcome
import dev.t43.vipi.core.ViPiComposer

/**
 * Bàn phím ViPi cho Android. Lõi Rust (Composer) quyết định chữ; ở đây chỉ đổi kết quả thành thao tác trên ô nhập:
 * - Tiếng Việt: từ đang gõ là "composing text" (có thể gạch chân), thay bằng chữ của lõi sau mỗi phím.
 * - Tiếng Anh: chữ đi thẳng vào ô nhập; gõ tắt / tự đổi thì xoá lùi rồi chèn.
 * - Tiếng Trung: pinyin đang gõ là composing text, ứng viên ở thanh trên, chọn thì commit chữ Hán.
 */
class ViPiInputMethod : InputMethodService(), KeyboardView.Listener {
    private lateinit var prefs: Prefs
    private var composer: ViPiComposer? = null
    private var keyboard: KeyboardView? = null
    private var passthrough = false        // ô mật khẩu / số: không qua bộ gõ
    private var enterAction = EditorInfo.IME_ACTION_NONE
    private var lastOwnEdit = 0L
    private var lastSpaceAt = 0L
    private val hardwareConsumed = HashSet<Int>()
    private var switcherRequested = false
    // cài đặt đổi khi bàn phím đang mở (màn hình cài đặt cùng tiến trình): áp ngay
    private val prefsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key != "mode" && key != "latin") { applyPrefs(); keyboard?.hapticsEnabled = prefs.haptics; refreshUi() }
    }

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        composer = Core.composer(this)
        prefs.sp.registerOnSharedPreferenceChangeListener(prefsListener)
    }

    override fun onDestroy() {
        prefs.sp.unregisterOnSharedPreferenceChangeListener(prefsListener)
        super.onDestroy()
    }

    override fun onCreateInputView(): View =
        KeyboardView(this, this).also { keyboard = it; it.showSystemSwitcher = switcherRequested }

    /**
     * Thanh điều hướng của bàn phím (mũi tên ẩn bàn phím ở góc trái, nút đổi bàn phím ở góc phải) do hệ thống vẽ
     * dưới bàn phím khi dùng cử chỉ. Android 16+ cho bộ gõ ẩn nó; nút đổi bàn phím chuyển vào menu quả địa cầu.
     */
    private fun hideImeNavigationBar() {
        if (android.os.Build.VERSION.SDK_INT >= 36) {
            window.window?.insetsController?.hide(android.view.WindowInsets.Type.captionBar())
        }
    }

    override fun onEvaluateFullscreenMode() = false

    override fun onStartInput(info: EditorInfo, restarting: Boolean) {
        super.onStartInput(info, restarting)
        applyPrefs()
        val cls = info.inputType and InputType.TYPE_MASK_CLASS
        val variation = info.inputType and InputType.TYPE_MASK_VARIATION
        val password = cls == InputType.TYPE_CLASS_TEXT && variation in setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD, InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        ) || cls == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        val numeric = cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_PHONE || cls == InputType.TYPE_CLASS_DATETIME
        passthrough = password || numeric || composer == null
        val multiLine = info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
        val action = info.imeOptions and EditorInfo.IME_MASK_ACTION
        enterAction = if (multiLine || info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) EditorInfo.IME_ACTION_NONE else action
        if (!restarting) composer?.cancel()
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        applyPrefs()
        val kb = keyboard ?: return
        val cls = info.inputType and InputType.TYPE_MASK_CLASS
        kb.layout = if (cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_PHONE || cls == InputType.TYPE_CLASS_DATETIME)
            KeyboardView.Layout.NUMBERS else KeyboardView.Layout.LETTERS
        kb.returnLabel = when (enterAction) {
            EditorInfo.IME_ACTION_GO -> "go"
            EditorInfo.IME_ACTION_SEARCH -> "search"
            EditorInfo.IME_ACTION_SEND -> "send"
            EditorInfo.IME_ACTION_NEXT -> "next"
            EditorInfo.IME_ACTION_DONE -> "done"
            else -> null
        }
        kb.modeLocked = passthrough
        kb.hapticsEnabled = prefs.haptics
        kb.shift = KeyboardView.Shift.OFF
        refreshUi()
        updateShift()
        hideImeNavigationBar()
        if (!restarting) kb.animateIn()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        endComposition()
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        composer?.cancel()
        super.onFinishInput()
    }

    private fun applyPrefs() {
        val c = composer ?: return
        c.setVietnameseOptions(prefs.modernTone, prefs.spellCheck, prefs.restore)
        c.setFullWidthPunctuation(prefs.fullWidth)
        c.setFuzzyRules(prefs.fuzzy.toList())
        c.setTraditional(prefs.traditional)
        c.setLearning(prefs.learn, Core.learnedWordsFile(this).absolutePath)
        // Android: Việt và Anh là một bộ gõ, luôn tự nhận diện; phím quả địa cầu chỉ đổi giữa Việt·Anh và Trung
        c.setAutoSwitch(true)
        if (c.mode() != prefs.mode) c.setMode(prefs.mode)
    }

    // MARK: - Phím

    override fun onKey(key: KeyInput) {
        val ic = currentInputConnection ?: return
        val c = composer
        lastOwnEdit = SystemClock.uptimeMillis()
        if (c == null || passthrough) {
            deliver(ic, key)
            updateShift()
            return
        }
        val before = c.mode()
        val hadWord = c.currentWord().isNotEmpty()
        val wasComposingChinese = c.isComposingChinese()
        val r = c.handleKey(key)
        ic.beginBatchEdit()
        val undo = r.edit
        if (key is KeyInput.Backspace && undo != null) {
            // Backspace ngay sau một lần tự đổi: trả lại chữ trước đó (lõi đã về chế độ cũ)
            ic.finishComposingText()
            ic.deleteSurroundingText(undo.backspaces.toInt(), 0)
            ic.commitText(undo.insert, 1)
        } else when (before) {
            InputMode.VIETNAMESE -> applyVietnamese(ic, key, r, hadWord)
            InputMode.ENGLISH -> applyEnglish(ic, key, r)
            InputMode.CHINESE -> applyChinese(ic, key, r, wasComposingChinese)
        }
        ic.endBatchEdit()
        r.switchedTo?.let { prefs.mode = it }
        refreshUi()
        updateShift()
    }

    private fun applyVietnamese(ic: InputConnection, key: KeyInput, r: KeyOutcome, hadWord: Boolean) {
        val c = composer ?: return
        val isLetter = key is KeyInput.Text && key.text.length == 1 && key.text[0].let { it in 'a'..'z' || it in 'A'..'Z' }
        when {
            isLetter -> ic.setComposingText(c.currentWord(), 1)
            key is KeyInput.Backspace -> if (hadWord) {
                ic.setComposingText(c.currentWord(), 1)
                if (c.currentWord().isEmpty()) ic.finishComposingText()
            } else deliver(ic, key)
            else -> {
                val edit = r.edit
                if (edit != null) {
                    ic.setComposingText(edit.insert, 1)
                    ic.finishComposingText()
                    if (r.repostKey) deliver(ic, key)
                } else {
                    ic.finishComposingText()
                    deliver(ic, key)
                }
            }
        }
    }

    private fun applyEnglish(ic: InputConnection, key: KeyInput, r: KeyOutcome) {
        val edit = r.edit
        if (edit == null) { deliver(ic, key); return }
        ic.deleteSurroundingText(edit.backspaces.toInt(), 0)
        ic.commitText(edit.insert, 1)
        if (r.repostKey) deliver(ic, key)
    }

    private fun applyChinese(ic: InputConnection, key: KeyInput?, r: KeyOutcome, wasComposing: Boolean) {
        val c = composer ?: return
        if (!r.handled) { if (key != null) deliver(ic, key); return }
        // pinyin đang gõ chỉ hiện trong bàn phím (refreshUi); app chỉ nhận chữ Hán đã chọn
        r.edit?.let { ic.commitText(it.insert, 1) }
        if (r.repostKey && key != null) deliver(ic, key)
    }

    /** Phím đi thẳng tới ô nhập như một bàn phím thường. */
    private fun deliver(ic: InputConnection, key: KeyInput) {
        when (key) {
            is KeyInput.Text -> ic.commitText(key.text, 1)
            KeyInput.Space -> space(ic)
            KeyInput.Enter -> if (enterAction != EditorInfo.IME_ACTION_NONE) ic.performEditorAction(enterAction) else sendKeyChar('\n')
            KeyInput.Backspace -> {
                val selected = ic.getSelectedText(0)
                if (!selected.isNullOrEmpty()) ic.commitText("", 1) else sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
            }
            KeyInput.Tab -> sendKeyChar('\t')
            KeyInput.Left -> sendDownUpKeyEvents(KeyEvent.KEYCODE_DPAD_LEFT)
            KeyInput.Right -> sendDownUpKeyEvents(KeyEvent.KEYCODE_DPAD_RIGHT)
            KeyInput.Up -> sendDownUpKeyEvents(KeyEvent.KEYCODE_DPAD_UP)
            KeyInput.Down -> sendDownUpKeyEvents(KeyEvent.KEYCODE_DPAD_DOWN)
            else -> {}
        }
        if (key !is KeyInput.Space) lastSpaceAt = 0
    }

    /** Hai lần cách liền nhau sau một chữ: ". " (như iOS). */
    private fun space(ic: InputConnection) {
        val now = SystemClock.uptimeMillis()
        if (prefs.doubleSpacePeriod && now - lastSpaceAt < 600) {
            val before = ic.getTextBeforeCursor(2, 0)
            if (before != null && before.length == 2 && before[1] == ' ' && before[0].isLetterOrDigit()) {
                ic.deleteSurroundingText(1, 0)
                ic.commitText(". ", 1)
                lastSpaceAt = 0
                return
            }
        }
        ic.commitText(" ", 1)
        lastSpaceAt = now
    }

    override fun onCandidate(index: Int) {
        val c = composer ?: return
        val ic = currentInputConnection ?: return
        lastOwnEdit = SystemClock.uptimeMillis()
        val r = c.selectCandidate(index.toUInt())
        ic.beginBatchEdit()
        applyChinese(ic, null, r, true)
        ic.endBatchEdit()
        refreshUi()
    }

    override fun onCursor(delta: Int) {
        endComposition()
        sendDownUpKeyEvents(if (delta > 0) KeyEvent.KEYCODE_DPAD_RIGHT else KeyEvent.KEYCODE_DPAD_LEFT)
    }

    override fun onSettings() {
        startActivity(Intent(this, SettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // MARK: - Chế độ

    /** Phím quả địa cầu: chạm đổi Việt·Anh ↔ Trung; giữ lâu: menu (hai bộ gõ, bàn phím khác, cài đặt). */
    override fun onPickInput(choice: Int) {
        when (choice) {
            KeyboardView.PICK_VIEN -> if (composer?.mode() == InputMode.CHINESE) setMode(prefs.latin, manual = false)
            KeyboardView.PICK_CHINESE -> if (composer?.mode() != InputMode.CHINESE) setMode(InputMode.CHINESE, manual = false)
            KeyboardView.PICK_TOGGLE -> if (!passthrough) {
                if (composer?.mode() == InputMode.CHINESE) setMode(prefs.latin, manual = false) else setMode(InputMode.CHINESE, manual = false)
            }
            KeyboardView.PICK_SETTINGS -> onSettings()
            KeyboardView.PICK_OTHER_KEYBOARD ->
                (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).showInputMethodPicker()
        }
    }

    /** Android 16+: hệ thống nhờ bàn phím tự hiện nút đổi bàn phím (vì đã ẩn thanh điều hướng của bàn phím). */
    override fun onCustomImeSwitcherButtonRequestedVisible(visible: Boolean) {
        switcherRequested = visible
        keyboard?.showSystemSwitcher = visible
    }

    private fun setMode(mode: InputMode, manual: Boolean) {
        val c = composer ?: return
        endComposition()
        c.setMode(mode)
        if (manual) c.pauseAutoSwitch()
        prefs.mode = mode
        refreshUi()
        updateShift()
    }

    /** Bỏ phần đang gõ: chữ Việt đang gõ giữ lại, pinyin chưa chọn thì xoá. */
    private fun endComposition() {
        val c = composer ?: return
        val ic = currentInputConnection
        ic?.finishComposingText()
        c.cancel()
        refreshUi()
    }

    private fun refreshUi() {
        val kb = keyboard ?: return
        val c = composer
        kb.mode = if (passthrough || c == null) InputMode.ENGLISH else c.mode()
        val chinese = c != null && !passthrough && c.isComposingChinese()
        kb.preedit = if (chinese) c!!.preedit() else ""
        kb.setCandidates(if (chinese) c!!.candidates().map { it.text } else emptyList())
    }

    private fun updateShift() {
        val kb = keyboard ?: return
        if (kb.shift == KeyboardView.Shift.LOCK || kb.layout != KeyboardView.Layout.LETTERS) return
        // tiếng Trung: không tự viết hoa (chữ hoa không phải pinyin, sẽ đi thẳng vào ô nhập)
        val chinese = !passthrough && composer?.mode() == InputMode.CHINESE
        if (!prefs.autoCap || chinese) {
            if (chinese && kb.shift == KeyboardView.Shift.ONCE) kb.shift = KeyboardView.Shift.OFF
            return
        }
        val info = currentInputEditorInfo ?: return
        val caps = currentInputConnection?.getCursorCapsMode(info.inputType) ?: 0
        kb.shift = if (caps != 0 && composer?.currentWord().isNullOrEmpty()) KeyboardView.Shift.ONCE else KeyboardView.Shift.OFF
    }

    // MARK: - Con trỏ bị di chuyển ngoài bàn phím: bỏ phần đang gõ

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int,
                                   candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        if (composer == null) return
        val ours = SystemClock.uptimeMillis() - lastOwnEdit < 300
        // con trỏ rời khỏi chữ đang gõ, hoặc người dùng tự chạm chỗ khác trong ô nhập
        val leftComposing = candidatesStart >= 0 && (newSelStart != candidatesEnd || newSelEnd != candidatesEnd)
        val movedByUser = !ours && candidatesStart < 0 && (newSelStart != oldSelStart || newSelEnd != oldSelEnd)
        if (leftComposing || movedByUser) {
            endComposition()
            updateShift()
        }
    }

    // MARK: - Bàn phím thật (Bluetooth / USB): cùng đường đi qua lõi

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val c = composer
        if (c == null || passthrough || currentInputConnection == null) return super.onKeyDown(keyCode, event)
        if (event.isCtrlPressed || event.isAltPressed || event.isMetaPressed) {
            endComposition()
            return super.onKeyDown(keyCode, event)
        }
        val chinese = c.isComposingChinese()
        val key: KeyInput = when (keyCode) {
            KeyEvent.KEYCODE_DEL -> KeyInput.Backspace
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> KeyInput.Enter
            KeyEvent.KEYCODE_SPACE -> KeyInput.Space
            KeyEvent.KEYCODE_TAB -> if (chinese) KeyInput.Tab else return passKey(keyCode, event)
            KeyEvent.KEYCODE_ESCAPE -> if (chinese) KeyInput.Escape else return passKey(keyCode, event)
            KeyEvent.KEYCODE_DPAD_LEFT -> if (chinese) KeyInput.Left else return passKey(keyCode, event)
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (chinese) KeyInput.Right else return passKey(keyCode, event)
            KeyEvent.KEYCODE_DPAD_UP -> if (chinese) KeyInput.Up else return passKey(keyCode, event)
            KeyEvent.KEYCODE_DPAD_DOWN -> if (chinese) KeyInput.Down else return passKey(keyCode, event)
            KeyEvent.KEYCODE_PAGE_UP -> if (chinese) KeyInput.PageUp else return passKey(keyCode, event)
            KeyEvent.KEYCODE_PAGE_DOWN -> if (chinese) KeyInput.PageDown else return passKey(keyCode, event)
            else -> {
                val u = event.unicodeChar
                if (u == 0 || Character.isISOControl(u)) return passKey(keyCode, event)
                KeyInput.Text(String(Character.toChars(u)))
            }
        }
        hardwareConsumed.add(keyCode)
        onKey(key)
        return true
    }

    private fun passKey(keyCode: Int, event: KeyEvent): Boolean {
        endComposition()
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (hardwareConsumed.remove(keyCode)) return true
        return super.onKeyUp(keyCode, event)
    }

    // MARK: - Kiểm thử tự động (chỉ bản debug): vị trí các phím ghi vào logcat, thẻ ViPiKeys

    override fun onWindowShown() {
        super.onWindowShown()
        if (BuildConfigCompat.debuggable(this)) keyboard?.post { Log.i("ViPiKeys", keyboard?.describeKeys() ?: "") }
    }
}

private object BuildConfigCompat {
    fun debuggable(context: android.content.Context) =
        context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
}
