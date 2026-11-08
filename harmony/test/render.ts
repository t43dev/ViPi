// Vẽ bàn phím bằng đúng mã Board.ets lên canvas của Node (Skia) để xem bố cục, màu, chữ: test/out/*.png.
// Chỉ gần đúng: phông chữ của máy Linux thay cho HarmonyOS Sans, đơn vị vp đổi thành px nhân `SCALE`.
import './mocks/skia-globals';
import { createCanvas } from '@napi-rs/canvas';
import * as fs from 'fs';
import { Board, BoardListener, Layout, Shift } from '../entry/src/main/ets/ime/Board';
import { KeyInput } from '../entry/src/main/ets/common/Engine';

const SCALE = 3;
const FAMILY = '"DejaVu Sans", "WenQuanYi Zen Hei", sans-serif';

/** Canvas của Node hiểu px, không hiểu vp: đổi chuỗi font, còn lại giữ nguyên. */
function arkCtx(ctx: any): any {
  return new Proxy(ctx, {
    get(t, k) {
      const v = t[k];
      return typeof v === 'function' ? v.bind(t) : v;
    },
    set(t, k, v) {
      if (k === 'font') {
        v = String(v).replace(/(\d+(?:\.\d+)?)vp/, '$1px').replace('sans-serif', FAMILY);
      }
      t[k] = v;
      return true;
    },
  });
}

const listener: BoardListener = {
  onKey: (_k: KeyInput) => {}, onPickInput: () => {}, onCandidate: () => {}, onSuggestion: () => {},
  onCursor: () => {}, onPaste: () => {}, feedback: () => {}, redraw: () => {},
};

// Pura X Max: màn ngoài ~389 × 569 vp, màn trong mở ~795 × 562 vp (1264 × 1848 và 2584 × 1828 px, mật độ ~3.25)
function render(name: string, setup: (b: any) => void, dark = false, W = 389, SH = 569) {
  const H = Board.heightFor(W, SH, true);
  const b: any = new Board(listener);
  b.setDark(dark);
  // hai lớp như trên máy: lớp phím tĩnh và lớp trên (trong suốt), chồng lên nhau
  const canvas = createCanvas(W * SCALE, H * SCALE);
  const top = createCanvas(W * SCALE, H * SCALE);
  const raw = canvas.getContext('2d');
  const rawTop = top.getContext('2d');
  raw.scale(SCALE, SCALE);
  rawTop.scale(SCALE, SCALE);
  const ctx = arkCtx(raw);
  const ctxTop = arkCtx(rawTop);
  b.setMeasurer(ctxTop);
  b.resize(W, H, SH);
  setup(b);
  b.drawStatic(ctx);
  b.drawDynamic(ctxTop);
  raw.setTransform(1, 0, 0, 1, 0, 0);
  raw.drawImage(top, 0, 0);
  fs.writeFileSync(`${__dirname}/${name}.png`, canvas.toBuffer('image/png'));
  console.log(`out/${name}.png`);
}

function keyAt(b: any, label: string): any {
  for (const row of b.rows) for (const k of row) if ((k.kind === 0 ? k.label : 'k' + k.kind) === label) return k;
  throw new Error(label);
}

render('letters-light', (b) => {
  b.setSuggestions('vieetj', 'việt');
  b.shift = Shift.ONCE;
  const k = keyAt(b, 'e');
  b.touchDown(1, k.x + 5, k.y + 5);
});
render('chinese-dark', (b) => {
  b.chinese = true;
  b.setCandidates(['你好', '拟好', '你', '尼', '泥', '腻', '逆', '妮', '倪', '霓'], 'ni hao');
}, true);
render('globe-menu-light', (b) => {
  const g = keyAt(b, 'k6');
  b.openMenu(g, 1);
  b.menuHighlight = 2;
});
render('numbers-dark', (b) => {
  b.layout = Layout.NUMBERS;
  b.action = 3;
}, true);
render('candidate-grid-light', (b) => {
  b.chinese = true;
  b.setCandidates(['是', '时', '事', '市', '世', '式', '使', '十', '石', '实', '试', '室', '视', '食', '师', '诗', '识', '史'], '');
  b.setGridOpen(true);
});

render('pura-x-max-inner-split-light', (b) => {
  b.setSuggestions('nguwowif', 'người');
}, false, 795, 562);
render('pura-x-max-inner-split-chinese-dark', (b) => {
  b.chinese = true;
  b.setCandidates(['你好', '拟好', '你', '尼', '泥', '腻', '逆', '妮', '倪', '霓', '拟', '溺'], '');
}, true, 795, 562);
render('pura-x-max-inner-numbers-dark', (b) => {
  b.layout = Layout.NUMBERS;
}, true, 795, 562);
render('pura-x-max-inner-globe-menu-light', (b) => {
  b.openMenu(keyAt(b, 'k6'), 1);
}, false, 795, 562);
