package dev.t43.vipi

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.animation.DecelerateInterpolator
import android.widget.OverScroller
import dev.t43.vipi.core.InputMode
import dev.t43.vipi.core.KeyInput
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Bàn phím ảo tự vẽ: thanh trên (chọn chế độ / ứng viên chữ Hán) + 4 hàng phím.
 * Phong cách theo bàn phím iOS 26/27: phím bo tròn lớn, không viền, phím chức năng tối hơn một bậc,
 * bóng chữ phóng to khi nhấn, các hàng phím trượt lên từ dưới khi bàn phím hiện.
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context, private val listener: Listener) : View(context) {

    interface Listener {
        fun onKey(key: KeyInput)
        /** Phím quả địa cầu: chạm = PICK_TOGGLE; giữ lâu rồi chọn trong menu = các PICK_ còn lại. */
        fun onPickInput(choice: Int)
        fun onCandidate(index: Int)
        fun onCursor(delta: Int)
        fun onSettings()
    }

    companion object {
        const val PICK_VIEN = 0
        const val PICK_CHINESE = 1
        const val PICK_OTHER_KEYBOARD = 2
        const val PICK_SETTINGS = 3
        const val PICK_TOGGLE = 4
    }

    enum class Layout { LETTERS, NUMBERS, SYMBOLS }
    enum class Shift { OFF, ONCE, LOCK }
    private enum class Kind { CHAR, SHIFT, BACKSPACE, NUMBERS, LETTERS, SYMBOLS, MODE, SPACE, RETURN, SPACER }

    private class Key(val kind: Kind, val label: String = "", val units: Float = 1f) {
        val rect = RectF()
        var row = 0
        val isFunction get() = kind != Kind.CHAR && kind != Kind.SPACE && kind != Kind.SPACER
    }

    // MARK: - Trạng thái do bộ gõ đặt

    var layout = Layout.LETTERS
        set(v) { field = v; buildRows(); invalidate() }
    var shift = Shift.OFF
        set(v) { field = v; invalidate() }
    var mode = InputMode.VIETNAMESE
        set(v) { field = v; updateStripHeight(); invalidate() }
    /** Chữ trên phím Return khi ô nhập có hành động (go, search, send…); null: biểu tượng xuống dòng. */
    var returnLabel: String? = null
        set(v) { field = v; invalidate() }
    var hapticsEnabled = true
    /** Ô mật khẩu / số: chỉ tiếng Anh, ẩn chọn chế độ. */
    var modeLocked = false
        set(v) { field = v; updateStripHeight(); invalidate() }
    /** Pinyin đang gõ (tiếng Trung): hiện trong bàn phím, phía trên ứng viên, không đưa vào ô nhập của app. */
    var preedit = ""
        set(v) { if (field != v) { field = v; invalidate() } }
    /** Android 16+: hệ thống giao nút đổi bàn phím cho bộ gõ (thanh điều hướng của bàn phím đã ẩn). */
    var showSystemSwitcher = false

    private var candidates: List<String> = emptyList()
    private var candidateRects: List<RectF> = emptyList()
    private val scroller = OverScroller(context)
    private var stripScroll = 0f
    private var stripContentWidth = 0f

    fun setCandidates(list: List<String>) {
        candidates = list
        stripScroll = 0f
        scroller.forceFinished(true)
        layoutCandidates()
        invalidate()
    }

    // MARK: - Kích thước và màu

    private val dp = resources.displayMetrics.density
    private val sp = resources.displayMetrics.scaledDensity
    private val stripBase = 34 * dp        // chỗ cho bóng chữ của hàng phím trên cùng
    private val stripChinese = 60 * dp     // dòng pinyin đang gõ + ứng viên
    private var stripHeight = stripBase

    private fun updateStripHeight() {
        val h = if (mode == InputMode.CHINESE && !modeLocked) stripChinese else stripBase
        if (h == stripHeight) return
        stripHeight = h
        layoutKeys()
        layoutCandidates()
        requestLayout()
    }
    private val rowPitch = 54 * dp
    private val keyGapX = 6 * dp
    private val keyGapY = 11 * dp
    private val sidePad = 3 * dp
    private val bottomPad = 4 * dp
    private val keyRadius = 9.5f * dp
    private val panelRadius = 22 * dp
    private var navInset = 0

    private class Palette(
        val panelTop: Int, val panelBottom: Int, val key: Int, val fnKey: Int, val pressed: Int,
        val text: Int, val subtle: Int, val shadow: Int, val segment: Int, val segmentOn: Int, val accent: Int,
    )

    private val light = Palette(
        panelTop = 0xFFECEDF1.toInt(), panelBottom = 0xFFDCDEE3.toInt(), key = 0xFFFFFFFF.toInt(),
        fnKey = 0xFFBFC3CC.toInt(), pressed = 0xFFE3E5EA.toInt(), text = 0xFF0B0B0C.toInt(),
        subtle = 0xFF6D6F76.toInt(), shadow = 0x33000000, segment = 0x14000000, segmentOn = 0xFFFFFFFF.toInt(),
        accent = 0xFFC8102E.toInt(),
    )
    private val dark = Palette(
        panelTop = 0xFF2A2A2D.toInt(), panelBottom = 0xFF1D1D1F.toInt(), key = 0xFF515155.toInt(),
        fnKey = 0xFF38383B.toInt(), pressed = 0xFF6C6C70.toInt(), text = 0xFFF5F5F7.toInt(),
        subtle = 0xFFA3A3A8.toInt(), shadow = 0x55000000, segment = 0x22FFFFFF, segmentOn = 0xFF636367.toInt(),
        accent = 0xFFE0485F.toInt(),
    )
    private val palette: Palette
        get() = if ((resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES) dark else light

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; typeface = Typeface.create("sans-serif", Typeface.NORMAL) }
    private val path = Path()
    private val tmp = RectF()

    // MARK: - Bố cục phím

    private var rows: List<List<Key>> = emptyList()

    private fun chars(s: String, units: Float = 1f) = s.map { Key(Kind.CHAR, it.toString(), units) }

    private fun buildRows() {
        val bottom = listOf(
            Key(if (layout == Layout.LETTERS) Kind.NUMBERS else Kind.LETTERS, if (layout == Layout.LETTERS) "123" else "ABC", 1.25f),
            Key(Kind.MODE, "", 1.25f),
            Key(Kind.SPACE, "", 5f),
            Key(Kind.RETURN, "", 2.5f),
        )
        rows = when (layout) {
            Layout.LETTERS -> listOf(
                chars("qwertyuiop"),
                listOf(Key(Kind.SPACER, units = 0.5f)) + chars("asdfghjkl") + Key(Kind.SPACER, units = 0.5f),
                listOf(Key(Kind.SHIFT, units = 1.3f), Key(Kind.SPACER, units = 0.2f)) + chars("zxcvbnm") +
                    listOf(Key(Kind.SPACER, units = 0.2f), Key(Kind.BACKSPACE, units = 1.3f)),
                bottom,
            )
            Layout.NUMBERS -> listOf(
                chars("1234567890"),
                chars("-/:;()$&@\""),
                listOf(Key(Kind.SYMBOLS, "#+=", 1.3f), Key(Kind.SPACER, units = 0.2f)) + chars(".,?!'", 1.4f) +
                    listOf(Key(Kind.SPACER, units = 0.2f), Key(Kind.BACKSPACE, units = 1.3f)),
                bottom,
            )
            Layout.SYMBOLS -> listOf(
                chars("[]{}#%^*+="),
                chars("_\\|~<>€£¥•"),
                listOf(Key(Kind.NUMBERS, "123", 1.3f), Key(Kind.SPACER, units = 0.2f)) + chars(".,?!'", 1.4f) +
                    listOf(Key(Kind.SPACER, units = 0.2f), Key(Kind.BACKSPACE, units = 1.3f)),
                bottom,
            )
        }
        rows.forEachIndexed { r, row -> row.forEach { it.row = r } }
        layoutKeys()
    }

    private fun layoutKeys() {
        if (width == 0) return
        val unit = (width - 2 * sidePad) / 10f
        rows.forEachIndexed { r, row ->
            var x = sidePad
            val top = stripHeight + r * rowPitch + keyGapY / 2
            for (k in row) {
                val w = k.units * unit
                k.rect.set(x + keyGapX / 2, top, x + w - keyGapX / 2, top + rowPitch - keyGapY)
                x += w
            }
        }
    }

    init {
        buildRows()
        isHapticFeedbackEnabled = true
        setOnApplyWindowInsetsListener { _, insets ->
            val bottom = if (android.os.Build.VERSION.SDK_INT >= 30)
                insets.getInsets(WindowInsets.Type.navigationBars()).bottom
            else @Suppress("DEPRECATION") insets.systemWindowInsetBottom
            if (bottom != navInset) { navInset = bottom; requestLayout() }
            insets
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = stripHeight + 4 * rowPitch + bottomPad + navInset
        setMeasuredDimension(w, h.toInt())
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        layoutKeys()
        layoutCandidates()
    }

    // MARK: - Hiệu ứng hiện bàn phím: các hàng trượt lên từ dưới, lần lượt

    private var appear = 1f
    private var appearAnimator: ValueAnimator? = null
    private val appearMs = 340f

    fun animateIn() {
        appearAnimator?.cancel()
        appear = 0f
        appearAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = appearMs.toLong()
            interpolator = null
            addUpdateListener { appear = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    private val ease = DecelerateInterpolator(2f)

    /** Tiến độ hiện của hàng (0 = chưa hiện) — hàng dưới cùng lên trước. */
    private fun rowProgress(fromBottom: Int): Float {
        val t = (appear * appearMs - fromBottom * 28f) / 230f
        return ease.getInterpolation(t.coerceIn(0f, 1f))
    }

    // MARK: - Vẽ

    override fun onDraw(canvas: Canvas) {
        val p = palette
        // nền: bo tròn hai góc trên, sáng dần lên trên như một tấm kính mờ
        fill.shader = android.graphics.LinearGradient(0f, 0f, 0f, height.toFloat(), p.panelTop, p.panelBottom, android.graphics.Shader.TileMode.CLAMP)
        tmp.set(0f, 0f, width.toFloat(), height + panelRadius)
        canvas.drawRoundRect(tmp, panelRadius, panelRadius, fill)
        fill.shader = null
        // đường sáng mảnh ở mép trên
        stroke.color = if (p === light) 0x99FFFFFF.toInt() else 0x22FFFFFF
        stroke.strokeWidth = 1 * dp
        tmp.set(0.5f * dp, 0.5f * dp, width - 0.5f * dp, height + panelRadius)
        canvas.drawRoundRect(tmp, panelRadius, panelRadius, stroke)

        drawStrip(canvas, p)
        rows.forEachIndexed { r, row ->
            val t = rowProgress(rows.size - 1 - r)
            if (t <= 0f) return@forEachIndexed
            canvas.save()
            canvas.translate(0f, (1 - t) * 34 * dp)
            val alpha = (t * 255).toInt()
            for (k in row) if (k.kind != Kind.SPACER) drawKey(canvas, k, p, alpha)
            canvas.restore()
        }
        // bóng chữ phóng to vẽ sau cùng để nổi lên trên hàng phía trên
        for (i in 0 until pressed.size()) {
            val k = pressed.valueAt(i).key
            if (k.kind == Kind.CHAR) drawCallout(canvas, k, p)
        }
        if (menuOpen) drawMenu(canvas, p)
    }

    private fun isPressed(k: Key): Boolean {
        if (k.kind == Kind.MODE && menuOpen) return true
        for (i in 0 until pressed.size()) if (pressed.valueAt(i).key === k) return true
        return k.kind == Kind.BACKSPACE && repeating
    }

    private fun drawKey(canvas: Canvas, k: Key, p: Palette, alpha: Int) {
        val down = isPressed(k)
        val isReturnAccent = k.kind == Kind.RETURN && returnLabel != null
        val base = when {
            isReturnAccent -> p.accent
            k.kind == Kind.SHIFT && shift != Shift.OFF -> p.key
            k.isFunction -> p.fnKey
            else -> p.key
        }
        val color = when {
            down && k.kind == Kind.CHAR -> base
            down && k.isFunction -> p.key
            down -> p.pressed
            else -> base
        }
        // bóng mảnh dưới phím
        fill.color = p.shadow
        fill.alpha = alpha * Color.alpha(p.shadow) / 255
        tmp.set(k.rect.left, k.rect.top + 1 * dp, k.rect.right, k.rect.bottom + 1 * dp)
        canvas.drawRoundRect(tmp, keyRadius, keyRadius, fill)
        fill.color = color
        fill.alpha = alpha
        canvas.drawRoundRect(k.rect, keyRadius, keyRadius, fill)

        val fg = if (isReturnAccent) Color.WHITE else p.text
        val cx = k.rect.centerX()
        val cy = k.rect.centerY()
        when (k.kind) {
            Kind.CHAR -> {
                val label = if (layout == Layout.LETTERS && shift != Shift.OFF) k.label.uppercase() else k.label
                drawLabel(canvas, label, cx, cy, if (layout == Layout.LETTERS) 23f else 21f, fg, alpha)
            }
            Kind.SHIFT -> drawShift(canvas, cx, cy, fg, alpha)
            Kind.BACKSPACE -> drawBackspace(canvas, cx, cy, fg, alpha)
            Kind.RETURN -> if (returnLabel != null) drawLabel(canvas, returnLabel!!, cx, cy, 16f, fg, alpha)
                else drawReturn(canvas, cx, cy, fg, alpha)
            Kind.MODE -> drawGlobe(canvas, cx, cy, fg, alpha)
            Kind.SPACE -> drawLabel(canvas, spaceLabel(), cx, cy, 15f, p.subtle, alpha)
            else -> drawLabel(canvas, k.label, cx, cy, 16f, fg, alpha)
        }
    }

    private fun spaceLabel() = when {
        modeLocked -> "space"
        mode == InputMode.CHINESE -> "拼音"
        else -> "Tiếng Việt · English"
    }

    private fun drawLabel(canvas: Canvas, s: String, cx: Float, cy: Float, size: Float, color: Int, alpha: Int) {
        text.textSize = size * sp
        text.color = color
        text.alpha = alpha * Color.alpha(color) / 255
        val fm = text.fontMetrics
        canvas.drawText(s, cx, cy - (fm.ascent + fm.descent) / 2, text)
    }

    private fun drawShift(canvas: Canvas, cx: Float, cy: Float, color: Int, alpha: Int) {
        val s = 9 * dp
        path.reset()
        path.moveTo(cx, cy - s)
        path.lineTo(cx + s, cy + 0.6f)
        path.lineTo(cx + s * 0.45f, cy + 0.6f)
        path.lineTo(cx + s * 0.45f, cy + s * 0.85f)
        path.lineTo(cx - s * 0.45f, cy + s * 0.85f)
        path.lineTo(cx - s * 0.45f, cy + 0.6f)
        path.lineTo(cx - s, cy + 0.6f)
        path.close()
        if (shift == Shift.OFF) {
            stroke.color = color; stroke.alpha = alpha; stroke.strokeWidth = 1.6f * dp
            canvas.drawPath(path, stroke)
        } else {
            fill.color = color; fill.alpha = alpha
            canvas.drawPath(path, fill)
            if (shift == Shift.LOCK) canvas.drawRect(cx - s * 0.45f, cy + s * 1.15f, cx + s * 0.45f, cy + s * 1.4f, fill)
        }
    }

    private fun drawBackspace(canvas: Canvas, cx: Float, cy: Float, color: Int, alpha: Int) {
        val w = 11 * dp
        val h = 8 * dp
        path.reset()
        path.moveTo(cx - w, cy)
        path.lineTo(cx - w * 0.45f, cy - h)
        path.lineTo(cx + w, cy - h)
        path.lineTo(cx + w, cy + h)
        path.lineTo(cx - w * 0.45f, cy + h)
        path.close()
        stroke.color = color; stroke.alpha = alpha; stroke.strokeWidth = 1.6f * dp
        canvas.drawPath(path, stroke)
        val x = cx + w * 0.28f
        val d = 3.2f * dp
        canvas.drawLine(x - d, cy - d, x + d, cy + d, stroke)
        canvas.drawLine(x - d, cy + d, x + d, cy - d, stroke)
    }

    private fun drawReturn(canvas: Canvas, cx: Float, cy: Float, color: Int, alpha: Int) {
        val w = 9 * dp
        stroke.color = color; stroke.alpha = alpha; stroke.strokeWidth = 1.7f * dp
        path.reset()
        path.moveTo(cx + w, cy - w * 0.8f)
        path.lineTo(cx + w, cy + w * 0.2f)
        path.lineTo(cx - w, cy + w * 0.2f)
        canvas.drawPath(path, stroke)
        path.reset()
        path.moveTo(cx - w * 0.45f, cy - w * 0.35f)
        path.lineTo(cx - w, cy + w * 0.2f)
        path.lineTo(cx - w * 0.45f, cy + w * 0.75f)
        canvas.drawPath(path, stroke)
    }

    /** Quả địa cầu: viền tròn, kinh tuyến giữa hình bầu dục, xích đạo và hai vĩ tuyến. */
    private fun drawGlobe(canvas: Canvas, cx: Float, cy: Float, color: Int, alpha: Int) {
        val r = 9.5f * dp
        stroke.color = color; stroke.alpha = alpha; stroke.strokeWidth = 1.5f * dp
        canvas.drawCircle(cx, cy, r, stroke)
        stroke.strokeWidth = 1.2f * dp
        tmp.set(cx - r * 0.42f, cy - r, cx + r * 0.42f, cy + r)
        canvas.drawOval(tmp, stroke)
        canvas.drawLine(cx - r, cy, cx + r, cy, stroke)
        val dy = r * 0.52f
        val half = Math.sqrt((r * r - dy * dy).toDouble()).toFloat() - 0.6f * dp
        canvas.drawLine(cx - half, cy - dy, cx + half, cy - dy, stroke)
        canvas.drawLine(cx - half, cy + dy, cx + half, cy + dy, stroke)
    }

    /** Bóng chữ phóng to phía trên phím đang nhấn. */
    private fun drawCallout(canvas: Canvas, k: Key, p: Palette) {
        val w = k.rect.width() * 1.45f
        val h = k.rect.height() * 1.15f
        val left = (k.rect.centerX() - w / 2).coerceIn(2 * dp, width - w - 2 * dp)
        val top = max(0f, k.rect.top - h + 10 * dp)   // phủ một phần đầu phím, như bóng chữ của iOS
        fill.color = p.shadow
        tmp.set(left, top + 2 * dp, left + w, top + h + 2 * dp)
        canvas.drawRoundRect(tmp, keyRadius * 1.3f, keyRadius * 1.3f, fill)
        fill.color = p.key
        tmp.set(left, top, left + w, top + h)
        canvas.drawRoundRect(tmp, keyRadius * 1.3f, keyRadius * 1.3f, fill)
        // cổ nối bóng chữ với phím
        tmp.set(k.rect.left + 2 * dp, top + h - keyRadius, k.rect.right - 2 * dp, k.rect.bottom)
        canvas.drawRoundRect(tmp, keyRadius, keyRadius, fill)
        val label = if (layout == Layout.LETTERS && shift != Shift.OFF) k.label.uppercase() else k.label
        drawLabel(canvas, label, left + w / 2, top + h / 2, 32f, p.text, 255)
    }

    // MARK: - Thanh trên: chọn chế độ hoặc ứng viên chữ Hán


    private fun layoutCandidates() {
        text.textSize = 21 * sp
        var x = 12 * dp
        candidateRects = candidates.map { c ->
            val w = max(text.measureText(c) + 26 * dp, 44 * dp)
            RectF(x, stripHeight - 40 * dp, x + w, stripHeight - 3 * dp).also { x += w }
        }
        stripContentWidth = x + 12 * dp
    }

    private fun drawStrip(canvas: Canvas, p: Palette) {
        val t = rowProgress(rows.size)
        if (t <= 0f) return
        val alpha = (t * 255).toInt()
        if (preedit.isNotEmpty()) {
            menuText.color = p.text
            menuText.alpha = alpha
            menuText.textSize = 15 * sp
            menuText.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            canvas.drawText(preedit, 16 * dp, 16 * dp, menuText)
        }
        if (candidates.isNotEmpty()) {
            canvas.save()
            canvas.clipRect(0f, 0f, width.toFloat(), stripHeight)
            canvas.translate(-stripScroll, 0f)
            candidateRects.forEachIndexed { i, r ->
                if (r.right < stripScroll || r.left > stripScroll + width) return@forEachIndexed
                if (i == 0) {
                    fill.color = p.segmentOn; fill.alpha = alpha
                    canvas.drawRoundRect(r, r.height() / 2, r.height() / 2, fill)
                }
                if (i == pressedCandidate) {
                    fill.color = p.segment; fill.alpha = alpha
                    canvas.drawRoundRect(r, r.height() / 2, r.height() / 2, fill)
                }
                drawLabel(canvas, candidates[i], r.centerX(), r.centerY(), 21f, p.text, alpha)
                if (i < candidateRects.size - 1 && i != 0) {
                    fill.color = p.subtle; fill.alpha = alpha / 4
                    canvas.drawRect(r.right - 0.5f * dp, r.top + 10 * dp, r.right + 0.5f * dp, r.bottom - 10 * dp, fill)
                }
            }
            canvas.restore()
            return
        }
    }

    // MARK: - Chạm

    private class Touch(var key: Key, val startX: Float, var lastX: Float) {
        var trackpad = false
    }

    private val pressed = android.util.SparseArray<Touch>()
    private val handler = Handler(Looper.getMainLooper())
    private var repeating = false
    private var lastShiftTap = 0L
    private var stripTouch: Int = -1
    private var stripDownX = 0f
    private var stripDownScroll = 0f
    private var stripDragged = false
    private var pressedCandidate = -1
    private var velocity: android.view.VelocityTracker? = null

    private val repeatBackspace = object : Runnable {
        override fun run() {
            repeating = true
            listener.onKey(KeyInput.Backspace)
            handler.postDelayed(this, 55)
        }
    }

    private fun stopRepeat() {
        handler.removeCallbacks(repeatBackspace)
        if (repeating) { repeating = false; invalidate() }
    }

    private fun hit(x: Float, y: Float): Key? {
        val r = ((y - stripHeight) / rowPitch).toInt().coerceIn(0, rows.size - 1)
        if (y < stripHeight - 6 * dp) return null
        var best: Key? = null
        var bestD = Float.MAX_VALUE
        for (k in rows[r]) {
            if (k.kind == Kind.SPACER) continue
            val d = if (x < k.rect.left) k.rect.left - x else if (x > k.rect.right) x - k.rect.right else 0f
            if (d < bestD) { bestD = d; best = k }
        }
        return best
    }

    private fun feedback() {
        if (hapticsEnabled) performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
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
                    // menu đang mở (đã chạm phím quả địa cầu): chạm vào mục để chọn, chạm chỗ khác để đóng
                    val m = menuItemAt(x, y)
                    if (m >= 0) { menuHighlight = m; menuPointer = id } else closeMenu()
                    invalidate()
                    return true
                }
                if (y < stripHeight - 6 * dp && pressed.size() == 0) {
                    stripTouch = id
                    stripDownX = x
                    stripDownScroll = stripScroll
                    stripDragged = false
                    scroller.forceFinished(true)
                    velocity = android.view.VelocityTracker.obtain().also { it.addMovement(e) }
                    pressedCandidate = candidateAt(x)
                    invalidate()
                    return true
                }
                val k = hit(x, y) ?: return true
                // ngón thứ hai chạm: phím của ngón trước được gõ luôn (gõ nhanh hai tay). Cả phím quả địa cầu:
                // chạm quả địa cầu rồi gõ ngay "n" thì đổi bộ gõ trước, "n" mới vào bộ gõ mới
                for (j in pressed.size() - 1 downTo 0) {
                    val t = pressed.valueAt(j)
                    if (t.key.kind == Kind.CHAR || t.key.kind == Kind.SPACE || t.key.kind == Kind.MODE) {
                        if (!t.trackpad) fire(t.key)
                        pressed.removeAt(j)
                    }
                }
                feedback()
                when (k.kind) {
                    Kind.SHIFT -> { tapShift(); return true }
                    Kind.MODE -> {
                        // chạm: đổi Việt·Anh ↔ Trung; giữ lâu: menu
                        handler.postDelayed(Runnable { holdGlobe(k, id) }.also { globeHold = it }, 380)
                    }
                    Kind.BACKSPACE -> {
                        listener.onKey(KeyInput.Backspace)
                        handler.postDelayed(repeatBackspace, 420)
                    }
                    else -> {}
                }
                pressed.put(id, Touch(k, x, x))
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
                if (stripTouch >= 0) {
                    velocity?.addMovement(e)
                    val idx = e.findPointerIndex(stripTouch)
                    if (idx >= 0 && candidates.isNotEmpty()) {
                        val dx = e.getX(idx) - stripDownX
                        if (abs(dx) > 8 * dp) { stripDragged = true; pressedCandidate = -1 }
                        if (stripDragged) {
                            stripScroll = (stripDownScroll - dx).coerceIn(0f, max(0f, stripContentWidth - width))
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
                        if (!t.trackpad && abs(x - t.startX) > 14 * dp) { t.trackpad = true; t.lastX = x }
                        if (t.trackpad) {
                            val step = 11 * dp
                            while (x - t.lastX > step) { listener.onCursor(1); t.lastX += step }
                            while (t.lastX - x > step) { listener.onCursor(-1); t.lastX -= step }
                        }
                    } else if (t.key.kind == Kind.CHAR) {
                        val k = hit(x, y)
                        if (k != null && k !== t.key && k.kind == Kind.CHAR) { t.key = k; invalidate() }
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (menuOpen && id == menuPointer) {
                    menuPointer = -1
                    // thả trên một mục: chọn; thả trên phím quả địa cầu (chạm nhanh): menu vẫn mở để chọn tiếp
                    if (menuHighlight >= 0) {
                        val choice = menuItems[menuHighlight].choice
                        closeMenu()
                        listener.onPickInput(choice)
                    }
                    invalidate()
                    return true
                }
                if (id == stripTouch) {
                    velocity?.let {
                        it.addMovement(e)
                        it.computeCurrentVelocity(1000)
                        if (stripDragged) {
                            scroller.fling(stripScroll.toInt(), 0, -it.xVelocity.toInt(), 0, 0,
                                max(0f, stripContentWidth - width).toInt(), 0, 0)
                            postInvalidateOnAnimation()
                        }
                        it.recycle()
                    }
                    velocity = null
                    if (!stripDragged) tapStrip(e.getX(i))
                    stripTouch = -1
                    pressedCandidate = -1
                    invalidate()
                    return true
                }
                val t = pressed.get(id)
                if (t != null) {
                    pressed.remove(id)
                    if (t.key.kind == Kind.BACKSPACE) stopRepeat() else if (!t.trackpad) fire(t.key)
                    invalidate()
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                cancelGlobeHold()
                closeMenu()
                pressed.clear()
                stopRepeat()
                stripTouch = -1
                pressedCandidate = -1
                invalidate()
            }
        }
        return true
    }

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            stripScroll = scroller.currX.toFloat()
            postInvalidateOnAnimation()
        }
    }

    private fun candidateAt(x: Float): Int {
        if (candidates.isEmpty()) return -1
        val cx = x + stripScroll
        return candidateRects.indexOfFirst { cx >= it.left && cx <= it.right }
    }

    private fun tapStrip(x: Float) {
        if (candidates.isNotEmpty()) {
            val i = candidateAt(x)
            if (i >= 0) { feedback(); listener.onCandidate(i) }
        }
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
                val s = if (layout == Layout.LETTERS && shift != Shift.OFF) k.label.uppercase() else k.label
                if (shift == Shift.ONCE && layout == Layout.LETTERS) shift = Shift.OFF
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

    /** Giữ phím quả địa cầu đủ lâu: thay cho lần chạm, mở menu (vẫn trượt ngón lên để chọn được). */
    private fun holdGlobe(globe: Key, pointer: Int) {
        globeHold = null
        if (pressed.get(pointer)?.key !== globe) return
        pressed.remove(pointer)
        feedback()
        openMenu(globe, pointer)
    }

    // MARK: - Menu đổi bộ gõ (phím quả địa cầu)

    private class MenuItem(val choice: Int, val title: String, val subtitle: String?, val checked: Boolean)

    private var menuOpen = false
    private var menuItems: List<MenuItem> = emptyList()
    private val menuRects = mutableListOf<RectF>()
    private val menuBox = RectF()
    private var menuHighlight = -1
    private var menuPointer = -1
    private val menuText = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.LEFT }

    private fun openMenu(globe: Key, pointer: Int) {
        val items = mutableListOf<MenuItem>()
        if (!modeLocked) {
            items += MenuItem(PICK_VIEN, "Tiếng Việt · English", "Detects the language as you type", mode != InputMode.CHINESE)
            items += MenuItem(PICK_CHINESE, "中文 · 拼音", "Chinese Pinyin", mode == InputMode.CHINESE)
        }
        if (showSystemSwitcher || modeLocked) items += MenuItem(PICK_OTHER_KEYBOARD, "Other keyboards", null, false)
        items += MenuItem(PICK_SETTINGS, "ViPi Settings", null, false)
        menuItems = items
        // bên phải phím quả địa cầu, đáy ngang đáy phím: không bao giờ che phím (thả tay tại chỗ không chọn nhầm)
        val pad = 6 * dp
        val heights = items.map { if (it.subtitle != null) 52 * dp else 44 * dp }
        val w = min(268 * dp, width - globe.rect.right - 14 * dp)
        val left = globe.rect.right + 6 * dp
        val bottom = globe.rect.bottom
        val top = max(4 * dp, bottom - heights.sum() - 2 * pad)
        menuBox.set(left, top, left + w, top + heights.sum() + 2 * pad)
        menuRects.clear()
        var y = top + pad
        heights.forEach { h -> menuRects += RectF(left + pad, y, left + w - pad, y + h); y += h }
        menuHighlight = -1
        menuPointer = pointer
        menuOpen = true
        invalidate()
    }

    private fun closeMenu() {
        menuOpen = false
        menuHighlight = -1
        menuPointer = -1
        invalidate()
    }

    private fun menuItemAt(x: Float, y: Float): Int = menuRects.indexOfFirst { it.contains(x, y) }

    private fun drawMenu(canvas: Canvas, p: Palette) {
        val r = 16 * dp
        fill.color = 0x40000000
        tmp.set(menuBox); tmp.offset(0f, 3 * dp); tmp.inset(-1 * dp, -1 * dp)
        canvas.drawRoundRect(tmp, r, r, fill)
        fill.color = if (p === light) 0xFFFFFFFF.toInt() else 0xFF3A3A3D.toInt()
        canvas.drawRoundRect(menuBox, r, r, fill)
        menuItems.forEachIndexed { i, item ->
            val row = menuRects[i]
            if (i == menuHighlight) {
                fill.color = p.segment
                canvas.drawRoundRect(row, 11 * dp, 11 * dp, fill)
            }
            if (i > 0 && i != menuHighlight && i - 1 != menuHighlight) {
                fill.color = p.subtle; fill.alpha = 40
                canvas.drawRect(row.left + 44 * dp, row.top - 0.5f * dp, row.right - 10 * dp, row.top + 0.5f * dp, fill)
            }
            if (item.checked) drawCheck(canvas, row.left + 22 * dp, row.centerY(), p.accent)
            val x = row.left + 44 * dp
            menuText.color = p.text
            menuText.textSize = 17 * sp
            menuText.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            if (item.subtitle == null) {
                val fm = menuText.fontMetrics
                canvas.drawText(item.title, x, row.centerY() - (fm.ascent + fm.descent) / 2, menuText)
            } else {
                canvas.drawText(item.title, x, row.centerY() - 1 * dp, menuText)
                menuText.typeface = Typeface.create("sans-serif", Typeface.NORMAL)
                menuText.textSize = 12.5f * sp
                menuText.color = p.subtle
                canvas.drawText(item.subtitle, x, row.centerY() + 15 * dp, menuText)
            }
        }
    }

    private fun drawCheck(canvas: Canvas, cx: Float, cy: Float, color: Int) {
        stroke.color = color; stroke.alpha = 255; stroke.strokeWidth = 2.2f * dp
        path.reset()
        path.moveTo(cx - 6 * dp, cy)
        path.lineTo(cx - 1.5f * dp, cy + 4.5f * dp)
        path.lineTo(cx + 7 * dp, cy - 5 * dp)
        canvas.drawPath(path, stroke)
    }

    /** Vị trí giữa các phím (cho kiểm thử tự động): "nhãn x y" mỗi phím. */
    fun describeKeys(): String = buildString {
        val loc = IntArray(2)
        getLocationOnScreen(loc)
        for (row in rows) for (k in row) if (k.kind != Kind.SPACER) {
            val name = if (k.kind == Kind.CHAR) k.label else k.kind.name.lowercase()
            append("$name ${(loc[0] + k.rect.centerX()).toInt()} ${(loc[1] + k.rect.centerY()).toInt()}\n")
        }
        append("strip ${loc[1] + (stripHeight / 2).toInt()}\n")
        candidateRects.forEachIndexed { i, r -> append("cand$i ${(loc[0] + r.centerX() - stripScroll).toInt()}\n") }
        menuRects.forEachIndexed { i, r -> append("menu$i ${(loc[0] + r.centerX()).toInt()} ${(loc[1] + r.centerY()).toInt()}\n") }
    }
}
