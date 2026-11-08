import './mocks/globals';
import { handlers } from './mocks/ime';
import { keyboardController } from '../entry/src/main/ets/ime/KeyboardController';
import { KeyInput, KeyKind } from '../entry/src/main/ets/common/Engine';
import { PICK_TOGGLE, Shift } from '../entry/src/main/ets/ime/Board';

/** Ô nhập giả theo đúng mô tả API: chữ tạm (preview) là một đoạn trong văn bản, finish thì thành chữ thật. */
class Client {
  text = '';
  cursor = 0;
  preview: [number, number] | null = null;
  actions: string[] = [];
  constructor(public attr: any) {}
  getEditorAttributeSync() { return this.attr; }
  insertTextSync(t: string) {
    if (this.preview) throw new Error('insertText while preview is active');
    this.text = this.text.slice(0, this.cursor) + t + this.text.slice(this.cursor);
    this.cursor += t.length;
  }
  deleteForwardSync(n: number) {
    if (this.preview) throw new Error('deleteForward while preview is active');
    const s = Math.max(0, this.cursor - n);
    this.text = this.text.slice(0, s) + this.text.slice(this.cursor);
    this.cursor = s;
  }
  getForwardSync(n: number) { return this.text.slice(Math.max(0, this.cursor - n), this.cursor); }
  setPreviewTextSync(t: string, r: { start: number; end: number }) {
    if (!this.attr.isTextPreviewSupported) { const e: any = new Error('no preview'); e.code = 12800011; throw e; }
    if (r.start !== -1) throw new Error('only whole-preview replace is used');
    const [s, e] = this.preview ?? [this.cursor, this.cursor];
    this.text = this.text.slice(0, s) + t + this.text.slice(e);
    this.preview = [s, s + t.length];
    this.cursor = s + t.length;
  }
  finishTextPreviewSync() { this.preview = null; }
  moveCursorSync(d: number) { this.cursor = Math.max(0, Math.min(this.text.length, this.cursor + (d === 4 ? 1 : d === 3 ? -1 : 0))); }
  sendKeyFunction(a: number) { this.actions.push('fn' + a); return Promise.resolve(true); }
  sendExtendAction(a: number) { this.actions.push('ext' + a); return Promise.resolve(); }
  get shown() { return this.preview ? this.text.slice(0, this.preview[0]) + '[' + this.text.slice(this.preview[0], this.preview[1]) + ']' + this.text.slice(this.preview[1]) : this.text; }
}

const ctx: any = {
  filesDir: process.env.FILES_DIR, config: { colorMode: 1 }, applicationInfo: { name: 'dev.t43.vipi' },
  getApplicationContext: () => ({ on: () => 1, off: () => {} }), startAbility: async () => {},
};
keyboardController.onCreate(ctx);

let fails = 0;
function start(attr: any): Client {
  const c = new Client({ inputPattern: 0, enterKeyType: 0, isTextPreviewSupported: false, ...attr });
  handlers['inputStart']({ hide: async () => {} }, c);
  return c;
}
function type(s: string) {
  for (const ch of s) {
    if (ch === ' ') keyboardController.onKey(new KeyInput(KeyKind.SPACE));
    else if (ch === '⌫') keyboardController.onKey(new KeyInput(KeyKind.BACKSPACE));
    else if (ch === '⏎') keyboardController.onKey(new KeyInput(KeyKind.ENTER));
    else keyboardController.onKey(KeyInput.char(ch));
  }
}
function expect(name: string, got: string, want: string) {
  const ok = got === want;
  if (!ok) fails++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}: ${JSON.stringify(got)}${ok ? '' : ' want ' + JSON.stringify(want)}`);
}
function mode(): number { return (keyboardController as any).last.mode; }
function toVietnamese() { if (mode() === 1) keyboardController.onPickInput(PICK_TOGGLE); }
function toChinese() { if (mode() !== 1) keyboardController.onPickInput(PICK_TOGGLE); }

let c = start({});
type('treen ');
expect('auto switch EN→VI on word end', c.text, 'trên ');
type('server ');
expect('English word in VI mode goes back to English', c.text, 'trên server ');
c = start({});
type('treen ');
type('⌫');
expect('backspace right after auto switch restores keys', c.text, 'treen');
c = start({});
type('Vieejt Nam ');
expect('Telex with capital and tone', c.text, 'Việt Nam ');
c = start({});
type('ok  ');
expect('double space period', c.text, 'ok. ');
expect('auto-cap after sentence', String(keyboardController.board.shift), String(Shift.ONCE));
c = start({ inputPattern: 7 });
type('vieejt');
expect('password field passes keys through', c.text, 'vieejt');
c = start({ enterKeyType: 3 });
type('a⏎');
expect('enter on search field sends the action', c.actions.join(','), 'fn3');
c = start({});
toVietnamese();
type('dduowngf');
keyboardController.onSuggestion(0);
expect('suggestion 0 keeps typed keys', c.text, 'dduowngf ');
c = start({});
toVietnamese();
type('dduowngf');
expect('Vietnamese word shown while typing', c.text, 'đường');
type('⌫⌫');
expect('backspace inside a Vietnamese word', c.text, 'đườ');

toChinese();
c = start({ isTextPreviewSupported: true });
type('nihao');
expect('pinyin preview in the field', c.shown, "[ni hao]");
type(' ');
expect('space picks the first candidate', c.shown, '你好');
type('nihao,');
expect('comma commits then full-width comma', c.shown, '你好你好，');
type('women');
keyboardController.onCandidate(0);
expect('tap candidate replaces preview', c.shown, '你好你好，我们');
type('ni');
type('⌫⌫');
expect('backspace clears the whole preview', c.shown, '你好你好，我们');
c = start({ isTextPreviewSupported: false });
type('nihao');
expect('no preview support: field untouched while composing', c.text, '');
expect('no preview support: preedit in the bar', (keyboardController.board as any).preedit, 'ni hao');
type(' ');
expect('no preview support: commit inserts', c.text, '你好');
toVietnamese();
c = start({});
type('vieejt');
expect('back to VI·EN from Chinese', c.text, 'việt');

// --- chạm trên Board (toạ độ vp) ---
const board: any = keyboardController.board;
board.resize(392, 278, 870);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
function keyAt(label: string): any {
  for (const row of board.rows) for (const k of row) if ((k.kind === 0 ? k.label : 'k' + k.kind) === label) return k;
  throw new Error('no key ' + label);
}
function tap(label: string, id = 1) { const k = keyAt(label); board.touchDown(id, k.x + k.w / 2, k.y + k.h / 2); board.touchUp(id, k.x + k.w / 2, k.y + k.h / 2); }
(async () => {
  toVietnamese();
  c = start({});
  board.shift = Shift.OFF;
  for (const ch of 'hello') tap(ch);
  expect('tapping keys types', c.text, 'hello');
  const h = keyAt('h'), i = keyAt('i');
  board.touchDown(1, h.x + 5, h.y + 5); board.touchDown(2, i.x + 5, i.y + 5); board.touchUp(1, h.x + 5, h.y + 5); board.touchUp(2, i.x + 5, i.y + 5);
  expect('second finger fires the first key (rollover)', c.text, 'hellohi');
  const q = keyAt('q');
  board.touchDown(3, q.x + 5, q.y + 5); await sleep(450); board.touchUp(3, q.x + 5, q.y + 5);
  expect('hold top-row key types its number', c.text, 'hellohi1');
  const bs = keyAt('k2');
  board.touchDown(4, bs.x + 5, bs.y + 5); board.touchUp(4, bs.x + 5, bs.y + 5);
  expect('backspace key', c.text, 'hellohi');
  const sh = keyAt('k1');
  board.touchDown(5, sh.x + 5, sh.y + 5); board.touchUp(5, sh.x + 5, sh.y + 5);
  tap('x');
  expect('shift once then a capital', c.text, 'hellohiX');
  expect('shift released after one letter', String(board.shift), String(Shift.OFF));
  const sp = keyAt('k7');
  board.touchDown(6, sp.x + sp.w / 2, sp.y + 5); for (let d = 2; d <= 50; d += 2) board.touchMove(6, sp.x + sp.w / 2 - d, sp.y + 5); board.touchUp(6, sp.x + sp.w / 2 - 50, sp.y + 5);
  expect('drag on space moves the cursor left', String(c.cursor), String(c.text.length - 3));
  const globe = keyAt('k6');
  board.touchDown(7, globe.x + 5, globe.y + 5); board.touchUp(7, globe.x + 5, globe.y + 5);
  expect('tap globe switches to Chinese', String(mode()), '1');
  board.touchDown(8, globe.x + 5, globe.y + 5); await sleep(350);
  expect('hold globe opens the menu', String(board.menuOpen), 'true');
  const idx = board.menuItems.findIndex((m: any) => m.title === 'Tiếng Việt · English');
  const r = board.menuRects[idx];
  board.touchMove(8, r.l + 20, (r.t + r.b) / 2); board.touchUp(8, r.l + 20, (r.t + r.b) / 2);
  expect('slide to a menu item picks it', String(mode() !== 1) + String(board.menuOpen), 'truefalse');
  board.layout = 0;
  tap('k3');
  expect('?123 opens numbers', String(board.layout), '1');
  tap('1'); tap('k7');
  expect('space returns to letters', String(board.layout) + c.text.slice(c.cursor - 2, c.cursor), '01 ');
  // Pura X Max mở ra (~795 × 562 vp): tách đôi; gập lại (~389 × 569 vp): bàn phím điện thoại, chữ đang gõ giữ nguyên
  const { Board: B } = require('../entry/src/main/ets/ime/Board');
  expect('inner screen height (vp)', String(B.heightFor(795, 562, true)), '244');
  expect('cover screen height (vp)', String(B.heightFor(389, 569, true)), '244');
  expect('normal phone height (vp)', String(B.heightFor(389, 860, true)), '278');
  toVietnamese();
  c = start({});
  type('vie');
  board.resize(795, 244, 562);
  expect('unfolded: split layout', String(board.split), 'true');
  const t2 = keyAt('t'), y2 = keyAt('y');
  expect('t and y on each side of the hinge', String(t2.x + t2.w < board.splitGapL + 0.01 && y2.x > board.splitGapR - 0.01), 'true');
  expect('tap over the hinge is not a key', String(board.hit((board.splitGapL + board.splitGapR) / 2, t2.y + 5)), 'null');
  tap('e'); tap('j'); tap('t');
  expect('typing across the fold keeps the word', c.text, 'việt');
  board.resize(389, 244, 569);
  expect('folded: phone layout', String(board.split), 'false');
  tap('k7');
  expect('space after folding', c.text, 'việt ');
  board.largeSplit = false;
  board.resize(795, 244, 562);
  expect('Wide setting: one block on the inner screen', String(board.split), 'false');
  board.largeSplit = true;
  console.log(fails === 0 ? 'ALL PASS' : `${fails} FAILED`);
  process.exit(fails === 0 ? 0 : 1);
})();
