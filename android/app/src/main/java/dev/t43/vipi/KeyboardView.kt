package dev.t43.vipi

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.RenderNode
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.text.Layout as TextLayout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.WindowInsets
import android.widget.OverScroller
import dev.t43.vipi.core.InputMode
import dev.t43.vipi.core.KeyInput
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Bàn phím ảo tự vẽ theo thiết kế Material 3 của ViPi (vipi-android-ui-spec.md): thanh gợi ý 48 dp
 * (bảng tạm · gợi ý / ứng viên · mic hoặc mở rộng) và 4 hàng phím 48 dp.
 *
 * Phía trên bàn phím có một khoảng trong suốt [overlay] để vẽ menu phím quả địa cầu; nó không nhận chạm
 * (ViPiInputMethod.onComputeInsets) trừ khi menu đang mở, và app phía sau không bị đẩy lên vì nó.
 * Lớp phím tĩnh được ghi một lần vào RenderNode; mỗi khung hình chỉ vẽ thêm phím đang nhấn, bóng chữ, thanh gợi ý.
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context, private val listener: Listener) : View(context) {

    interface Listener {
        fun onKey(key: KeyInput)
        /** Phím quả địa cầu: chạm = PICK_TOGGLE; giữ rồi chọn trong menu = các PICK_ còn lại. */
        fun onPickInput(choice: Int)
        fun onCandidate(index: Int)
        /** Thanh gợi ý tiếng Việt: 0 = đúng các phím đã gõ, 1 = chữ đang hiện. */
        fun onSuggestion(index: Int)
        fun onCursor(delta: Int)
        /** Bảng tạm vừa mở: bộ gõ đọc mục mới chép rồi đặt [clips]. */
        fun onClipboardOpen()
        fun onClipPaste(text: String)
        fun onClipDelete(text: String)
        fun onClipClear()
        fun onVoice()
    }

    companion object {
        const val PICK_VIEN = 0
        const val PICK_CHINESE = 1
        const val PICK_OTHER_KEYBOARD = 2
        const val PICK_SETTINGS = 3
        const val PICK_TOGGLE = 4
        const val PICK_TRADITIONAL = 5
    }

    enum class Layout { LETTERS, NUMBERS, SYMBOLS }
    enum class Shift { OFF, ONCE, LOCK }
    enum class Action { RETURN, SEND, SEARCH, GO, NEXT, DONE }
    enum class Theme { SYSTEM, LIGHT, DARK }
    private enum class Kind { CHAR, SHIFT, BACKSPACE, NUMBERS, LETTERS, SYMBOLS, MODE, SPACE, RETURN, SPACER }

    private class Key(val kind: Kind, val label: String = "", val units: Float = 1f, val hint: String? = null, val punct: Boolean = false) {
        val rect = RectF()
        val isFunction get() = kind != Kind.CHAR && kind != Kind.SPACE && kind != Kind.SPACER
    }

    // MARK: - Trạng thái do bộ gõ đặt

    var layout = Layout.LETTERS
        set(v) { if (field != v) { field = v; buildRows(); dirty() } }
    var shift = Shift.OFF
        set(v) { if (field != v) { field = v; dirty() } }
    var mode = InputMode.VIETNAMESE
        set(v) { if (field != v) { val old = field; field = v; crossfade(old) } }
    var action = Action.RETURN
        set(v) { if (field != v) { field = v; dirty() } }
    /** Ô mật khẩu / số: chỉ tiếng Anh, menu chỉ còn bàn phím khác và cài đặt. */
    var modeLocked = false
        set(v) { if (field != v) { field = v; dirty() } }
    /** Android 16+: hệ thống giao nút đổi bàn phím cho bộ gõ (thanh điều hướng của bàn phím đã ẩn). */
    var showSystemSwitcher = false
    var traditional = false
    var hapticsEnabled = true
    var keyPopup = true
    var fullWidth = true
        set(v) { if (field != v) { field = v; dirty() } }

    fun setAppearance(theme: Theme, materialYou: Boolean) {
        this.theme = theme
        this.materialYou = materialYou
        palette = makePalette()
        dirty()
    }

    class Clip(val text: String, val at: Long)

    /** Các mục bảng tạm, mới nhất trước (tối đa 6). */
    var clips: List<Clip> = emptyList()
        set(v) { field = v; layoutClips(); invalidate() }

    private var candidates: List<String> = emptyList()
    private var suggestKeys = ""
    private var suggestWord = ""

    fun setCandidates(list: List<String>) {
        if (list == candidates) return
        candidates = list
        stripScroll = 0f
        scroller.forceFinished(true)
        if (list.isEmpty()) gridOpen = false
        gridScroll = 0f
        layoutCandidates()
        invalidate()
    }

    /** Từ tiếng Việt đang gõ: các phím đã gõ và chữ đang hiện (rỗng khi không gõ). */
    fun setSuggestions(keys: String, word: String) {
        if (keys == suggestKeys && word == suggestWord) return
        suggestKeys = keys
        suggestWord = word
        invalidate()
    }

    // MARK: - Kích thước (dp → px), theo mục 3.3 của spec

    private val dp = resources.displayMetrics.density
    private val sp = resources.displayMetrics.scaledDensity
    /** Khoảng trong suốt phía trên bàn phím cho menu quả địa cầu. */
    var overlay = 0
        private set
    private var barH = 0f
    private var topGap = 0f
    private var keyH = 0f
    private val gapX = 6 * dp
    private var gapY = 0f
    private var bottomPad = 0f

    /**
     * Cỡ theo chiều cao màn hình: điện thoại dọc phím 48 dp; màn thấp < 760 dp (máy gập mở ngang) 46 dp;
     * điện thoại xoay ngang (< 500 dp) gọn hẳn để app phía sau còn chỗ và cửa sổ bàn phím không cắt mất hàng dưới.
     */
    private fun applyMetrics() {
        val h = resources.configuration.screenHeightDp
        val short = h in 1 until 500
        keyH = (if (short) 38 else if (h in 1 until 760) 46 else 48) * dp
        barH = (if (short) 40 else 48) * dp
        topGap = (if (short) 4 else 6) * dp
        gapY = (if (short) 6 else 8) * dp
        bottomPad = (if (short) 6 else 8) * dp
        overlay = ((if (short) 96 else 124) * dp).toInt()
    }
    private val radius = 8 * dp
    private val sideIcon = 44 * dp
    private var navInset = 0

    private val kbTop get() = overlay.toFloat()
    private val rowsTop get() = kbTop + barH + topGap
    private val rowsBottom get() = rowsTop + 4 * keyH + 3 * gapY
    private var blockL = 0f
    private var blockR = 0f

    // MARK: - Màu (mục 3.1)

    private class Palette(
        val bg: Int, val key: Int, val fn: Int, val text: Int, val hint: Int, val icon: Int,
        val primary: Int, val onPrimary: Int, val container: Int, val onContainer: Int,
        val divider: Int, val shadow: Int, val menu: Int, val popup: Int, val faint: Int, val outline: Int,
    )

    private var theme = Theme.SYSTEM
    private var materialYou = true

    private val isDark: Boolean
        get() = when (theme) {
            Theme.LIGHT -> false
            Theme.DARK -> true
            Theme.SYSTEM -> (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        }

    private fun makePalette(): Palette {
        val dark = isDark
        var primary = if (dark) 0xFFFFB4AB.toInt() else 0xFFA8221C.toInt()
        var onPrimary = if (dark) 0xFF690005.toInt() else 0xFFFFFFFF.toInt()
        var container = if (dark) 0xFF93000A.toInt() else 0xFFFFDAD6.toInt()
        var onContainer = if (dark) 0xFFFFDAD6.toInt() else 0xFF410002.toInt()
        if (materialYou && Build.VERSION.SDK_INT >= 31) {
            // tone 40/80 → accent1_600/200; container tone 90/30 → 100/700; chữ trên đó tone 100/20, 10/90
            val c = context
            fun res(id: Int) = c.getColor(id)
            primary = res(if (dark) android.R.color.system_accent1_200 else android.R.color.system_accent1_600)
            onPrimary = res(if (dark) android.R.color.system_accent1_800 else android.R.color.system_accent1_0)
            container = res(if (dark) android.R.color.system_accent1_700 else android.R.color.system_accent1_100)
            onContainer = res(if (dark) android.R.color.system_accent1_100 else android.R.color.system_accent1_900)
        }
        return if (dark) Palette(
            bg = 0xFF202024.toInt(), key = 0xFF3A3A3F.toInt(), fn = 0xFF2B2B30.toInt(), text = 0xFFE6E1E5.toInt(),
            hint = 0xFFAEAAAE.toInt(), icon = 0xFFCAC4D0.toInt(), primary = primary, onPrimary = onPrimary,
            container = container, onContainer = onContainer, divider = 0xFF48464C.toInt(), shadow = 0x66000000,
            menu = 0xFF2B2930.toInt(), popup = 0xFF4A4A50.toInt(), faint = 0xFF938F99.toInt(), outline = 0xFF938F99.toInt(),
        ) else Palette(
            bg = 0xFFE9E8EC.toInt(), key = 0xFFFFFFFF.toInt(), fn = 0xFFD4D5DA.toInt(), text = 0xFF1C1B1F.toInt(),
            hint = 0xFF5F5E62.toInt(), icon = 0xFF44464E.toInt(), primary = primary, onPrimary = onPrimary,
            container = container, onContainer = onContainer, divider = 0xFFC9C7CC.toInt(), shadow = 0x24000000,
            menu = 0xFFFFFFFF.toInt(), popup = 0xFFFFFFFF.toInt(), faint = 0xFF8E8E93.toInt(), outline = 0xFF79767D.toInt(),
        )
    }

    private var palette = makePalette()

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        palette = makePalette()
        applyMetrics()
        layoutKeys()
        requestLayout()
        dirty()
    }

    // MARK: - Bút vẽ: tạo một lần, không cấp phát trong onDraw

    private val regular = Typeface.create("sans-serif", Typeface.NORMAL)
    private val medium = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    private val bold = Typeface.create("sans-serif", Typeface.BOLD)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val icon = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val text = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }
    private val leftText = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.LEFT }
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val tmp = RectF()
    private var fade: LinearGradient? = null
    private var fadeFor = 0

    /** Biểu tượng vẽ trong ô 24×24 như SVG của thiết kế, phóng theo cỡ khi vẽ. */
    private object Icons {
        val shift = Path().apply { moveTo(12f, 4f); lineTo(20f, 12f); lineTo(15f, 12f); lineTo(15f, 20f); lineTo(9f, 20f); lineTo(9f, 12f); lineTo(4f, 12f); close() }
        val backspace = Path().apply {
            moveTo(9f, 5f); lineTo(20f, 5f); quadTo(22f, 5f, 22f, 7f); lineTo(22f, 17f); quadTo(22f, 19f, 20f, 19f); lineTo(9f, 19f); lineTo(3f, 12f); close()
            moveTo(12f, 9f); lineTo(17f, 15f); moveTo(17f, 9f); lineTo(12f, 15f)
        }
        val enter = Path().apply { moveTo(20f, 5f); lineTo(20f, 11f); quadTo(20f, 13f, 18f, 13f); lineTo(6f, 13f); moveTo(9f, 9f); lineTo(5f, 13f); lineTo(9f, 17f) }
        val send = Path().apply { moveTo(4f, 4f); lineTo(20f, 12f); lineTo(4f, 20f); lineTo(7f, 12f); close() }
        val search = Path().apply { addCircle(11f, 11f, 6.5f, Path.Direction.CW); moveTo(16f, 16f); lineTo(20f, 20f) }
        val arrow = Path().apply { moveTo(5f, 12f); lineTo(19f, 12f); moveTo(13f, 6f); lineTo(19f, 12f); lineTo(13f, 18f) }
        val check = Path().apply { moveTo(5f, 12f); lineTo(10f, 17f); lineTo(20f, 7f) }
        val globe = Path().apply {
            addCircle(12f, 12f, 9f, Path.Direction.CW); moveTo(3f, 12f); lineTo(21f, 12f)
            moveTo(12f, 3f); cubicTo(15f, 6f, 15f, 18f, 12f, 21f); moveTo(12f, 3f); cubicTo(9f, 6f, 9f, 18f, 12f, 21f)
        }
        val clipboard = Path().apply {
            addRoundRect(5f, 4f, 19f, 21f, 2f, 2f, Path.Direction.CW)
            moveTo(9f, 4f); lineTo(9f, 2.5f); lineTo(15f, 2.5f); lineTo(15f, 4f)
            moveTo(9f, 10f); lineTo(15f, 10f); moveTo(9f, 14f); lineTo(13f, 14f)
        }
        val mic = Path().apply {
            addRoundRect(9f, 3f, 15f, 14f, 3f, 3f, Path.Direction.CW)
            moveTo(5f, 11f); arcTo(5f, 4f, 19f, 18f, 180f, -180f, false)
            moveTo(12f, 18f); lineTo(12f, 21f); moveTo(8f, 21f); lineTo(16f, 21f)
        }
        val chevronDown = Path().apply { moveTo(6f, 9f); lineTo(12f, 15f); lineTo(18f, 9f) }
        val chevronUp = Path().apply { moveTo(6f, 15f); lineTo(12f, 9f); lineTo(18f, 15f) }
        val sliders = Path().apply {
            moveTo(4f, 7f); lineTo(12f, 7f); moveTo(18f, 7f); lineTo(20f, 7f); moveTo(4f, 17f); lineTo(6f, 17f); moveTo(12f, 17f); lineTo(20f, 17f)
            addCircle(15f, 7f, 2.5f, Path.Direction.CW); addCircle(9f, 17f, 2.5f, Path.Direction.CW)
        }
        val trash = Path().apply {
            moveTo(4f, 7f); lineTo(20f, 7f); moveTo(9f, 7f); lineTo(9f, 4f); lineTo(15f, 4f); lineTo(15f, 7f)
            moveTo(6f, 7f); lineTo(7f, 20f); lineTo(17f, 20f); lineTo(18f, 7f); moveTo(10f, 11f); lineTo(10f, 16f); moveTo(14f, 11f); lineTo(14f, 16f)
        }
        val keyboard = Path().apply {
            addRoundRect(2.5f, 5.5f, 21.5f, 18.5f, 2f, 2f, Path.Direction.CW)
            for (x in listOf(6.5f, 10.5f, 14.5f, 18.5f)) { moveTo(x - 0.5f, 10f); lineTo(x + 0.5f, 10f) }
            moveTo(8f, 14.5f); lineTo(16f, 14.5f)
        }
    }

    private fun drawIcon(canvas: Canvas, path: Path, cx: Float, cy: Float, sizeDp: Float, color: Int, filled: Boolean = false, alpha: Int = 255) {
        val s = sizeDp * dp / 24f
        canvas.save()
        canvas.translate(cx - 12 * s, cy - 12 * s)
        canvas.scale(s, s)
        icon.style = if (filled) Paint.Style.FILL_AND_STROKE else Paint.Style.STROKE
        icon.strokeWidth = 2f
        icon.color = color
        icon.alpha = alpha * (color ushr 24) / 255
        canvas.drawPath(path, icon)
        canvas.restore()
    }

    // MARK: - Bố cục phím (mục 4.1)

    private var rows: List<List<Key>> = emptyList()

    private fun chars(s: String, units: Float = 1f) = s.map { Key(Kind.CHAR, it.toString(), units) }

    private fun buildRows() {
        val bottom = listOf(
            if (layout == Layout.LETTERS) Key(Kind.NUMBERS, "?123", 1.5f) else Key(Kind.LETTERS, "ABC", 1.5f),
            Key(Kind.MODE),
            Key(Kind.CHAR, ",", punct = true),
            Key(Kind.SPACE, units = 4f),
            Key(Kind.CHAR, ".", punct = true),
            Key(Kind.RETURN, units = 1.5f),
        )
        val third = { left: Key -> listOf(left) + chars(".,?!'", 1.4f) + Key(Kind.BACKSPACE, units = 1.5f) }
        rows = when (layout) {
            Layout.LETTERS -> listOf(
                "qwertyuiop".mapIndexed { i, c -> Key(Kind.CHAR, c.toString(), hint = ((i + 1) % 10).toString()) },
                listOf(Key(Kind.SPACER, units = 0.5f)) + chars("asdfghjkl") + Key(Kind.SPACER, units = 0.5f),
                listOf(Key(Kind.SHIFT, units = 1.5f)) + chars("zxcvbnm") + Key(Kind.BACKSPACE, units = 1.5f),
                bottom,
            )
            Layout.NUMBERS -> listOf(chars("1234567890"), chars("-/:;()$&@\""), third(Key(Kind.SYMBOLS, "#+=", 1.5f)), bottom)
            Layout.SYMBOLS -> listOf(chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"), third(Key(Kind.NUMBERS, "123", 1.5f)), bottom)
        }
        layoutKeys()
    }

    private fun layoutKeys() {
        if (width == 0) return
        // điện thoại: lề 4, phím (W − 8 − 54)/10; màn ≥ 600 dp (máy gập mở, tablet): một khối, phím tối đa 64 dp, canh giữa
        val wide = width / dp >= 600
        val side = (if (wide) 12 else 4) * dp
        var unit = (width - 2 * side + gapX) / 10f
        if (wide) unit = min(unit, 64 * dp + gapX)
        blockL = (width - (10 * unit - gapX)) / 2
        blockR = width - blockL
        rows.forEachIndexed { r, row ->
            var x = blockL - gapX / 2
            val top = rowsTop + r * (keyH + gapY)
            for (k in row) {
                val w = k.units * unit
                k.rect.set(x + gapX / 2, top, x + w - gapX / 2, top + keyH)
                x += w
            }
        }
        layoutCandidates()
        dirty()
    }

    private val handler = Handler(Looper.getMainLooper())

    init {
        applyMetrics()
        buildRows()
        isHapticFeedbackEnabled = true
        setOnApplyWindowInsetsListener { _, insets ->
            val bottom = if (Build.VERSION.SDK_INT >= 30) insets.getInsets(WindowInsets.Type.navigationBars()).bottom
            else @Suppress("DEPRECATION") insets.systemWindowInsetBottom
            if (bottom != navInset) { navInset = bottom; requestLayout() }
            insets
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(w, (rowsBottom + bottomPad + navInset).toInt())
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        layoutKeys()
        fade = null
    }

    // MARK: - Lớp phím tĩnh (RenderNode): chỉ ghi lại khi bố cục, Shift, chế độ hay màu đổi

    private val keysNode: RenderNode? = if (Build.VERSION.SDK_INT >= 29) RenderNode("keys") else null
    private var keysDirty = true

    private fun dirty() {
        keysDirty = true
        invalidate()
    }

    private fun drawKeysLayer(canvas: Canvas) {
        val node = keysNode
        if (node == null || !canvas.isHardwareAccelerated) { drawKeys(canvas); return }
        if (keysDirty || !node.hasDisplayList()) {
            node.setPosition(0, 0, width, height)
            val c = node.beginRecording(width, height)
            drawKeys(c)
            node.endRecording()
            keysDirty = false
        }
        canvas.drawRenderNode(node)
    }

    private fun drawKeys(canvas: Canvas) {
        val p = palette
        fill.color = p.bg
        canvas.drawRect(0f, kbTop, width.toFloat(), height.toFloat(), fill)
        if (gridOpen || clipOpen) return
        for (row in rows) for (k in row) if (k.kind != Kind.SPACER) drawKey(canvas, k, p, 0f)
    }

    // MARK: - Đổi chế độ: nhãn quả địa cầu và phím cách mờ dần trong 120 ms, bố cục không đổi

    private var previousMode = mode
    private var labelFade = 1f
    private var fadeAnimator: ValueAnimator? = null

    private fun crossfade(old: InputMode) {
        previousMode = old
        fadeAnimator?.cancel()
        fadeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 120
            addUpdateListener { labelFade = it.animatedValue as Float; dirty() }
            start()
        }
    }

    private fun chinese(m: InputMode = mode) = m == InputMode.CHINESE && !modeLocked

    // MARK: - Vẽ

    override fun onDraw(canvas: Canvas) {
        val p = palette
        drawKeysLayer(canvas)
        drawBar(canvas, p)
        if (clipOpen) drawClips(canvas, p)
        else if (gridOpen) drawGrid(canvas, p)
        else {
            val now = SystemClock.uptimeMillis()
            var fading = false
            val it = releases.iterator()
            while (it.hasNext()) {
                val (k, at) = it.next()
                val t = (now - at) / 90f
                if (t >= 1f || isPressed(k)) { it.remove(); continue }
                drawKey(canvas, k, p, 1f - t)
                fading = true
            }
            for (i in 0 until pressed.size()) drawKey(canvas, pressed.valueAt(i).key, p, 1f)
            if (menuOpen) rows.last().firstOrNull { it.kind == Kind.MODE }?.let { drawKey(canvas, it, p, 1f) }
            if (keyPopup) for (i in 0 until pressed.size()) {
                val t = pressed.valueAt(i)
                if (t.key.kind == Kind.CHAR && !t.trackpad) drawPopup(canvas, t, p)
            }
            if (fading) postInvalidateOnAnimation()
        }
        if (menuOpen) drawMenu(canvas, p)
    }

    private fun isPressed(k: Key): Boolean {
        for (i in 0 until pressed.size()) if (pressed.valueAt(i).key === k) return true
        return false
    }

    /** `press`: 0 = bình thường, 1 = đang nhấn (nền primary container), ở giữa = đang nhả. */
    private fun drawKey(canvas: Canvas, k: Key, p: Palette, press: Float) {
        val r = k.rect
        val isReturn = k.kind == Kind.RETURN
        val base = when {
            isReturn -> p.primary
            k.isFunction -> p.fn
            else -> p.key
        }
        if (press == 0f) {
            // bóng 1 dp dưới phím
            fill.color = p.shadow
            tmp.set(r.left, r.top + 1 * dp, r.right, r.bottom + 1 * dp)
            canvas.drawRoundRect(tmp, radius, radius, fill)
        }
        fill.color = base
        canvas.drawRoundRect(r, radius, radius, fill)
        var fg = if (isReturn) p.onPrimary else p.text
        var iconColor = if (isReturn) p.onPrimary else p.icon
        if (press > 0f) {
            fill.color = if (isReturn) p.onPrimary else p.container
            fill.alpha = ((if (isReturn) 0.18f else 1f) * press * 255).toInt()
            canvas.drawRoundRect(r, radius, radius, fill)
            if (!isReturn && press > 0.5f) { fg = p.onContainer; iconColor = p.onContainer }
        }
        val cx = r.centerX()
        val cy = r.centerY()
        when (k.kind) {
            Kind.CHAR -> {
                drawText(canvas, keyLabel(k), cx, cy, 22f, fg, regular)
                val hint = keyHint(k)
                if (hint != null) {
                    text.textAlign = Paint.Align.RIGHT
                    text.textSize = 11 * sp
                    text.typeface = regular
                    text.color = p.hint
                    canvas.drawText(hint, r.right - 5 * dp, r.top + 3 * dp - text.fontMetrics.ascent, text)
                    text.textAlign = Paint.Align.CENTER
                }
            }
            Kind.SHIFT -> {
                val color = if (shift == Shift.OFF) iconColor else p.primary
                drawIcon(canvas, Icons.shift, cx, cy - (if (shift == Shift.LOCK) 2 * dp else 0f), 22f, color, filled = shift != Shift.OFF)
                if (shift == Shift.LOCK) {
                    fill.color = p.primary
                    canvas.drawRoundRect(cx - 5 * dp, cy + 10 * dp, cx + 5 * dp, cy + 12 * dp, 1 * dp, 1 * dp, fill)
                }
            }
            Kind.BACKSPACE -> drawIcon(canvas, Icons.backspace, cx, cy, 22f, iconColor)
            Kind.RETURN -> drawIcon(canvas, when (action) {
                Action.SEND -> Icons.send
                Action.SEARCH -> Icons.search
                Action.GO, Action.NEXT -> Icons.arrow
                Action.DONE -> Icons.check
                Action.RETURN -> Icons.enter
            }, cx, cy, 22f, iconColor)
            Kind.MODE -> {
                if (modeLocked) drawIcon(canvas, Icons.globe, cx, cy, 20f, iconColor)
                else {
                    drawIcon(canvas, Icons.globe, cx, cy - 6.5f * dp, 18f, iconColor)
                    val a = labelFade
                    if (a < 1f) drawText(canvas, globeLabel(previousMode), cx, cy + 12 * dp, 10f, iconColor, bold, 1f - a, 0.04f)
                    drawText(canvas, globeLabel(mode), cx, cy + 12 * dp, 10f, iconColor, bold, a, 0.04f)
                }
            }
            Kind.SPACE -> {
                val a = labelFade
                if (a < 1f) drawText(canvas, spaceLabel(previousMode), cx, cy, 12f, p.hint, medium, 1f - a, 0.06f)
                drawText(canvas, spaceLabel(mode), cx, cy, 12f, p.hint, medium, a, 0.06f)
            }
            else -> drawText(canvas, k.label, cx, cy, 14f, fg, medium)
        }
    }

    private fun keyLabel(k: Key): String = when {
        k.punct && chinese() && fullWidth -> if (k.label == ",") "，" else "。"
        layout == Layout.LETTERS && shift != Shift.OFF -> k.label.uppercase()
        else -> k.label
    }

    private fun keyHint(k: Key): String? = when {
        layout != Layout.LETTERS -> null
        k.hint != null -> k.hint
        k.label == "v" && chinese() -> "ü"
        else -> null
    }

    private fun globeLabel(m: InputMode) = if (chinese(m)) "拼" else "VI"
    private fun spaceLabel(m: InputMode) = when {
        modeLocked -> "space"
        chinese(m) -> "拼音"
        else -> "VI · EN"
    }

    private fun drawText(canvas: Canvas, s: String, cx: Float, cy: Float, size: Float, color: Int, face: Typeface,
                         alpha: Float = 1f, spacing: Float = 0f) {
        text.textSize = size * sp
        text.typeface = face
        text.letterSpacing = spacing
        text.color = color
        text.alpha = (alpha * (color ushr 24)).toInt()
        val fm = text.fontMetrics
        canvas.drawText(s, cx, cy - (fm.ascent + fm.descent) / 2, text)
        text.letterSpacing = 0f
    }

    /** Bóng chữ khi nhấn: cao 60, rộng phím + 16, đáy cách đáy phím 36 dp (phủ đầu phím), chữ 30 sp. */
    private fun drawPopup(canvas: Canvas, t: Touch, p: Palette) {
        val k = t.key
        val w = k.rect.width() + 16 * dp
        val h = 60 * dp
        val left = (k.rect.centerX() - w / 2).coerceIn(2 * dp, width - w - 2 * dp)
        val bottom = k.rect.bottom - 36 * dp
        tmp.set(left, bottom - h, left + w, bottom)
        shadowPaint.color = p.popup
        shadowPaint.setShadowLayer(4 * dp, 0f, 2 * dp, 0x47000000)
        canvas.drawRoundRect(tmp, 10 * dp, 10 * dp, shadowPaint)
        val label = if (t.longFired) k.hint ?: keyLabel(k) else keyLabel(k)
        drawText(canvas, label, tmp.centerX(), tmp.centerY(), 30f, p.text, regular)
    }

    // MARK: - Thanh gợi ý (mục 5): [bảng tạm 44] [giữa] [mic / mở rộng 44]

    private val barTop get() = kbTop
    private val midL get() = blockL + sideIcon + 2 * dp
    private val midR get() = blockR - sideIcon - 2 * dp

    private var candidateRects: List<RectF> = emptyList()
    private val scroller = OverScroller(context)
    private var stripScroll = 0f
    private var stripContentWidth = 0f

    private fun layoutCandidates() {
        var x = midL + 2 * dp
        val cy = barTop + barH / 2
        candidateRects = candidates.mapIndexed { i, c ->
            text.textSize = 19 * sp; text.typeface = medium
            var w = text.measureText(c) + 24 * dp
            if (i < 9) { text.textSize = 11 * sp; text.typeface = regular; w += text.measureText("${i + 1}") + 5 * dp }
            RectF(x, cy - 18 * dp, x + w, cy + 18 * dp).also { x += w + 4 * dp }
        }
        stripContentWidth = x - midL
        layoutGrid()
    }

    private fun drawBar(canvas: Canvas, p: Palette) {
        val cy = barTop + barH / 2
        val l = blockL + sideIcon / 2
        val r = blockR - sideIcon / 2
        if (clipOpen) {
            // tiêu đề bảng tạm: [về bàn phím] Clipboard BETA [xoá hết]
            if (barPressed == BAR_CLIP) pressedCircle(canvas, l, cy, p)
            drawIcon(canvas, Icons.keyboard, l, cy, 22f, p.icon)
            if (barPressed == BAR_RIGHT) pressedCircle(canvas, r, cy, p)
            drawIcon(canvas, Icons.trash, r, cy, 22f, p.icon, alpha = if (clips.isEmpty()) 97 else 255)
            leftText.textSize = 16 * sp; leftText.typeface = medium; leftText.color = p.text
            val fm = leftText.fontMetrics
            val x = midL + 8 * dp
            canvas.drawText("Clipboard", x, cy - (fm.ascent + fm.descent) / 2, leftText)
            val bx = x + leftText.measureText("Clipboard") + 8 * dp
            leftText.textSize = 10 * sp; leftText.typeface = bold
            val bw = leftText.measureText("BETA") + 12 * dp
            fill.color = p.container
            canvas.drawRoundRect(bx, cy - 10 * dp, bx + bw, cy + 10 * dp, 10 * dp, 10 * dp, fill)
            leftText.color = p.onContainer
            val bfm = leftText.fontMetrics
            canvas.drawText("BETA", bx + 6 * dp, cy - (bfm.ascent + bfm.descent) / 2, leftText)
            return
        }
        if (barPressed == BAR_CLIP) pressedCircle(canvas, l, cy, p)
        drawIcon(canvas, Icons.clipboard, l, cy, 22f, p.icon)
        if (candidates.isNotEmpty()) {
            if (barPressed == BAR_RIGHT) pressedCircle(canvas, r, cy, p)
            drawIcon(canvas, if (gridOpen) Icons.chevronUp else Icons.chevronDown, r, cy, 22f, p.icon)
            drawCandidates(canvas, p)
        } else {
            drawIcon(canvas, Icons.mic, r, cy, 22f, p.icon, alpha = 97)   // v1: chưa có, mờ 38%
            drawSuggestions(canvas, p)
        }
    }

    private fun pressedCircle(canvas: Canvas, cx: Float, cy: Float, p: Palette) {
        fill.color = p.text
        fill.alpha = 0x1F
        canvas.drawCircle(cx, cy, 20 * dp, fill)
    }

    private fun drawCandidates(canvas: Canvas, p: Palette) {
        canvas.save()
        canvas.clipRect(midL, barTop, midR, barTop + barH)
        canvas.translate(-stripScroll, 0f)
        candidateRects.forEachIndexed { i, r ->
            if (r.right < midL + stripScroll || r.left > midR + stripScroll) return@forEachIndexed
            val first = i == 0
            if (first || i == pressedCandidate) {
                fill.color = if (first) p.container else p.text
                if (!first) fill.alpha = 0x1F
                canvas.drawRoundRect(r, radius, radius, fill)
            }
            var x = r.left + 12 * dp
            val base = r.centerY()
            if (i < 9) {
                leftText.textSize = 11 * sp; leftText.typeface = regular
                leftText.color = if (first) p.onContainer else p.faint
                if (first) leftText.alpha = 0xCC
                val n = "${i + 1}"
                canvas.drawText(n, x, base + 5.5f * sp, leftText)
                x += leftText.measureText(n) + 5 * dp
            }
            leftText.textSize = 19 * sp; leftText.typeface = medium
            leftText.color = if (first) p.onContainer else p.text
            val fm = leftText.fontMetrics
            canvas.drawText(candidates[i], x, base - (fm.ascent + fm.descent) / 2, leftText)
        }
        canvas.restore()
        // mép phải mờ dần báo còn ứng viên
        if (stripContentWidth - stripScroll > midR - midL) {
            if (fade == null || fadeFor != p.bg) {
                fade = LinearGradient(midR - 28 * dp, 0f, midR, 0f, p.bg and 0x00FFFFFF, p.bg, Shader.TileMode.CLAMP)
                fadeFor = p.bg
            }
            fill.shader = fade
            canvas.drawRect(midR - 28 * dp, barTop, midR, barTop + barH, fill)
            fill.shader = null
        }
    }

    /** Ba ô chia đều: [các phím đã gõ] · **chữ đang hiện** · [trống]. Không có gợi ý thì để trống, không bịa. */
    private fun suggestionCells(): List<String> = when {
        suggestWord.isEmpty() -> emptyList()
        suggestKeys == suggestWord || suggestKeys.isEmpty() -> listOf("", suggestWord, "")
        else -> listOf(suggestKeys, suggestWord, "")
    }

    private fun drawSuggestions(canvas: Canvas, p: Palette) {
        val cells = suggestionCells()
        if (cells.isEmpty()) return
        val w = (midR - midL) / 3
        val cy = barTop + barH / 2
        cells.forEachIndexed { i, s ->
            if (s.isEmpty()) return@forEachIndexed
            val l = midL + i * w
            if (i == pressedSuggestion) {
                fill.color = p.text; fill.alpha = 0x1F
                canvas.drawRoundRect(l + 2 * dp, cy - 18 * dp, l + w - 2 * dp, cy + 18 * dp, radius, radius, fill)
            }
            text.textSize = 16 * sp
            text.typeface = if (i == 1) bold else regular
            val shown = TextUtils.ellipsize(s, text, w - 12 * dp, TextUtils.TruncateAt.START).toString()
            drawText(canvas, shown, l + w / 2, cy, 16f, p.text, if (i == 1) bold else regular)
            if (i == 0) {
                fill.color = p.divider
                canvas.drawRect(l + w - 0.5f * dp, cy - 11 * dp, l + w + 0.5f * dp, cy + 11 * dp, fill)
            }
        }
    }

    // MARK: - Lưới ứng viên: thay chỗ các hàng phím, cuộn dọc

    private var gridOpen = false
        set(v) { if (field != v) { field = v; gridScroll = 0f; dirty() } }
    private var gridRects: List<RectF> = emptyList()
    private var gridScroll = 0f
    private var gridContentHeight = 0f
    private val gridTop get() = rowsTop - topGap / 2
    private val gridBottom get() = rowsBottom + bottomPad / 2

    private fun layoutGrid() {
        val cell = 48 * dp
        val pad = 3 * dp
        var x = blockL
        var y = gridTop + pad
        val rects = ArrayList<RectF>(candidates.size)
        text.textSize = 20 * sp; text.typeface = medium
        for (c in candidates) {
            val w = max(text.measureText(c) + 28 * dp, (blockR - blockL) / 6 - pad)
            if (x + w > blockR + 0.5f && x > blockL) { x = blockL; y += cell + pad }
            rects += RectF(x, y, min(x + w, blockR), y + cell)
            x += w + pad
        }
        // hàng đầy (trừ hàng cuối): chia phần thừa cho các ô để hai mép thẳng hàng
        rects.groupBy { it.top }.values.toList().dropLast(1).forEach { row ->
            val extra = (blockR - row.last().right) / row.size
            row.forEachIndexed { j, r -> r.left += extra * j; r.right += extra * (j + 1) }
        }
        gridRects = rects
        gridContentHeight = (rects.lastOrNull()?.bottom ?: gridTop) - gridTop + pad
    }

    private fun drawGrid(canvas: Canvas, p: Palette) {
        canvas.save()
        canvas.clipRect(0f, gridTop, width.toFloat(), gridBottom)
        canvas.translate(0f, -gridScroll)
        gridRects.forEachIndexed { i, r ->
            if (r.bottom < gridTop + gridScroll || r.top > gridBottom + gridScroll) return@forEachIndexed
            fill.color = if (i == 0) p.container else p.key
            canvas.drawRoundRect(r, radius, radius, fill)
            if (i == pressedCandidate) { fill.color = p.text; fill.alpha = 0x1F; canvas.drawRoundRect(r, radius, radius, fill) }
            drawText(canvas, candidates[i], r.centerX(), r.centerY(), 20f, if (i == 0) p.onContainer else p.text, medium)
        }
        canvas.restore()
    }

    // MARK: - Bảng tạm: thay chỗ các hàng phím, lưới 2 × 3, chạm = dán, giữ = xoá

    private var clipOpen = false
        set(v) { if (field != v) { field = v; if (v) gridOpen = false; layoutClips(); dirty() } }
    private var clipRects: List<RectF> = emptyList()
    private var clipLayouts: List<StaticLayout> = emptyList()
    private var pressedClip = -1
    private var clipHold: Runnable? = null

    private fun layoutClips() {
        val gap = 6 * dp
        val n = min(clips.size, ClipHistory.MAX)
        val w = (blockR - blockL - gap) / 2
        val h = (gridBottom - gridTop - 2 * gap) / 3
        clipRects = (0 until n).map { i ->
            val x = blockL + (i % 2) * (w + gap)
            val y = gridTop + (i / 2) * (h + gap)
            RectF(x, y, x + w, y + h)
        }
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 14 * sp; typeface = regular }
        val inner = max(1, (w - 24 * dp).toInt())
        // hai dòng chữ cần ô cao ~70 dp (cùng dòng thời gian); điện thoại xoay ngang chỉ đủ một dòng
        val lines = if (h >= 68 * dp) 2 else 1
        clipLayouts = (0 until n).map { i ->
            val t = clips[i].text.replace(Regex("\\s+"), " ").trim()
            StaticLayout.Builder.obtain(t, 0, t.length, paint, inner)
                .setMaxLines(lines).setEllipsize(TextUtils.TruncateAt.END).setIncludePad(false)
                .setAlignment(TextLayout.Alignment.ALIGN_NORMAL).build()
        }
    }

    private fun ago(at: Long): String {
        val m = ((System.currentTimeMillis() - at) / 60_000).toInt()
        return if (m < 1) "Just now" else "$m min ago"
    }

    private fun drawClips(canvas: Canvas, p: Palette) {
        if (clipRects.isEmpty()) {
            val cy = (gridTop + gridBottom) / 2
            drawText(canvas, "Copied text shows up here", width / 2f, cy - 12 * dp, 15f, p.text, medium)
            drawText(canvas, "Tap to paste · Hold to delete · Kept for 1 hour on this phone", width / 2f, cy + 14 * dp, 12f, p.hint, regular)
            return
        }
        clipRects.forEachIndexed { i, r ->
            fill.color = p.shadow
            tmp.set(r.left, r.top + 1 * dp, r.right, r.bottom + 1 * dp)
            canvas.drawRoundRect(tmp, 12 * dp, 12 * dp, fill)
            fill.color = if (i == pressedClip) p.container else p.key
            canvas.drawRoundRect(r, 12 * dp, 12 * dp, fill)
            val layout = clipLayouts[i]
            layout.paint.color = if (i == pressedClip) p.onContainer else p.text
            canvas.save()
            canvas.translate(r.left + 12 * dp, r.top + 9 * dp)
            layout.draw(canvas)
            canvas.restore()
            leftText.textSize = 11 * sp; leftText.typeface = regular; leftText.color = p.hint
            canvas.drawText(ago(clips[i].at), r.left + 12 * dp, r.bottom - 8 * dp, leftText)
        }
    }

    private fun clipAt(x: Float, y: Float) = clipRects.indexOfFirst { it.contains(x, y) }

    // MARK: - Chạm

    private class Touch(var key: Key, val startX: Float, var lastX: Float) {
        var trackpad = false
        var longFired = false
        var longPress: Runnable? = null
    }

    private val pressed = android.util.SparseArray<Touch>()
    private val releases = ArrayList<Pair<Key, Long>>()
    private var lastShiftTap = 0L

    private val BAR_CLIP = 0
    private val BAR_MID = 1
    private val BAR_RIGHT = 2
    private val BAR_GRID = 3
    private val BAR_CLIPS = 4
    private var barTouch = -1          // ngón đang chạm thanh gợi ý / lưới ứng viên
    private var barRegion = -1
    private var barPressed = -1
    private var barDownX = 0f
    private var barDownY = 0f
    private var barDownScroll = 0f
    private var barDragged = false
    private var pressedCandidate = -1
    private var pressedSuggestion = -1
    private var velocity: VelocityTracker? = null

    private val repeatBackspace = object : Runnable {
        override fun run() {
            listener.onKey(KeyInput.Backspace)
            feedback()
            handler.postDelayed(this, 50)
        }
    }

    private fun hit(x: Float, y: Float): Key? {
        if (y < rowsTop - topGap) return null
        val r = ((y - rowsTop + gapY / 2) / (keyH + gapY)).toInt().coerceIn(0, rows.size - 1)
        var best: Key? = null
        var bestD = Float.MAX_VALUE
        for (k in rows[r]) {
            if (k.kind == Kind.SPACER) continue
            val d = if (x < k.rect.left) k.rect.left - x else if (x > k.rect.right) x - k.rect.right else 0f
            if (d < bestD) { bestD = d; best = k }
        }
        return best
    }

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31)
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    else @Suppress("DEPRECATION") context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    private val tick: VibrationEffect? = if (Build.VERSION.SDK_INT >= 29) VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK) else null

    /**
     * Rung khi nhấn: hiệu ứng bàn phím của máy (đã được hãng tinh chỉnh). Nếu hệ thống tắt "phản hồi chạm" thì
     * performHapticFeedback không rung; cài đặt "Vibrate on key press" của ViPi vẫn bật nên rung một nhịp ngắn.
     */
    private fun feedback() {
        if (!hapticsEnabled) return
        if (performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)) return
        val v = vibrator ?: return
        if (tick != null) v.vibrate(tick)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val i = e.actionIndex
        val id = e.getPointerId(i)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val x = e.getX(i)
                val y = e.getY(i)
                if (menuOpen) {
                    // menu đang mở: chạm vào mục để chọn, chạm chỗ khác để đóng
                    val m = menuItemAt(x, y)
                    if (m >= 0) { menuHighlight = m; menuPointer = id } else closeMenu()
                    invalidate()
                    return true
                }
                if (pressed.size() == 0 && barTouch < 0 && (y < rowsTop - topGap || (gridOpen || clipOpen) && y < gridBottom)) {
                    if (y < barTop) return true
                    barTouch = id
                    barDownX = x; barDownY = y
                    barDragged = false
                    barRegion = when {
                        y >= barTop + barH -> if (clipOpen) BAR_CLIPS else BAR_GRID
                        x < blockL + sideIcon -> BAR_CLIP
                        x > blockR - sideIcon -> BAR_RIGHT
                        else -> BAR_MID
                    }
                    barPressed = if (barRegion == BAR_CLIP || barRegion == BAR_RIGHT && (candidates.isNotEmpty() || clipOpen)) barRegion else -1
                    if (barRegion == BAR_CLIPS) {
                        pressedClip = clipAt(x, y)
                        if (pressedClip >= 0) {
                            val text = clips[pressedClip].text
                            clipHold = Runnable {
                                clipHold = null
                                barDragged = true   // giữ: xoá, không dán khi nhả
                                pressedClip = -1
                                feedback()
                                listener.onClipDelete(text)
                            }.also { handler.postDelayed(it, 500) }
                        }
                    } else if (barRegion == BAR_GRID) { barDownScroll = gridScroll; pressedCandidate = gridAt(x, y) }
                    else if (barRegion == BAR_MID) {
                        barDownScroll = stripScroll
                        scroller.forceFinished(true)
                        if (candidates.isNotEmpty()) pressedCandidate = candidateAt(x)
                        else pressedSuggestion = suggestionAt(x)
                    }
                    velocity = VelocityTracker.obtain().also { it.addMovement(e) }
                    invalidate()
                    return true
                }
                if (gridOpen || clipOpen) return true
                val k = hit(x, y) ?: return true
                // ngón thứ hai chạm: phím của ngón trước được gõ luôn (gõ nhanh hai tay). Cả phím quả địa cầu:
                // chạm quả địa cầu rồi gõ ngay "n" thì đổi bộ gõ trước, "n" mới vào bộ gõ mới
                for (j in pressed.size() - 1 downTo 0) {
                    val t = pressed.valueAt(j)
                    if (t.key.kind == Kind.CHAR || t.key.kind == Kind.SPACE || t.key.kind == Kind.MODE) {
                        t.longPress?.let { handler.removeCallbacks(it) }
                        if (!t.trackpad && !t.longFired) fire(t.key)
                        release(t.key)
                        pressed.removeAt(j)
                    }
                }
                feedback()
                val touch = Touch(k, x, x)
                when (k.kind) {
                    Kind.SHIFT -> { tapShift(); release(k); return true }
                    Kind.MODE -> handler.postDelayed(Runnable { holdGlobe(k, id) }.also { globeHold = it }, 300)
                    Kind.BACKSPACE -> {
                        listener.onKey(KeyInput.Backspace)
                        handler.postDelayed(repeatBackspace, 400)
                    }
                    Kind.CHAR -> if (keyHint(k)?.let { it[0].isDigit() } == true) {
                        // giữ phím hàng trên: gõ số ở góc phím thay cho chữ
                        touch.longPress = Runnable {
                            if (pressed.get(id) === touch && touch.key === k) {
                                touch.longFired = true
                                feedback()
                                listener.onKey(KeyInput.Text(k.hint!!))
                                invalidate()
                            }
                        }.also { handler.postDelayed(it, 400) }
                    }
                    else -> {}
                }
                pressed.put(id, touch)
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                if (menuOpen && menuPointer >= 0) {
                    // giữ phím quả địa cầu rồi trượt lên mục cần chọn
                    val idx = e.findPointerIndex(menuPointer)
                    if (idx >= 0) {
                        val m = menuItemAt(e.getX(idx), e.getY(idx))
                        if (m != menuHighlight) { menuHighlight = m; if (m >= 0) feedback(); invalidate() }
                    }
                    return true
                }
                if (barTouch >= 0) {
                    velocity?.addMovement(e)
                    val idx = e.findPointerIndex(barTouch)
                    if (idx < 0) return true
                    if (barRegion == BAR_MID && candidates.isNotEmpty()) {
                        val dx = e.getX(idx) - barDownX
                        if (abs(dx) > 8 * dp) { barDragged = true; pressedCandidate = -1 }
                        if (barDragged) {
                            stripScroll = (barDownScroll - dx).coerceIn(0f, max(0f, stripContentWidth - (midR - midL)))
                            invalidate()
                        }
                    } else if (barRegion == BAR_CLIPS) {
                        if (abs(e.getX(idx) - barDownX) > 12 * dp || abs(e.getY(idx) - barDownY) > 12 * dp) {
                            clipHold?.let { handler.removeCallbacks(it) }; clipHold = null
                            barDragged = true; pressedClip = -1; invalidate()
                        }
                    } else if (barRegion == BAR_GRID) {
                        val dy = e.getY(idx) - barDownY
                        if (abs(dy) > 8 * dp) { barDragged = true; pressedCandidate = -1 }
                        if (barDragged) {
                            gridScroll = (barDownScroll - dy).coerceIn(0f, max(0f, gridContentHeight - (gridBottom - gridTop)))
                            invalidate()
                        }
                    }
                    return true
                }
                for (j in 0 until pressed.size()) {
                    val t = pressed.valueAt(j)
                    val idx = e.findPointerIndex(pressed.keyAt(j))
                    if (idx < 0) continue
                    val x = e.getX(idx)
                    val y = e.getY(idx)
                    if (t.key.kind == Kind.SPACE) {
                        // kéo trên phím cách: di chuyển con trỏ
                        if (!t.trackpad && abs(x - t.startX) > 14 * dp) { t.trackpad = true; t.lastX = x; invalidate() }
                        if (t.trackpad) {
                            val step = 11 * dp
                            while (x - t.lastX > step) { listener.onCursor(1); t.lastX += step }
                            while (t.lastX - x > step) { listener.onCursor(-1); t.lastX -= step }
                        }
                    } else if (t.key.kind == Kind.CHAR && !t.longFired) {
                        val k = hit(x, y)
                        if (k != null && k !== t.key && k.kind == Kind.CHAR) {
                            t.longPress?.let { handler.removeCallbacks(it) }
                            t.longPress = null
                            t.key = k
                            invalidate()
                        }
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (menuOpen && id == menuPointer) {
                    menuPointer = -1
                    // thả trên một mục: chọn; thả trên phím quả địa cầu: menu vẫn mở để chạm chọn
                    if (menuHighlight >= 0) {
                        val choice = menuItems[menuHighlight].choice
                        closeMenu()
                        listener.onPickInput(choice)
                    }
                    invalidate()
                    return true
                }
                if (id == barTouch) {
                    finishBarTouch(e, i)
                    return true
                }
                val t = pressed.get(id)
                if (t != null) {
                    pressed.remove(id)
                    t.longPress?.let { handler.removeCallbacks(it) }
                    if (t.key.kind == Kind.BACKSPACE) handler.removeCallbacks(repeatBackspace)
                    else if (!t.trackpad && !t.longFired) fire(t.key)
                    if (t.key.kind == Kind.MODE) cancelGlobeHold()
                    release(t.key)
                    invalidate()
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                cancelGlobeHold()
                closeMenu()
                for (j in 0 until pressed.size()) pressed.valueAt(j).longPress?.let { handler.removeCallbacks(it) }
                pressed.clear()
                handler.removeCallbacks(repeatBackspace)
                velocity?.recycle(); velocity = null
                clipHold?.let { handler.removeCallbacks(it) }; clipHold = null
                barTouch = -1; barPressed = -1; pressedCandidate = -1; pressedSuggestion = -1; pressedClip = -1
                invalidate()
            }
        }
        return true
    }

    private fun finishBarTouch(e: MotionEvent, i: Int) {
        val x = e.getX(i)
        val y = e.getY(i)
        velocity?.let {
            it.addMovement(e)
            it.computeCurrentVelocity(1000)
            if (barDragged && barRegion == BAR_MID) {
                scroller.fling(stripScroll.toInt(), 0, -it.xVelocity.toInt(), 0, 0,
                    max(0f, stripContentWidth - (midR - midL)).toInt(), 0, 0)
                postInvalidateOnAnimation()
            }
            it.recycle()
        }
        velocity = null
        clipHold?.let { handler.removeCallbacks(it) }
        clipHold = null
        if (!barDragged) when (barRegion) {
            BAR_CLIP -> if (x < blockL + sideIcon) {
                feedback()
                if (!clipOpen) listener.onClipboardOpen()
                clipOpen = !clipOpen
            }
            BAR_RIGHT -> if (x > blockR - sideIcon) {
                feedback()
                when {
                    clipOpen -> if (clips.isNotEmpty()) listener.onClipClear()
                    candidates.isNotEmpty() -> gridOpen = !gridOpen
                    else -> listener.onVoice()
                }
            }
            BAR_CLIPS -> {
                val c = clipAt(x, y)
                if (c >= 0 && c == pressedClip) { feedback(); val t = clips[c].text; clipOpen = false; listener.onClipPaste(t) }
            }
            BAR_MID -> if (candidates.isNotEmpty()) {
                val c = candidateAt(x)
                if (c >= 0 && c == pressedCandidate) { feedback(); listener.onCandidate(c) }
            } else {
                val s = suggestionAt(x)
                if (s >= 0 && s == pressedSuggestion) { feedback(); listener.onSuggestion(if (s == 0) 0 else 1) }
            }
            BAR_GRID -> {
                val c = gridAt(x, y)
                if (c >= 0 && c == pressedCandidate) { feedback(); gridOpen = false; listener.onCandidate(c) }
            }
        }
        barTouch = -1
        barPressed = -1
        pressedCandidate = -1
        pressedSuggestion = -1
        pressedClip = -1
        invalidate()
    }

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            stripScroll = scroller.currX.toFloat()
            postInvalidateOnAnimation()
        }
    }

    private fun candidateAt(x: Float): Int {
        if (x < midL || x > midR) return -1
        val cx = x + stripScroll
        return candidateRects.indexOfFirst { cx >= it.left - 2 * dp && cx <= it.right + 2 * dp }
    }

    private fun gridAt(x: Float, y: Float): Int {
        val gy = y + gridScroll
        return gridRects.indexOfFirst { it.contains(x, gy) }
    }

    private fun suggestionAt(x: Float): Int {
        val cells = suggestionCells()
        if (cells.isEmpty() || x < midL || x > midR) return -1
        val i = ((x - midL) / ((midR - midL) / 3)).toInt().coerceIn(0, 2)
        return if (cells[i].isNotEmpty()) i else -1
    }

    private fun release(k: Key) {
        releases.removeAll { it.first === k }
        releases += k to SystemClock.uptimeMillis()
        postInvalidateOnAnimation()
    }

    private fun tapShift() {
        val now = SystemClock.uptimeMillis()
        shift = when (shift) {
            Shift.LOCK -> Shift.OFF
            Shift.OFF -> Shift.ONCE
            Shift.ONCE -> if (now - lastShiftTap < 350) Shift.LOCK else Shift.OFF
        }
        lastShiftTap = now
    }

    private fun fire(k: Key) {
        when (k.kind) {
            Kind.CHAR -> {
                val s = if (layout == Layout.LETTERS && shift != Shift.OFF && !k.punct) k.label.uppercase() else k.label
                if (shift == Shift.ONCE && layout == Layout.LETTERS && !k.punct) shift = Shift.OFF
                listener.onKey(KeyInput.Text(s))
                if (layout != Layout.LETTERS && s == "'") layout = Layout.LETTERS
            }
            Kind.SPACE -> {
                listener.onKey(KeyInput.Space)
                if (layout != Layout.LETTERS) layout = Layout.LETTERS
            }
            Kind.RETURN -> listener.onKey(KeyInput.Enter)
            Kind.NUMBERS -> layout = Layout.NUMBERS
            Kind.SYMBOLS -> layout = Layout.SYMBOLS
            Kind.LETTERS -> layout = Layout.LETTERS
            Kind.MODE -> { cancelGlobeHold(); listener.onPickInput(PICK_TOGGLE) }
            else -> {}
        }
    }

    private var globeHold: Runnable? = null

    private fun cancelGlobeHold() {
        globeHold?.let { handler.removeCallbacks(it) }
        globeHold = null
    }

    /** Giữ phím quả địa cầu 300 ms: thay cho lần chạm, mở menu (vẫn trượt ngón lên để chọn được). */
    private fun holdGlobe(globe: Key, pointer: Int) {
        globeHold = null
        if (pressed.get(pointer)?.key !== globe) return
        pressed.remove(pointer)
        feedback()
        openMenu(globe, pointer)
    }

    // MARK: - Menu phím quả địa cầu (artboard "Giữ phím Globe")

    private enum class Row { HEADER, ITEM, DIVIDER, SWITCH, ACTION }
    private class MenuItem(val row: Row, val choice: Int = -1, val title: String = "", val subtitle: String? = null,
                           val checked: Boolean = false, val icon: Path? = null)

    var menuOpen = false
        private set
    private var menuItems: List<MenuItem> = emptyList()
    private val menuRects = mutableListOf<RectF>()
    private val menuBox = RectF()
    private var menuHighlight = -1
    private var menuPointer = -1

    private fun openMenu(globe: Key, pointer: Int) {
        val items = mutableListOf<MenuItem>()
        if (!modeLocked) {
            items += MenuItem(Row.HEADER, title = "INPUT LANGUAGE")
            items += MenuItem(Row.ITEM, PICK_VIEN, "Tiếng Việt · English", "Telex · detects English as you type", mode != InputMode.CHINESE)
            items += MenuItem(Row.ITEM, PICK_CHINESE, "中文 · 拼音", "Full pinyin, initials, fuzzy pinyin", mode == InputMode.CHINESE)
            items += MenuItem(Row.DIVIDER)
            items += MenuItem(Row.SWITCH, PICK_TRADITIONAL, "Traditional (繁體)", checked = traditional)
        }
        if (showSystemSwitcher || modeLocked) items += MenuItem(Row.ACTION, PICK_OTHER_KEYBOARD, "Other keyboards", icon = Icons.keyboard)
        items += MenuItem(Row.ACTION, PICK_SETTINGS, "ViPi Settings", icon = Icons.sliders)
        val pad = 8 * dp
        var bottom = globe.rect.top - 14 * dp   // trên hàng dưới cùng: thả tay tại phím quả địa cầu không chọn nhầm
        fun heightsOf(list: List<MenuItem>, compact: Boolean) = list.map {
            when (it.row) {
                Row.HEADER -> 30 * dp
                Row.ITEM -> (if (compact) 48 else 56) * dp
                Row.DIVIDER -> (if (compact) 9 else 17) * dp
                else -> (if (compact) 40 else 48) * dp
            }
        }
        var heights = heightsOf(items, false)
        // không đủ chỗ phía trên (điện thoại xoay ngang): bỏ tiêu đề, thu gọn các dòng
        if (heights.sum() + 2 * pad > bottom - 2 * dp) {
            items.removeAll { it.row == Row.HEADER }
            heights = heightsOf(items, true)
        }
        menuItems = items
        val h = heights.sum() + 2 * pad
        val w = min(292 * dp, blockR - blockL - 16 * dp)
        var left = blockL + 8 * dp
        if (h > bottom - 2 * dp) {
            // vẫn không vừa: đặt bên phải phím quả địa cầu, đáy ngang đáy phím, không bao giờ che phím
            left = globe.rect.right + 8 * dp
            bottom = globe.rect.bottom
        }
        val top = max(2 * dp, bottom - h)
        menuBox.set(left, top, left + w, top + h)
        menuRects.clear()
        var y = top + pad
        heights.forEach { h -> menuRects += RectF(left, y, left + w, y + h); y += h }
        menuHighlight = -1
        menuPointer = pointer
        menuOpen = true
        requestLayout()   // vùng nhận chạm mở rộng lên khoảng trong suốt phía trên (onComputeInsets)
        invalidate()
    }

    private fun closeMenu() {
        if (!menuOpen) return
        menuOpen = false
        menuHighlight = -1
        menuPointer = -1
        requestLayout()
        invalidate()
    }

    private fun menuItemAt(x: Float, y: Float): Int =
        menuRects.indexOfFirst { it.contains(x, y) }.takeIf { it >= 0 && menuItems[it].choice >= 0 } ?: -1

    private fun drawMenu(canvas: Canvas, p: Palette) {
        val r = 12 * dp
        shadowPaint.color = p.menu
        shadowPaint.setShadowLayer(10 * dp, 0f, 4 * dp, 0x40000000)
        canvas.drawRoundRect(menuBox, r, r, shadowPaint)
        canvas.save()
        canvas.clipRect(menuBox)
        menuItems.forEachIndexed { i, item ->
            val row = menuRects[i]
            val x = row.left + 52 * dp
            when (item.row) {
                Row.HEADER -> {
                    leftText.textSize = 11 * sp; leftText.typeface = medium; leftText.letterSpacing = 0.05f; leftText.color = p.hint
                    canvas.drawText(item.title, row.left + 16 * dp, row.top + 6 * dp - leftText.fontMetrics.ascent, leftText)
                    leftText.letterSpacing = 0f
                }
                Row.DIVIDER -> { fill.color = p.divider; canvas.drawRect(row.left, row.centerY() - 0.5f * dp, row.right, row.centerY() + 0.5f * dp, fill) }
                else -> {
                    val on = item.row == Row.ITEM && item.checked
                    if (on) { fill.color = p.container; canvas.drawRect(row, fill) }
                    if (i == menuHighlight) { fill.color = p.text; fill.alpha = 0x14; canvas.drawRect(row, fill) }
                    val fg = if (on) p.onContainer else p.text
                    if (on) drawIcon(canvas, Icons.check, row.left + 27 * dp, row.centerY(), 22f, fg)
                    item.icon?.let { drawIcon(canvas, it, row.left + 27 * dp, row.centerY(), 22f, p.icon) }
                    leftText.textSize = 15 * sp; leftText.typeface = medium; leftText.color = fg
                    if (item.subtitle == null) {
                        leftText.typeface = if (item.row == Row.ITEM) medium else regular
                        val fm = leftText.fontMetrics
                        val room = row.right - x - (if (item.row == Row.SWITCH) 80 else 16) * dp
                        val title = TextUtils.ellipsize(item.title, leftText, room, TextUtils.TruncateAt.END).toString()
                        canvas.drawText(title, x, row.centerY() - (fm.ascent + fm.descent) / 2, leftText)
                    } else {
                        canvas.drawText(item.title, x, row.centerY() - 2 * dp, leftText)
                        leftText.textSize = 12 * sp; leftText.typeface = regular
                        leftText.color = if (on) p.onContainer else p.hint
                        if (on) leftText.alpha = 0xCC
                        canvas.drawText(item.subtitle, x, row.centerY() + 15 * dp, leftText)
                    }
                    if (item.row == Row.SWITCH) drawSwitch(canvas, row.right - 16 * dp - 52 * dp, row.centerY(), item.checked, p)
                }
            }
        }
        canvas.restore()
    }

    /** Switch Material 3, 52 × 32. */
    private fun drawSwitch(canvas: Canvas, left: Float, cy: Float, on: Boolean, p: Palette) {
        tmp.set(left, cy - 16 * dp, left + 52 * dp, cy + 16 * dp)
        if (on) {
            fill.color = p.primary
            canvas.drawRoundRect(tmp, 16 * dp, 16 * dp, fill)
            fill.color = p.onPrimary
            canvas.drawCircle(tmp.right - 16 * dp, cy, 12 * dp, fill)
        } else {
            fill.color = p.bg
            canvas.drawRoundRect(tmp, 16 * dp, 16 * dp, fill)
            icon.style = Paint.Style.STROKE; icon.strokeWidth = 2 * dp; icon.color = p.outline
            tmp.inset(1 * dp, 1 * dp)
            canvas.drawRoundRect(tmp, 15 * dp, 15 * dp, icon)
            fill.color = p.outline
            canvas.drawCircle(left + 16 * dp, cy, 8 * dp, fill)
        }
    }

    /** Bàn phím ẩn đi: đóng bảng tạm, lưới ứng viên và menu. */
    fun reset() {
        clipOpen = false
        gridOpen = false
        closeMenu()
    }

    /** Vị trí giữa các phím (cho kiểm thử tự động): "nhãn x y" mỗi phím. */
    fun describeKeys(): String = buildString {
        val loc = IntArray(2)
        getLocationOnScreen(loc)
        fun put(name: String, x: Float, y: Float) = append("$name ${(loc[0] + x).toInt()} ${(loc[1] + y).toInt()}\n")
        if (!gridOpen && !clipOpen) for (row in rows) for (k in row) if (k.kind != Kind.SPACER) put(if (k.kind == Kind.CHAR) k.label else k.kind.name.lowercase(), k.rect.centerX(), k.rect.centerY())
        val cy = barTop + barH / 2
        put("nav", navInset.toFloat(), height.toFloat())
        put("clip", blockL + sideIcon / 2, cy)
        put("right", blockR - sideIcon / 2, cy)
        put("sug0", midL + (midR - midL) / 6, cy)
        put("sug1", midL + (midR - midL) / 2, cy)
        candidateRects.forEachIndexed { i, r -> put("cand$i", r.centerX() - stripScroll, cy) }
        if (gridOpen) gridRects.forEachIndexed { i, r -> put("grid$i", r.centerX(), r.centerY() - gridScroll) }
        val names = mapOf(PICK_VIEN to "vien", PICK_CHINESE to "chinese", PICK_TRADITIONAL to "traditional",
            PICK_OTHER_KEYBOARD to "other", PICK_SETTINGS to "settings")
        if (menuOpen) menuRects.forEachIndexed { i, r -> names[menuItems[i].choice]?.let { put("menu_$it", r.centerX(), r.centerY()) } }
        if (clipOpen) clipRects.forEachIndexed { i, r -> put("clip$i", r.centerX(), r.centerY()) }
    }
}
