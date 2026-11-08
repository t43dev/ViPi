/** Màu bàn phím, cùng giá trị với bản Android (vipi-android-ui-spec.md, mục 3.1). Màu dạng 0xAARRGGBB. */
export class Palette {
  bg: number = 0;
  key: number = 0;
  fn: number = 0;
  text: number = 0;
  hint: number = 0;
  icon: number = 0;
  primary: number = 0;
  onPrimary: number = 0;
  container: number = 0;
  onContainer: number = 0;
  divider: number = 0;
  shadow: number = 0;
  menu: number = 0;
  popup: number = 0;
  faint: number = 0;
  outline: number = 0;
}

export function makePalette(dark: boolean): Palette {
  const p = new Palette();
  p.primary = dark ? 0xFFFFB4AB : 0xFFA8221C;
  p.onPrimary = dark ? 0xFF690005 : 0xFFFFFFFF;
  p.container = dark ? 0xFF93000A : 0xFFFFDAD6;
  p.onContainer = dark ? 0xFFFFDAD6 : 0xFF410002;
  if (dark) {
    p.bg = 0xFF202024;
    p.key = 0xFF3A3A3F;
    p.fn = 0xFF2B2B30;
    p.text = 0xFFE6E1E5;
    p.hint = 0xFFAEAAAE;
    p.icon = 0xFFCAC4D0;
    p.divider = 0xFF48464C;
    p.shadow = 0x66000000;
    p.menu = 0xFF2B2930;
    p.popup = 0xFF4A4A50;
    p.faint = 0xFF938F99;
    p.outline = 0xFF938F99;
  } else {
    p.bg = 0xFFE9E8EC;
    p.key = 0xFFFFFFFF;
    p.fn = 0xFFD4D5DA;
    p.text = 0xFF1C1B1F;
    p.hint = 0xFF5F5E62;
    p.icon = 0xFF44464E;
    p.divider = 0xFFC9C7CC;
    p.shadow = 0x24000000;
    p.menu = 0xFFFFFFFF;
    p.popup = 0xFFFFFFFF;
    p.faint = 0xFF8E8E93;
    p.outline = 0xFF79767D;
  }
  return p;
}

/** Màu 0xAARRGGBB thành chuỗi rgba() cho Canvas; `alpha` nhân thêm vào độ đục sẵn có. */
export function css(argb: number, alpha: number = 1): string {
  const a = Math.floor(argb / 0x1000000) & 0xFF;
  const r = Math.floor(argb / 0x10000) & 0xFF;
  const g = Math.floor(argb / 0x100) & 0xFF;
  const b = argb & 0xFF;
  const o = Math.max(0, Math.min(1, (a / 255) * alpha));
  return `rgba(${r},${g},${b},${o.toFixed(3)})`;
}
