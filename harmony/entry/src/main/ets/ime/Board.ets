import { KeyInput, KeyKind } from '../common/Engine';
import { Palette, makePalette, css } from './Palette';

/**
 * Bàn phím tự vẽ trên Canvas, theo thiết kế Material 3 của ViPi (giống KeyboardView.kt của bản Android):
 * thanh gợi ý 48 vp (dán · gợi ý / ứng viên · mở rộng) và 4 hàng phím 48 vp. Đơn vị là vp.
 *
 * Hai lớp Canvas chồng nhau: lớp phím tĩnh chỉ vẽ lại khi bố cục, Shift, chế độ hay màu đổi; lớp trên vẽ phím
 * đang nhấn, bóng chữ, thanh gợi ý, lưới ứng viên và menu phím quả địa cầu.
 * Bảng điều khiển của bộ gõ không được mở cửa sổ con, nên menu và bóng chữ đều vẽ bên trong bàn phím.
 */
export interface BoardListener {
  onKey(key: KeyInput): void;
  /** Phím quả địa cầu: chạm = PICK_TOGGLE; giữ rồi chọn trong menu = các PICK_ còn lại. */
  onPickInput(choice: number): void;
  onCandidate(index: number): void;
  /** Thanh gợi ý tiếng Việt: 0 = đúng các phím đã gõ, 1 = chữ đang hiện. */
  onSuggestion(index: number): void;
  onCursor(delta: number): void;
  onPaste(): void;
  feedback(): void;
  redraw(staticLayer: boolean): void;
}

export const PICK_VIEN = 0;
export const PICK_CHINESE = 1;
export const PICK_OTHER_KEYBOARD = 2;
export const PICK_SETTINGS = 3;
export const PICK_TOGGLE = 4;
export const PICK_TRADITIONAL = 5;

export enum Layout { LETTERS, NUMBERS, SYMBOLS }

export enum Shift { OFF, ONCE, LOCK }

export enum Action { RETURN, SEND, SEARCH, GO, NEXT, DONE }

enum Kind { CHAR, SHIFT, BACKSPACE, NUMBERS, LETTERS, SYMBOLS, MODE, SPACE, RETURN, SPACER, GAP }

class Key {
  kind: Kind;
  label: string;
  units: number;
  hint: string;
  punct: boolean;
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;

  constructor(kind: Kind, label: string = '', units: number = 1, hint: string = '', punct: boolean = false) {
    this.kind = kind;
    this.label = label;
    this.units = units;
    this.hint = hint;
    this.punct = punct;
  }

  get isFunction(): boolean {
    return this.kind !== Kind.CHAR && this.kind !== Kind.SPACE && this.kind !== Kind.SPACER && this.kind !== Kind.GAP;
  }

  get isKey(): boolean {
    return this.kind !== Kind.SPACER && this.kind !== Kind.GAP;
  }

  get cx(): number {
    return this.x + this.w / 2;
  }

  get cy(): number {
    return this.y + this.h / 2;
  }
}

/** Cỡ hàng phím và thanh gợi ý theo chiều cao màn hình (vp). */
class Metrics {
  keyH: number;
  barH: number;
  topGap: number;
  gapY: number;
  bottomPad: number;

  constructor(keyH: number, barH: number, topGap: number, gapY: number, bottomPad: number) {
    this.keyH = keyH;
    this.barH = barH;
    this.topGap = topGap;
    this.gapY = gapY;
    this.bottomPad = bottomPad;
  }

  /**
   * Điện thoại dọc phím 48 vp; màn < 760 vp 46; màn thấp < 650 vp (Pura X Max: màn ngoài ~569 vp, màn trong mở
   * ~562 vp) 42 để app phía sau còn hơn nửa màn; điện thoại xoay ngang (< 500 vp) 38.
   */
  static of(screenH: number): Metrics {
    if (screenH > 0 && screenH < 500) {
      return new Metrics(38, 40, 4, 6, 6);
    }
    if (screenH > 0 && screenH < 650) {
      return new Metrics(42, 44, 5, 7, 6);
    }
    if (screenH > 0 && screenH < 760) {
      return new Metrics(46, 48, 6, 8, 8);
    }
    return new Metrics(48, 48, 6, 8, 8);
  }
}

class Rect {
  l: number;
  t: number;
  r: number;
  b: number;

  constructor(l: number, t: number, r: number, b: number) {
    this.l = l;
    this.t = t;
    this.r = r;
    this.b = b;
  }

  contains(x: number, y: number): boolean {
    return x >= this.l && x < this.r && y >= this.t && y < this.b;
  }
}

/** Biểu tượng trong ô 24×24 như SVG của thiết kế, phóng theo cỡ khi vẽ. */
class Icons {
  static readonly shift = new Path2D('M12 4 L20 12 L15 12 L15 20 L9 20 L9 12 L4 12 Z');
  static readonly backspace = new Path2D('M9 5 L20 5 Q22 5 22 7 L22 17 Q22 19 20 19 L9 19 L3 12 Z M12 9 L17 15 M17 9 L12 15');
  static readonly enter = new Path2D('M20 5 L20 11 Q20 13 18 13 L6 13 M9 9 L5 13 L9 17');
  static readonly send = new Path2D('M4 4 L20 12 L4 20 L7 12 Z');
  static readonly search = new Path2D('M17.5 11 A6.5 6.5 0 1 1 4.5 11 A6.5 6.5 0 1 1 17.5 11 M16 16 L20 20');
  static readonly arrow = new Path2D('M5 12 L19 12 M13 6 L19 12 L13 18');
  static readonly check = new Path2D('M5 12 L10 17 L20 7');
  static readonly globe = new Path2D('M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 M3 12 L21 12 M12 3 C15 6 15 18 12 21 M12 3 C9 6 9 18 12 21');
  static readonly clipboard = new Path2D('M7 4 L17 4 Q19 4 19 6 L19 19 Q19 21 17 21 L7 21 Q5 21 5 19 L5 6 Q5 4 7 4 Z M9 4 L9 2.5 L15 2.5 L15 4 M9 10 L15 10 M9 14 L13 14');
  static readonly chevronDown = new Path2D('M6 9 L12 15 L18 9');
  static readonly chevronUp = new Path2D('M6 15 L12 9 L18 15');
  static readonly sliders = new Path2D('M4 7 L12 7 M18 7 L20 7 M4 17 L6 17 M12 17 L20 17 M17.5 7 A2.5 2.5 0 1 1 12.5 7 A2.5 2.5 0 1 1 17.5 7 M11.5 17 A2.5 2.5 0 1 1 6.5 17 A2.5 2.5 0 1 1 11.5 17');
  static readonly keyboard = new Path2D('M4.5 5.5 L19.5 5.5 Q21.5 5.5 21.5 7.5 L21.5 16.5 Q21.5 18.5 19.5 18.5 L4.5 18.5 Q2.5 18.5 2.5 16.5 L2.5 7.5 Q2.5 5.5 4.5 5.5 Z M6 10 L7 10 M10 10 L11 10 M14 10 L15 10 M18 10 L19 10 M8 14.5 L16 14.5');
}

enum Row { HEADER, ITEM, DIVIDER, SWITCH, ACTION }

class MenuItem {
  row: Row;
  choice: number;
  title: string;
  subtitle: string;
  checked: boolean;
  icon: Path2D | null;

  constructor(row: Row, choice: number = -1, title: string = '', subtitle: string = '', checked: boolean = false,
    icon: Path2D | null = null) {
    this.row = row;
    this.choice = choice;
    this.title = title;
    this.subtitle = subtitle;
    this.checked = checked;
    this.icon = icon;
  }
}

class Touch {
  key: Key;
  startX: number;
  lastX: number;
  trackpad: boolean = false;
  longFired: boolean = false;
  longPress: number = -1;

  constructor(key: Key, x: number) {
    this.key = key;
    this.startX = x;
    this.lastX = x;
  }
}

const FONT = 'sans-serif';
const BAR_PASTE = 0;
const BAR_MID = 1;
const BAR_RIGHT = 2;
const BAR_GRID = 3;
const GAP_X = 6;
const RADIUS = 8;
const SIDE_ICON = 44;

export class Board {
  listener: BoardListener;

  // MARK: - Trạng thái do bộ gõ đặt

  private layoutValue: Layout = Layout.LETTERS;
  private shiftValue: Shift = Shift.OFF;
  private chineseValue: boolean = false;
  private actionValue: Action = Action.RETURN;
  private lockedValue: boolean = false;
  private fullWidthValue: boolean = true;
  traditional: boolean = false;
  keyPopup: boolean = true;
  private palette: Palette = makePalette(false);
  private dark: boolean = false;

  private candidates: string[] = [];
  private preedit: string = '';
  private suggestKeys: string = '';
  private suggestWord: string = '';

  // MARK: - Kích thước

  width: number = 0;
  height: number = 0;
  private barH: number = 48;
  private topGap: number = 6;
  private keyH: number = 48;
  private gapY: number = 8;
  private bottomPad: number = 8;
  private blockL: number = 0;
  private blockR: number = 0;
  private rows: Key[][] = [];
  private screenH: number = 0;
  private splitPref: boolean = true;
  private split: boolean = false;
  private numberRow: boolean = false;
  private splitGapL: number = 0;
  private splitGapR: number = 0;

  private measurer: CanvasRenderingContext2D | null = null;

  constructor(listener: BoardListener) {
    this.listener = listener;
    this.buildRows();
  }

  get layout(): Layout {
    return this.layoutValue;
  }

  set layout(v: Layout) {
    if (this.layoutValue !== v) {
      this.layoutValue = v;
      this.buildRows();
      this.dirty();
    }
  }

  get shift(): Shift {
    return this.shiftValue;
  }

  set shift(v: Shift) {
    if (this.shiftValue !== v) {
      this.shiftValue = v;
      this.dirty();
    }
  }

  set chinese(v: boolean) {
    if (this.chineseValue !== v) {
      this.chineseValue = v;
      this.dirty();
    }
  }

  set action(v: Action) {
    if (this.actionValue !== v) {
      this.actionValue = v;
      this.dirty();
    }
  }

  /** Ô mật khẩu / số: chỉ gõ thẳng, menu chỉ còn bàn phím khác và cài đặt. */
  set modeLocked(v: boolean) {
    if (this.lockedValue !== v) {
      this.lockedValue = v;
      this.dirty();
    }
  }

  set fullWidth(v: boolean) {
    if (this.fullWidthValue !== v) {
      this.fullWidthValue = v;
      this.dirty();
    }
  }

  setDark(dark: boolean): void {
    if (this.dark !== dark) {
      this.dark = dark;
      this.palette = makePalette(dark);
      this.dirty();
    }
  }

  get background(): number {
    return this.palette.bg;
  }

  setCandidates(list: string[], preedit: string): void {
    if (preedit === this.preedit && list.length === this.candidates.length &&
      list.every((c: string, i: number) => c === this.candidates[i])) {
      return;
    }
    const wasGrid = this.gridOpen;
    this.candidates = list;
    this.preedit = preedit;
    this.stripScroll = 0;
    this.gridScroll = 0;
    if (list.length === 0) {
      this.gridOpen = false;
    }
    this.layoutCandidates();
    this.listener.redraw(wasGrid !== this.gridOpen);
  }

  /** Từ tiếng Việt đang gõ: các phím đã gõ và chữ đang hiện (rỗng khi không gõ). */
  setSuggestions(keys: string, word: string): void {
    if (keys === this.suggestKeys && word === this.suggestWord) {
      return;
    }
    this.suggestKeys = keys;
    this.suggestWord = word;
    this.listener.redraw(false);
  }

  /**
   * Tách đôi hai bên bản lề: màn rộng ≥ 600 vp (máy gập mở như Pura X Max ~795 vp, tablet) khi người dùng chọn
   * Split. Màn thấp < 500 vp (điện thoại xoay ngang) luôn một khối.
   */
  static splitFor(screenW: number, screenH: number, splitPref: boolean): boolean {
    return splitPref && screenW >= 600 && !(screenH > 0 && screenH < 500);
  }

  /** Hàng số 1–5 | 6–0 khi tách đôi trên màn cao ≥ 760 vp (tablet dọc). */
  static numberRowFor(split: boolean, screenH: number): boolean {
    return split && screenH >= 760;
  }

  /** Chiều cao bàn phím (vp) cho màn `screenW` × `screenH` (vp). */
  static heightFor(screenW: number, screenH: number, splitPref: boolean): number {
    const m = Metrics.of(screenH);
    const rows = Board.numberRowFor(Board.splitFor(screenW, screenH, splitPref), screenH) ? 5 : 4;
    return m.barH + m.topGap + rows * m.keyH + (rows - 1) * m.gapY + m.bottomPad;
  }

  /** Màn lớn (máy gập mở, tablet): true = tách đôi, false = một khối ở giữa. */
  set largeSplit(v: boolean) {
    if (this.splitPref !== v) {
      this.splitPref = v;
      this.configure();
    }
  }

  /** Cỡ theo màn hình hiện tại; gập/mở máy hay xoay màn thì gọi lại (bố cục đổi, chữ đang gõ giữ nguyên). */
  resize(width: number, height: number, screenH: number): void {
    const m = Metrics.of(screenH);
    this.keyH = m.keyH;
    this.barH = m.barH;
    this.topGap = m.topGap;
    this.gapY = m.gapY;
    this.bottomPad = m.bottomPad;
    this.width = width;
    this.height = height;
    this.screenH = screenH;
    this.configure();
  }

  /** Chọn kiểu bàn phím theo bề rộng; đổi kiểu thì đóng menu / lưới và dựng lại các hàng phím. */
  private configure(): void {
    const split = Board.splitFor(this.width, this.screenH, this.splitPref);
    const numberRow = Board.numberRowFor(split, this.screenH);
    if (split !== this.split || numberRow !== this.numberRow) {
      this.split = split;
      this.numberRow = numberRow;
      this.closeMenu();
      this.setGridOpen(false);
      this.buildRows();
    } else {
      this.layoutKeys();
    }
    this.dirty();
  }

  setMeasurer(ctx: CanvasRenderingContext2D): void {
    this.measurer = ctx;
    this.layoutCandidates();
  }

  private dirty(): void {
    this.listener.redraw(true);
  }

  private get rowsTop(): number {
    return this.barH + this.topGap;
  }

  private get rowsBottom(): number {
    return this.rowsTop + this.rows.length * this.keyH + (this.rows.length - 1) * this.gapY;
  }

  // MARK: - Bố cục phím

  private chars(s: string, units: number = 1): Key[] {
    const keys: Key[] = [];
    for (const c of s) {
      keys.push(new Key(Kind.CHAR, c, units));
    }
    return keys;
  }

  private buildRows(): void {
    if (this.split) {
      this.rows = this.splitRows();
      this.layoutKeys();
      return;
    }
    const bottom: Key[] = [
      this.layoutValue === Layout.LETTERS ? new Key(Kind.NUMBERS, '?123', 1.5) : new Key(Kind.LETTERS, 'ABC', 1.5),
      new Key(Kind.MODE),
      new Key(Kind.CHAR, ',', 1, '', true),
      new Key(Kind.SPACE, '', 4),
      new Key(Kind.CHAR, '.', 1, '', true),
      new Key(Kind.RETURN, '', 1.5),
    ];
    const third = (left: Key): Key[] =>
      [left, ...this.chars('.,?!\'', 1.4), new Key(Kind.BACKSPACE, '', 1.5)];
    if (this.layoutValue === Layout.LETTERS) {
      const top: Key[] = [];
      const q = 'qwertyuiop';
      for (let i = 0; i < q.length; i++) {
        top.push(new Key(Kind.CHAR, q[i], 1, `${(i + 1) % 10}`));
      }
      this.rows = [
        top,
        [new Key(Kind.SPACER, '', 0.5), ...this.chars('asdfghjkl'), new Key(Kind.SPACER, '', 0.5)],
        [new Key(Kind.SHIFT, '', 1.5), ...this.chars('zxcvbnm'), new Key(Kind.BACKSPACE, '', 1.5)],
        bottom,
      ];
    } else if (this.layoutValue === Layout.NUMBERS) {
      this.rows = [this.chars('1234567890'), this.chars('-/:;()$&@"'), third(new Key(Kind.SYMBOLS, '#+=', 1.5)), bottom];
    } else {
      this.rows = [this.chars('[]{}#%^*+='), this.chars('_\\|~<>€£¥•'), third(new Key(Kind.NUMBERS, '123', 1.5)), bottom];
    }
    this.layoutKeys();
  }

  /**
   * Tách đôi (giống bản Android): mỗi nửa 5 đơn vị. Trái: 1–5 / q w e r t / a s d f g / Shift z x c v /
   * ?123 Globe , Space. Phải: 6–0 / y u i o p / h j k l / b n m ⌫ / Space . Enter. Khoảng giữa (GAP) nằm trên bản lề.
   */
  private splitRows(): Key[][] {
    const gap = (): Key => new Key(Kind.GAP);
    const bottom: Key[] = [
      this.layoutValue === Layout.LETTERS ? new Key(Kind.NUMBERS, '?123', 1.5) : new Key(Kind.LETTERS, 'ABC', 1.5),
      new Key(Kind.MODE), new Key(Kind.CHAR, ',', 1, '', true), new Key(Kind.SPACE, '', 1.5),
      gap(),
      new Key(Kind.SPACE, '', 2), new Key(Kind.CHAR, '.', 1, '', true), new Key(Kind.RETURN, '', 2),
    ];
    const digits = (): Key[] => [...this.chars('12345'), gap(), ...this.chars('67890')];
    const third = (left: Key): Key[] =>
      [left, ...this.chars('.,?', 1.2), gap(), ...this.chars('!\'', 1.2), new Key(Kind.SPACER, '', 0.6), new Key(Kind.BACKSPACE, '', 2)];
    const sym1 = (): Key[] => [...this.chars('-/:;('), gap(), ...this.chars(')$&@"')];
    const sym2 = (): Key[] => [...this.chars('_\\|~<'), gap(), ...this.chars('>€£¥•')];
    const brackets = (): Key[] => [...this.chars('[]{}#'), gap(), ...this.chars('%^*+=')];
    if (this.layoutValue === Layout.LETTERS) {
      const top: Key[] = [];
      const left = 'qwert';
      const right = 'yuiop';
      for (let i = 0; i < 5; i++) {
        top.push(new Key(Kind.CHAR, left[i], 1, this.numberRow ? '' : `${i + 1}`));
      }
      top.push(gap());
      for (let i = 0; i < 5; i++) {
        top.push(new Key(Kind.CHAR, right[i], 1, this.numberRow ? '' : `${(i + 6) % 10}`));
      }
      const rows: Key[][] = this.numberRow ? [digits()] : [];
      rows.push(top);
      rows.push([...this.chars('asdfg'), gap(), new Key(Kind.SPACER, '', 0.5), ...this.chars('hjkl'), new Key(Kind.SPACER, '', 0.5)]);
      rows.push([new Key(Kind.SHIFT), ...this.chars('zxcv'), gap(), ...this.chars('bnm'), new Key(Kind.BACKSPACE, '', 2)]);
      rows.push(bottom);
      return rows;
    }
    // cùng số hàng với lớp chữ để chiều cao bàn phím không đổi khi chuyển lớp
    if (this.layoutValue === Layout.NUMBERS) {
      return this.numberRow ? [digits(), sym1(), brackets(), third(new Key(Kind.SYMBOLS, '#+=', 1.4)), bottom] :
        [digits(), sym1(), third(new Key(Kind.SYMBOLS, '#+=', 1.4)), bottom];
    }
    return this.numberRow ? [digits(), brackets(), sym2(), third(new Key(Kind.NUMBERS, '123', 1.4)), bottom] :
      [brackets(), sym2(), third(new Key(Kind.NUMBERS, '123', 1.4)), bottom];
  }

  private layoutKeys(): void {
    if (this.width <= 0) {
      return;
    }
    if (this.split) {
      this.layoutSplit();
      this.layoutCandidates();
      return;
    }
    // điện thoại: lề 4, phím (W − 8 − 54)/10; màn rộng ≥ 600 vp: một khối, phím tối đa 64 vp, canh giữa
    const wide = this.width >= 600;
    const side = wide ? 12 : 4;
    let unit = (this.width - 2 * side + GAP_X) / 10;
    if (wide) {
      unit = Math.min(unit, 64 + GAP_X);
    }
    this.blockL = (this.width - (10 * unit - GAP_X)) / 2;
    this.blockR = this.width - this.blockL;
    for (let r = 0; r < this.rows.length; r++) {
      let x = this.blockL - GAP_X / 2;
      const top = this.rowsTop + r * (this.keyH + this.gapY);
      for (const k of this.rows[r]) {
        const w = k.units * unit;
        k.x = x + GAP_X / 2;
        k.y = top;
        k.w = w - GAP_X;
        k.h = this.keyH;
        x += w;
      }
    }
    this.layoutCandidates();
  }

  /** Phím rộng clamp((W/2 − 44)/5, 56, 64) vp; hai nửa sát hai mép, khoảng hở giữa nằm trên bản lề. */
  private layoutSplit(): void {
    const side = 12;
    const key = Math.max(56, Math.min(64, (this.width / 2 - 44) / 5));
    const unit = key + GAP_X;
    const half = 5 * unit - GAP_X;
    this.blockL = side;
    this.blockR = this.width - side;
    this.splitGapL = this.blockL + half;
    this.splitGapR = this.blockR - half;
    for (let r = 0; r < this.rows.length; r++) {
      const top = this.rowsTop + r * (this.keyH + this.gapY);
      let x = this.blockL - GAP_X / 2;
      for (const k of this.rows[r]) {
        k.y = top;
        k.h = this.keyH;
        if (k.kind === Kind.GAP) {
          k.x = this.splitGapL;
          k.w = this.splitGapR - this.splitGapL;
          x = this.splitGapR - GAP_X / 2;
          continue;
        }
        const w = k.units * unit;
        k.x = x + GAP_X / 2;
        k.w = w - GAP_X;
        x += w;
      }
    }
  }

  // MARK: - Vẽ

  private font(size: number, weight: string = 'normal'): string {
    return `normal ${weight} ${size}vp ${FONT}`;
  }

  private drawIcon(ctx: CanvasRenderingContext2D, path: Path2D, cx: number, cy: number, size: number, color: number,
    filled: boolean = false, alpha: number = 1): void {
    const s = size / 24;
    ctx.save();
    ctx.translate(cx - 12 * s, cy - 12 * s);
    ctx.scale(s, s);
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = css(color, alpha);
    if (filled) {
      ctx.fillStyle = css(color, alpha);
      ctx.fill(path);
    }
    ctx.stroke(path);
    ctx.restore();
  }

  private roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number, color: string): void {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, r);
    ctx.fill();
  }

  private text(ctx: CanvasRenderingContext2D, s: string, x: number, y: number, size: number, color: number,
    weight: string = 'normal', align: CanvasTextAlign = 'center', alpha: number = 1): void {
    ctx.font = this.font(size, weight);
    ctx.textAlign = align;
    ctx.textBaseline = 'middle';
    ctx.fillStyle = css(color, alpha);
    ctx.fillText(s, x, y);
  }

  private measure(s: string, size: number, weight: string = 'normal'): number {
    const m = this.measurer;
    if (m === null) {
      return s.length * size * 0.6;
    }
    m.font = this.font(size, weight);
    return m.measureText(s).width;
  }

  /** Lớp phím tĩnh. */
  drawStatic(ctx: CanvasRenderingContext2D): void {
    ctx.clearRect(0, 0, this.width, this.height);
    ctx.fillStyle = css(this.palette.bg);
    ctx.fillRect(0, 0, this.width, this.height);
    if (this.gridOpen) {
      return;
    }
    for (const row of this.rows) {
      for (const k of row) {
        if (k.isKey) {
          this.drawKey(ctx, k, false);
        }
      }
    }
  }

  /** Lớp trên: phím đang nhấn, bóng chữ, thanh gợi ý, lưới ứng viên, menu. */
  drawDynamic(ctx: CanvasRenderingContext2D): void {
    ctx.clearRect(0, 0, this.width, this.height);
    this.drawBar(ctx);
    if (this.gridOpen) {
      this.drawGrid(ctx);
    } else {
      this.pressed.forEach((t: Touch) => this.drawKey(ctx, t.key, true));
      if (this.menuOpen) {
        const globe = this.rows[this.rows.length - 1].find((k: Key) => k.kind === Kind.MODE);
        if (globe !== undefined) {
          this.drawKey(ctx, globe, true);
        }
      }
      if (this.keyPopup) {
        this.pressed.forEach((t: Touch) => {
          if (t.key.kind === Kind.CHAR && !t.trackpad) {
            this.drawPopup(ctx, t);
          }
        });
      }
    }
    if (this.menuOpen) {
      this.drawMenu(ctx);
    }
  }

  private drawKey(ctx: CanvasRenderingContext2D, k: Key, pressed: boolean): void {
    const p = this.palette;
    const isReturn = k.kind === Kind.RETURN;
    const base = isReturn ? p.primary : (k.isFunction ? p.fn : p.key);
    if (!pressed) {
      this.roundRect(ctx, k.x, k.y + 1, k.w, k.h, RADIUS, css(p.shadow)); // bóng 1 vp dưới phím
    }
    this.roundRect(ctx, k.x, k.y, k.w, k.h, RADIUS, css(base));
    let fg = isReturn ? p.onPrimary : p.text;
    let iconColor = isReturn ? p.onPrimary : p.icon;
    if (pressed) {
      this.roundRect(ctx, k.x, k.y, k.w, k.h, RADIUS, isReturn ? css(p.onPrimary, 0.18) : css(p.container));
      if (!isReturn) {
        fg = p.onContainer;
        iconColor = p.onContainer;
      }
    }
    const cx = k.cx;
    const cy = k.cy;
    switch (k.kind) {
      case Kind.CHAR: {
        this.text(ctx, this.keyLabel(k), cx, cy, 22, fg);
        const hint = this.keyHint(k);
        if (hint.length > 0) {
          ctx.font = this.font(11);
          ctx.textAlign = 'right';
          ctx.textBaseline = 'top';
          ctx.fillStyle = css(p.hint);
          ctx.fillText(hint, k.x + k.w - 5, k.y + 3);
        }
        break;
      }
      case Kind.SHIFT: {
        const color = this.shiftValue === Shift.OFF ? iconColor : p.primary;
        const lock = this.shiftValue === Shift.LOCK;
        this.drawIcon(ctx, Icons.shift, cx, cy - (lock ? 2 : 0), 22, color, this.shiftValue !== Shift.OFF);
        if (lock) {
          this.roundRect(ctx, cx - 5, cy + 10, 10, 2, 1, css(p.primary));
        }
        break;
      }
      case Kind.BACKSPACE:
        this.drawIcon(ctx, Icons.backspace, cx, cy, 22, iconColor);
        break;
      case Kind.RETURN:
        this.drawIcon(ctx, this.returnIcon(), cx, cy, 22, iconColor);
        break;
      case Kind.MODE:
        if (this.lockedValue) {
          this.drawIcon(ctx, Icons.globe, cx, cy, 20, iconColor);
        } else {
          this.drawIcon(ctx, Icons.globe, cx, cy - 6.5, 18, iconColor);
          this.text(ctx, this.chineseNow() ? '拼' : 'VI', cx, cy + 12, 10, iconColor, 'bold');
        }
        break;
      case Kind.SPACE:
        this.text(ctx, this.lockedValue ? 'space' : (this.chineseNow() ? '拼音' : 'VI · EN'), cx, cy, 12, p.hint, '500');
        break;
      default:
        this.text(ctx, k.label, cx, cy, 14, fg, '500');
    }
  }

  private returnIcon(): Path2D {
    switch (this.actionValue) {
      case Action.SEND:
        return Icons.send;
      case Action.SEARCH:
        return Icons.search;
      case Action.GO:
      case Action.NEXT:
        return Icons.arrow;
      case Action.DONE:
        return Icons.check;
      default:
        return Icons.enter;
    }
  }

  private chineseNow(): boolean {
    return this.chineseValue && !this.lockedValue;
  }

  private keyLabel(k: Key): string {
    if (k.punct && this.chineseNow() && this.fullWidthValue) {
      return k.label === ',' ? '，' : '。';
    }
    if (this.layoutValue === Layout.LETTERS && this.shiftValue !== Shift.OFF) {
      return k.label.toUpperCase();
    }
    return k.label;
  }

  private keyHint(k: Key): string {
    if (this.layoutValue !== Layout.LETTERS) {
      return '';
    }
    if (k.hint.length > 0) {
      return k.hint;
    }
    return k.label === 'v' && this.chineseNow() ? 'ü' : '';
  }

  /** Bóng chữ khi nhấn: cao 60, rộng phím + 16, đáy cách đáy phím 36 vp (phủ đầu phím), chữ 30. */
  private drawPopup(ctx: CanvasRenderingContext2D, t: Touch): void {
    const k = t.key;
    const w = k.w + 16;
    const h = 60;
    const left = Math.max(2, Math.min(this.width - w - 2, k.cx - w / 2));
    const bottom = k.y + k.h - 36;
    const top = Math.max(0, bottom - h);
    ctx.save();
    ctx.shadowBlur = 4;
    ctx.shadowOffsetY = 2;
    ctx.shadowColor = 'rgba(0,0,0,0.28)';
    this.roundRect(ctx, left, top, w, bottom - top, 10, css(this.palette.popup));
    ctx.restore();
    const label = t.longFired && k.hint.length > 0 ? k.hint : this.keyLabel(k);
    this.text(ctx, label, left + w / 2, (top + bottom) / 2, 30, this.palette.text);
  }

  // MARK: - Thanh gợi ý: [dán 44] [giữa] [mở rộng 44]

  private candidateRects: Rect[] = [];
  private stripScroll: number = 0;
  private stripContentWidth: number = 0;
  private preeditWidth: number = 0;

  private get midL(): number {
    return this.blockL + SIDE_ICON + 2;
  }

  private get midR(): number {
    return this.blockR - SIDE_ICON - 2;
  }

  private layoutCandidates(): void {
    // pinyin đang gõ khi ô nhập không hiện được chữ tạm: ghi ở đầu thanh, trước các ứng viên
    this.preeditWidth = this.preedit.length > 0 ? this.measure(this.preedit, 14) + 16 : 0;
    let x = this.midL + 2 + this.preeditWidth;
    const cy = this.barH / 2;
    const rects: Rect[] = [];
    for (let i = 0; i < this.candidates.length; i++) {
      let w = this.measure(this.candidates[i], 19, '500') + 24;
      if (i < 9) {
        w += this.measure(`${i + 1}`, 11) + 5;
      }
      rects.push(new Rect(x, cy - 18, x + w, cy + 18));
      x += w + 4;
    }
    this.candidateRects = rects;
    this.stripContentWidth = x - this.midL;
    this.layoutGrid();
  }

  private drawBar(ctx: CanvasRenderingContext2D): void {
    const p = this.palette;
    const cy = this.barH / 2;
    const l = this.blockL + SIDE_ICON / 2;
    const r = this.blockR - SIDE_ICON / 2;
    if (this.barPressed === BAR_PASTE) {
      this.pressedCircle(ctx, l, cy);
    }
    this.drawIcon(ctx, Icons.clipboard, l, cy, 22, p.icon);
    if (this.candidates.length > 0 || this.preedit.length > 0) {
      if (this.candidates.length > 0) {
        if (this.barPressed === BAR_RIGHT) {
          this.pressedCircle(ctx, r, cy);
        }
        this.drawIcon(ctx, this.gridOpen ? Icons.chevronUp : Icons.chevronDown, r, cy, 22, p.icon);
      }
      this.drawCandidates(ctx);
    } else {
      this.drawSuggestions(ctx);
    }
  }

  private pressedCircle(ctx: CanvasRenderingContext2D, cx: number, cy: number): void {
    ctx.fillStyle = css(this.palette.text, 0x1F / 255);
    ctx.beginPath();
    ctx.arc(cx, cy, 20, 0, Math.PI * 2);
    ctx.fill();
  }

  private drawCandidates(ctx: CanvasRenderingContext2D): void {
    const p = this.palette;
    const cy = this.barH / 2;
    ctx.save();
    ctx.beginPath();
    ctx.rect(this.midL, 0, this.midR - this.midL, this.barH);
    ctx.clip();
    ctx.translate(-this.stripScroll, 0);
    if (this.preedit.length > 0) {
      this.text(ctx, this.preedit, this.midL + 8, cy, 14, p.hint, 'normal', 'left');
    }
    for (let i = 0; i < this.candidateRects.length; i++) {
      const rc = this.candidateRects[i];
      if (rc.r < this.midL + this.stripScroll || rc.l > this.midR + this.stripScroll) {
        continue;
      }
      const first = i === 0;
      if (first) {
        this.roundRect(ctx, rc.l, rc.t, rc.r - rc.l, rc.b - rc.t, RADIUS, css(p.container));
      } else if (i === this.pressedCandidate) {
        this.roundRect(ctx, rc.l, rc.t, rc.r - rc.l, rc.b - rc.t, RADIUS, css(p.text, 0x1F / 255));
      }
      let x = rc.l + 12;
      if (i < 9) {
        const n = `${i + 1}`;
        ctx.font = this.font(11);
        ctx.textAlign = 'left';
        ctx.textBaseline = 'alphabetic';
        ctx.fillStyle = first ? css(p.onContainer, 0.8) : css(p.faint);
        ctx.fillText(n, x, cy + 5.5);
        x += ctx.measureText(n).width + 5;
      }
      this.text(ctx, this.candidates[i], x, cy, 19, first ? p.onContainer : p.text, '500', 'left');
    }
    ctx.restore();
    // mép phải mờ dần báo còn ứng viên
    if (this.stripContentWidth - this.stripScroll > this.midR - this.midL) {
      const g = ctx.createLinearGradient(this.midR - 28, 0, this.midR, 0);
      g.addColorStop(0, css(p.bg, 0));
      g.addColorStop(1, css(p.bg));
      ctx.fillStyle = g;
      ctx.fillRect(this.midR - 28, 0, 28, this.barH);
    }
  }

  /** Ba ô chia đều: [các phím đã gõ] · **chữ đang hiện** · [trống]. Không có gợi ý thì để trống, không bịa. */
  private suggestionCells(): string[] {
    if (this.suggestWord.length === 0) {
      return [];
    }
    if (this.suggestKeys === this.suggestWord || this.suggestKeys.length === 0) {
      return ['', this.suggestWord, ''];
    }
    return [this.suggestKeys, this.suggestWord, ''];
  }

  /** Cụm gợi ý: tối đa 420 vp ở giữa (màn rộng). */
  private get sugL(): number {
    return Math.max(this.midL, (this.midL + this.midR) / 2 - 210);
  }

  private get sugR(): number {
    return Math.min(this.midR, (this.midL + this.midR) / 2 + 210);
  }

  private ellipsizeStart(s: string, size: number, weight: string, room: number): string {
    if (this.measure(s, size, weight) <= room) {
      return s;
    }
    let t = s;
    while (t.length > 1 && this.measure('…' + t, size, weight) > room) {
      t = t.substring(1);
    }
    return '…' + t;
  }

  private drawSuggestions(ctx: CanvasRenderingContext2D): void {
    const p = this.palette;
    const cells = this.suggestionCells();
    if (cells.length === 0) {
      return;
    }
    const w = (this.sugR - this.sugL) / 3;
    const cy = this.barH / 2;
    for (let i = 0; i < cells.length; i++) {
      if (cells[i].length === 0) {
        continue;
      }
      const l = this.sugL + i * w;
      if (i === this.pressedSuggestion) {
        this.roundRect(ctx, l + 2, cy - 18, w - 4, 36, RADIUS, css(p.text, 0x1F / 255));
      }
      const weight = i === 1 ? 'bold' : 'normal';
      this.text(ctx, this.ellipsizeStart(cells[i], 16, weight, w - 12), l + w / 2, cy, 16, p.text, weight);
      if (i === 0) {
        ctx.fillStyle = css(p.divider);
        ctx.fillRect(l + w - 0.5, cy - 11, 1, 22);
      }
    }
  }

  // MARK: - Lưới ứng viên: thay chỗ các hàng phím, cuộn dọc

  private gridOpen: boolean = false;
  private gridRects: Rect[] = [];
  private gridScroll: number = 0;
  private gridContentHeight: number = 0;

  private get gridTop(): number {
    return this.rowsTop - this.topGap / 2;
  }

  private get gridBottom(): number {
    return this.rowsBottom + this.bottomPad / 2;
  }

  private setGridOpen(v: boolean): void {
    if (this.gridOpen !== v) {
      this.gridOpen = v;
      this.gridScroll = 0;
      this.dirty();
    }
  }

  private layoutGrid(): void {
    const cell = 48;
    const pad = 3;
    let x = this.blockL;
    let y = this.gridTop + pad;
    const rects: Rect[] = [];
    const span = this.blockR - this.blockL;
    for (const c of this.candidates) {
      const w = Math.max(this.measure(c, 20, '500') + 28, span / 6 - pad);
      if (x + w > this.blockR + 0.5 && x > this.blockL) {
        x = this.blockL;
        y += cell + pad;
      }
      rects.push(new Rect(x, y, Math.min(x + w, this.blockR), y + cell));
      x += w + pad;
    }
    // hàng đầy (trừ hàng cuối): chia phần thừa cho các ô để hai mép thẳng hàng
    let start = 0;
    while (start < rects.length) {
      let end = start;
      while (end + 1 < rects.length && rects[end + 1].t === rects[start].t) {
        end++;
      }
      if (end + 1 < rects.length) {
        const n = end - start + 1;
        const extra = (this.blockR - rects[end].r) / n;
        for (let j = 0; j < n; j++) {
          rects[start + j].l += extra * j;
          rects[start + j].r += extra * (j + 1);
        }
      }
      start = end + 1;
    }
    this.gridRects = rects;
    this.gridContentHeight = (rects.length > 0 ? rects[rects.length - 1].b : this.gridTop) - this.gridTop + pad;
  }

  private drawGrid(ctx: CanvasRenderingContext2D): void {
    const p = this.palette;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, this.gridTop, this.width, this.gridBottom - this.gridTop);
    ctx.clip();
    ctx.translate(0, -this.gridScroll);
    for (let i = 0; i < this.gridRects.length; i++) {
      const r = this.gridRects[i];
      if (r.b < this.gridTop + this.gridScroll || r.t > this.gridBottom + this.gridScroll) {
        continue;
      }
      this.roundRect(ctx, r.l, r.t, r.r - r.l, r.b - r.t, RADIUS, css(i === 0 ? p.container : p.key));
      if (i === this.pressedCandidate) {
        this.roundRect(ctx, r.l, r.t, r.r - r.l, r.b - r.t, RADIUS, css(p.text, 0x1F / 255));
      }
      this.text(ctx, this.candidates[i], (r.l + r.r) / 2, (r.t + r.b) / 2, 20, i === 0 ? p.onContainer : p.text, '500');
    }
    ctx.restore();
  }

  // MARK: - Chạm

  private pressed: Map<number, Touch> = new Map<number, Touch>();
  private lastShiftTap: number = 0;
  private barTouch: number = -1;
  private barRegion: number = -1;
  private barPressed: number = -1;
  private barDownX: number = 0;
  private barDownY: number = 0;
  private barDownScroll: number = 0;
  private barDragged: boolean = false;
  private pressedCandidate: number = -1;
  private pressedSuggestion: number = -1;
  private repeatTimer: number = -1;
  private globeHold: number = -1;

  private hit(x: number, y: number): Key | null {
    if (y < this.rowsTop - this.topGap) {
      return null;
    }
    if (this.split && x > this.splitGapL && x < this.splitGapR) {
      return null; // khoảng trên bản lề: không phải phím
    }
    const r = Math.max(0, Math.min(this.rows.length - 1, Math.floor((y - this.rowsTop + this.gapY / 2) / (this.keyH + this.gapY))));
    let best: Key | null = null;
    let bestD = Number.MAX_VALUE;
    for (const k of this.rows[r]) {
      if (!k.isKey) {
        continue;
      }
      const d = x < k.x ? k.x - x : (x > k.x + k.w ? x - k.x - k.w : 0);
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  private stopRepeat(): void {
    if (this.repeatTimer >= 0) {
      clearTimeout(this.repeatTimer);
      clearInterval(this.repeatTimer);
      this.repeatTimer = -1;
    }
  }

  private startRepeat(): void {
    this.stopRepeat();
    this.repeatTimer = setTimeout(() => {
      this.repeatTimer = setInterval(() => {
        this.listener.onKey(new KeyInput(KeyKind.BACKSPACE));
        this.listener.feedback();
      }, 50);
    }, 400);
  }

  touchDown(id: number, x: number, y: number): void {
    if (this.menuOpen) {
      // menu đang mở: chạm vào mục để chọn, chạm chỗ khác để đóng
      const m = this.menuItemAt(x, y);
      if (m >= 0) {
        this.menuHighlight = m;
        this.menuPointer = id;
      } else {
        this.closeMenu();
      }
      this.listener.redraw(false);
      return;
    }
    if (this.pressed.size === 0 && this.barTouch < 0 && (y < this.rowsTop - this.topGap || (this.gridOpen && y < this.gridBottom))) {
      this.barTouch = id;
      this.barDownX = x;
      this.barDownY = y;
      this.barDragged = false;
      if (y >= this.barH) {
        this.barRegion = BAR_GRID;
      } else if (x < this.blockL + SIDE_ICON) {
        this.barRegion = BAR_PASTE;
      } else if (x > this.blockR - SIDE_ICON) {
        this.barRegion = BAR_RIGHT;
      } else {
        this.barRegion = BAR_MID;
      }
      this.barPressed = this.barRegion === BAR_PASTE || (this.barRegion === BAR_RIGHT && this.candidates.length > 0) ? this.barRegion : -1;
      if (this.barRegion === BAR_GRID) {
        this.barDownScroll = this.gridScroll;
        this.pressedCandidate = this.gridAt(x, y);
      } else if (this.barRegion === BAR_MID) {
        this.barDownScroll = this.stripScroll;
        if (this.candidates.length > 0) {
          this.pressedCandidate = this.candidateAt(x);
        } else {
          this.pressedSuggestion = this.suggestionAt(x);
        }
      }
      this.listener.redraw(false);
      return;
    }
    if (this.gridOpen) {
      return;
    }
    const k = this.hit(x, y);
    if (k === null) {
      return;
    }
    // ngón thứ hai chạm: phím của ngón trước được gõ luôn (gõ nhanh hai tay). Cả phím quả địa cầu:
    // chạm quả địa cầu rồi gõ ngay "n" thì đổi bộ gõ trước, "n" mới vào bộ gõ mới
    const early: number[] = [];
    this.pressed.forEach((t: Touch, pid: number) => {
      if (t.key.kind === Kind.CHAR || t.key.kind === Kind.SPACE || t.key.kind === Kind.MODE) {
        early.push(pid);
      }
    });
    for (const pid of early) {
      const t = this.pressed.get(pid) as Touch;
      if (t.longPress >= 0) {
        clearTimeout(t.longPress);
      }
      this.pressed.delete(pid);
      if (!t.trackpad && !t.longFired) {
        this.fire(t.key);
      }
    }
    this.listener.feedback();
    const touch = new Touch(k, x);
    switch (k.kind) {
      case Kind.SHIFT:
        this.tapShift();
        this.listener.redraw(false);
        return;
      case Kind.MODE:
        this.cancelGlobeHold();
        this.globeHold = setTimeout(() => this.holdGlobe(k, id), 300);
        break;
      case Kind.BACKSPACE:
        this.listener.onKey(new KeyInput(KeyKind.BACKSPACE));
        this.startRepeat();
        break;
      case Kind.CHAR: {
        const hint = this.keyHint(k);
        if (hint.length > 0 && hint[0] >= '0' && hint[0] <= '9') {
          // giữ phím hàng trên: gõ số ở góc phím thay cho chữ
          touch.longPress = setTimeout(() => {
            if (this.pressed.get(id) === touch && touch.key === k) {
              touch.longFired = true;
              this.listener.feedback();
              this.listener.onKey(KeyInput.char(k.hint));
              this.listener.redraw(false);
            }
          }, 400);
        }
        break;
      }
      default:
        break;
    }
    this.pressed.set(id, touch);
    this.listener.redraw(false);
  }

  touchMove(id: number, x: number, y: number): void {
    if (this.menuOpen) {
      if (id === this.menuPointer) {
        // giữ phím quả địa cầu rồi trượt lên mục cần chọn
        const m = this.menuItemAt(x, y);
        if (m !== this.menuHighlight) {
          this.menuHighlight = m;
          if (m >= 0) {
            this.listener.feedback();
          }
          this.listener.redraw(false);
        }
      }
      return;
    }
    if (id === this.barTouch) {
      if (this.barRegion === BAR_MID && this.candidates.length > 0) {
        const dx = x - this.barDownX;
        if (Math.abs(dx) > 8) {
          this.barDragged = true;
          this.pressedCandidate = -1;
        }
        if (this.barDragged) {
          this.stripScroll = Math.max(0, Math.min(Math.max(0, this.stripContentWidth - (this.midR - this.midL)), this.barDownScroll - dx));
          this.listener.redraw(false);
        }
      } else if (this.barRegion === BAR_GRID) {
        const dy = y - this.barDownY;
        if (Math.abs(dy) > 8) {
          this.barDragged = true;
          this.pressedCandidate = -1;
        }
        if (this.barDragged) {
          const max = Math.max(0, this.gridContentHeight - (this.gridBottom - this.gridTop));
          this.gridScroll = Math.max(0, Math.min(max, this.barDownScroll - dy));
          this.listener.redraw(false);
        }
      }
      return;
    }
    const t = this.pressed.get(id);
    if (t === undefined) {
      return;
    }
    if (t.key.kind === Kind.SPACE) {
      // kéo trên phím cách: di chuyển con trỏ
      if (!t.trackpad && Math.abs(x - t.startX) > 14) {
        t.trackpad = true;
        t.lastX = x;
        this.listener.redraw(false);
      }
      if (t.trackpad) {
        const step = 11;
        while (x - t.lastX > step) {
          this.listener.onCursor(1);
          t.lastX += step;
        }
        while (t.lastX - x > step) {
          this.listener.onCursor(-1);
          t.lastX -= step;
        }
      }
    } else if (t.key.kind === Kind.CHAR && !t.longFired) {
      const k = this.hit(x, y);
      if (k !== null && k !== t.key && k.kind === Kind.CHAR) {
        if (t.longPress >= 0) {
          clearTimeout(t.longPress);
          t.longPress = -1;
        }
        t.key = k;
        this.listener.redraw(false);
      }
    }
  }

  touchUp(id: number, x: number, y: number): void {
    if (this.menuOpen && id === this.menuPointer) {
      this.menuPointer = -1;
      // thả trên một mục: chọn; thả trên phím quả địa cầu: menu vẫn mở để chạm chọn
      if (this.menuHighlight >= 0) {
        const choice = this.menuItems[this.menuHighlight].choice;
        this.closeMenu();
        this.listener.onPickInput(choice);
      }
      this.listener.redraw(false);
      return;
    }
    if (id === this.barTouch) {
      this.finishBarTouch(x, y);
      return;
    }
    const t = this.pressed.get(id);
    if (t === undefined) {
      return;
    }
    this.pressed.delete(id);
    if (t.longPress >= 0) {
      clearTimeout(t.longPress);
    }
    if (t.key.kind === Kind.BACKSPACE) {
      this.stopRepeat();
    } else if (!t.trackpad && !t.longFired) {
      this.fire(t.key);
    }
    if (t.key.kind === Kind.MODE) {
      this.cancelGlobeHold();
    }
    this.listener.redraw(false);
  }

  touchCancel(): void {
    this.cancelGlobeHold();
    this.closeMenu();
    this.pressed.forEach((t: Touch) => {
      if (t.longPress >= 0) {
        clearTimeout(t.longPress);
      }
    });
    this.pressed.clear();
    this.stopRepeat();
    this.barTouch = -1;
    this.barPressed = -1;
    this.pressedCandidate = -1;
    this.pressedSuggestion = -1;
    this.listener.redraw(false);
  }

  private finishBarTouch(x: number, y: number): void {
    if (!this.barDragged) {
      switch (this.barRegion) {
        case BAR_PASTE:
          if (x < this.blockL + SIDE_ICON) {
            this.listener.feedback();
            this.listener.onPaste();
          }
          break;
        case BAR_RIGHT:
          if (x > this.blockR - SIDE_ICON && this.candidates.length > 0) {
            this.listener.feedback();
            this.setGridOpen(!this.gridOpen);
          }
          break;
        case BAR_MID:
          if (this.candidates.length > 0) {
            const c = this.candidateAt(x);
            if (c >= 0 && c === this.pressedCandidate) {
              this.listener.feedback();
              this.listener.onCandidate(c);
            }
          } else {
            const s = this.suggestionAt(x);
            if (s >= 0 && s === this.pressedSuggestion) {
              this.listener.feedback();
              this.listener.onSuggestion(s === 0 ? 0 : 1);
            }
          }
          break;
        case BAR_GRID: {
          const c = this.gridAt(x, y);
          if (c >= 0 && c === this.pressedCandidate) {
            this.listener.feedback();
            this.setGridOpen(false);
            this.listener.onCandidate(c);
          }
          break;
        }
        default:
          break;
      }
    }
    this.barTouch = -1;
    this.barPressed = -1;
    this.pressedCandidate = -1;
    this.pressedSuggestion = -1;
    this.listener.redraw(false);
  }

  private candidateAt(x: number): number {
    if (x < this.midL || x > this.midR) {
      return -1;
    }
    const cx = x + this.stripScroll;
    return this.candidateRects.findIndex((r: Rect) => cx >= r.l - 2 && cx <= r.r + 2);
  }

  private gridAt(x: number, y: number): number {
    const gy = y + this.gridScroll;
    return this.gridRects.findIndex((r: Rect) => r.contains(x, gy));
  }

  private suggestionAt(x: number): number {
    const cells = this.suggestionCells();
    if (cells.length === 0 || x < this.sugL || x > this.sugR) {
      return -1;
    }
    const i = Math.max(0, Math.min(2, Math.floor((x - this.sugL) / ((this.sugR - this.sugL) / 3))));
    return cells[i].length > 0 ? i : -1;
  }

  private tapShift(): void {
    const now = Date.now();
    if (this.shiftValue === Shift.LOCK) {
      this.shift = Shift.OFF;
    } else if (this.shiftValue === Shift.OFF) {
      this.shift = Shift.ONCE;
    } else {
      this.shift = now - this.lastShiftTap < 350 ? Shift.LOCK : Shift.OFF;
    }
    this.lastShiftTap = now;
  }

  private fire(k: Key): void {
    switch (k.kind) {
      case Kind.CHAR: {
        const letters = this.layoutValue === Layout.LETTERS;
        const s = letters && this.shiftValue !== Shift.OFF && !k.punct ? k.label.toUpperCase() : k.label;
        if (this.shiftValue === Shift.ONCE && letters && !k.punct) {
          this.shift = Shift.OFF;
        }
        this.listener.onKey(KeyInput.char(s));
        if (!letters && s === '\'') {
          this.layout = Layout.LETTERS;
        }
        break;
      }
      case Kind.SPACE:
        this.listener.onKey(new KeyInput(KeyKind.SPACE));
        if (this.layoutValue !== Layout.LETTERS) {
          this.layout = Layout.LETTERS;
        }
        break;
      case Kind.RETURN:
        this.listener.onKey(new KeyInput(KeyKind.ENTER));
        break;
      case Kind.NUMBERS:
        this.layout = Layout.NUMBERS;
        break;
      case Kind.SYMBOLS:
        this.layout = Layout.SYMBOLS;
        break;
      case Kind.LETTERS:
        this.layout = Layout.LETTERS;
        break;
      case Kind.MODE:
        this.cancelGlobeHold();
        this.listener.onPickInput(PICK_TOGGLE);
        break;
      default:
        break;
    }
  }

  private cancelGlobeHold(): void {
    if (this.globeHold >= 0) {
      clearTimeout(this.globeHold);
      this.globeHold = -1;
    }
  }

  /** Giữ phím quả địa cầu 300 ms: thay cho lần chạm, mở menu (vẫn trượt ngón lên để chọn được). */
  private holdGlobe(globe: Key, pointer: number): void {
    this.globeHold = -1;
    const t = this.pressed.get(pointer);
    if (t === undefined || t.key !== globe) {
      return;
    }
    this.pressed.delete(pointer);
    this.listener.feedback();
    this.openMenu(globe, pointer);
  }

  // MARK: - Menu phím quả địa cầu

  private menuOpen: boolean = false;
  private menuItems: MenuItem[] = [];
  private menuRects: Rect[] = [];
  private menuBox: Rect = new Rect(0, 0, 0, 0);
  private menuHighlight: number = -1;
  private menuPointer: number = -1;

  private openMenu(globe: Key, pointer: number): void {
    let items: MenuItem[] = [];
    if (!this.lockedValue) {
      items.push(new MenuItem(Row.HEADER, -1, 'INPUT LANGUAGE'));
      items.push(new MenuItem(Row.ITEM, PICK_VIEN, 'Tiếng Việt · English', 'Telex · detects English as you type', !this.chineseValue));
      items.push(new MenuItem(Row.ITEM, PICK_CHINESE, '中文 · 拼音', 'Full pinyin, initials, fuzzy pinyin', this.chineseValue));
      items.push(new MenuItem(Row.DIVIDER));
      items.push(new MenuItem(Row.SWITCH, PICK_TRADITIONAL, 'Traditional (繁體)', '', this.traditional));
    }
    items.push(new MenuItem(Row.ACTION, PICK_OTHER_KEYBOARD, 'Next keyboard', '', false, Icons.keyboard));
    items.push(new MenuItem(Row.ACTION, PICK_SETTINGS, 'ViPi Settings', '', false, Icons.sliders));
    const pad = 8;
    let bottom = globe.y - 14; // trên hàng dưới cùng: thả tay tại phím quả địa cầu không chọn nhầm
    const heightsOf = (list: MenuItem[], compact: boolean): number[] => list.map((it: MenuItem) => {
      switch (it.row) {
        case Row.HEADER:
          return 30;
        case Row.ITEM:
          return compact ? 48 : 56;
        case Row.DIVIDER:
          return compact ? 9 : 17;
        default:
          return compact ? 40 : 48;
      }
    });
    const sum = (hs: number[]): number => hs.reduce((a: number, b: number) => a + b, 0);
    let heights = heightsOf(items, false);
    // không đủ chỗ phía trên: bỏ tiêu đề, thu gọn các dòng
    if (sum(heights) + 2 * pad > bottom - 2) {
      items = items.filter((it: MenuItem) => it.row !== Row.HEADER);
      heights = heightsOf(items, true);
    }
    this.menuItems = items;
    const h = sum(heights) + 2 * pad;
    const w = Math.min(292, this.blockR - this.blockL - 16);
    let left = this.blockL + 8;
    if (h > bottom - 2) {
      // vẫn không vừa: đặt bên phải phím quả địa cầu, đáy ngang đáy phím
      left = Math.min(globe.x + globe.w + 8, this.blockR - w);
      bottom = globe.y + globe.h;
    }
    const top = Math.max(2, bottom - h);
    this.menuBox = new Rect(left, top, left + w, top + h);
    this.menuRects = [];
    let y = top + pad;
    for (const rh of heights) {
      this.menuRects.push(new Rect(left, y, left + w, y + rh));
      y += rh;
    }
    this.menuHighlight = -1;
    this.menuPointer = pointer;
    this.menuOpen = true;
    this.listener.redraw(false);
  }

  private closeMenu(): void {
    if (!this.menuOpen) {
      return;
    }
    this.menuOpen = false;
    this.menuHighlight = -1;
    this.menuPointer = -1;
    this.listener.redraw(false);
  }

  private menuItemAt(x: number, y: number): number {
    const i = this.menuRects.findIndex((r: Rect) => r.contains(x, y));
    return i >= 0 && this.menuItems[i].choice >= 0 ? i : -1;
  }

  private drawMenu(ctx: CanvasRenderingContext2D): void {
    const p = this.palette;
    const b = this.menuBox;
    ctx.save();
    ctx.shadowBlur = 10;
    ctx.shadowOffsetY = 4;
    ctx.shadowColor = 'rgba(0,0,0,0.25)';
    this.roundRect(ctx, b.l, b.t, b.r - b.l, b.b - b.t, 12, css(p.menu));
    ctx.restore();
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(b.l, b.t, b.r - b.l, b.b - b.t, 12);
    ctx.clip();
    for (let i = 0; i < this.menuItems.length; i++) {
      const item = this.menuItems[i];
      const row = this.menuRects[i];
      const cy = (row.t + row.b) / 2;
      const x = row.l + 52;
      if (item.row === Row.HEADER) {
        ctx.font = this.font(11, '500');
        ctx.textAlign = 'left';
        ctx.textBaseline = 'top';
        ctx.fillStyle = css(p.hint);
        ctx.fillText(item.title, row.l + 16, row.t + 8);
        continue;
      }
      if (item.row === Row.DIVIDER) {
        ctx.fillStyle = css(p.divider);
        ctx.fillRect(row.l, cy - 0.5, row.r - row.l, 1);
        continue;
      }
      const on = item.row === Row.ITEM && item.checked;
      if (on) {
        ctx.fillStyle = css(p.container);
        ctx.fillRect(row.l, row.t, row.r - row.l, row.b - row.t);
      }
      if (i === this.menuHighlight) {
        ctx.fillStyle = css(p.text, 0x14 / 255);
        ctx.fillRect(row.l, row.t, row.r - row.l, row.b - row.t);
      }
      const fg = on ? p.onContainer : p.text;
      if (on) {
        this.drawIcon(ctx, Icons.check, row.l + 27, cy, 22, fg);
      }
      if (item.icon !== null) {
        this.drawIcon(ctx, item.icon, row.l + 27, cy, 22, p.icon);
      }
      if (item.subtitle.length === 0) {
        this.text(ctx, item.title, x, cy, 15, fg, item.row === Row.ITEM ? '500' : 'normal', 'left');
      } else {
        this.text(ctx, item.title, x, cy - 9, 15, fg, '500', 'left');
        this.text(ctx, item.subtitle, x, cy + 11, 12, on ? p.onContainer : p.hint, 'normal', 'left', on ? 0.8 : 1);
      }
      if (item.row === Row.SWITCH) {
        this.drawSwitch(ctx, row.r - 16 - 52, cy, item.checked);
      }
    }
    ctx.restore();
  }

  /** Switch Material 3, 52 × 32. */
  private drawSwitch(ctx: CanvasRenderingContext2D, left: number, cy: number, on: boolean): void {
    const p = this.palette;
    if (on) {
      this.roundRect(ctx, left, cy - 16, 52, 32, 16, css(p.primary));
      ctx.fillStyle = css(p.onPrimary);
      ctx.beginPath();
      ctx.arc(left + 36, cy, 12, 0, Math.PI * 2);
      ctx.fill();
    } else {
      this.roundRect(ctx, left, cy - 16, 52, 32, 16, css(p.bg));
      ctx.strokeStyle = css(p.outline);
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.roundRect(left + 1, cy - 15, 50, 30, 15);
      ctx.stroke();
      ctx.fillStyle = css(p.outline);
      ctx.beginPath();
      ctx.arc(left + 16, cy, 8, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  /** Bàn phím ẩn đi: đóng lưới ứng viên và menu, bỏ các ngón đang chạm. */
  reset(): void {
    this.setGridOpen(false);
    this.touchCancel();
  }
}
