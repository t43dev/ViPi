import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Mode } from './Engine';

/** Cài đặt người dùng (Preferences "vipi"), cùng khoá với bản Android. */
export class Settings {
  modernTone: boolean = false;
  spellCheck: boolean = true;
  restore: boolean = true;
  traditional: boolean = false;
  learn: boolean = true;
  fullWidth: boolean = true;
  haptics: boolean = true;
  autoCap: boolean = true;
  doubleSpace: boolean = true;
  keyPopup: boolean = true;
  /** 'SYSTEM' | 'LIGHT' | 'DARK' */
  theme: string = 'SYSTEM';
  /** Màn lớn (máy gập mở, tablet): 'SPLIT' tách đôi hai bên bản lề, 'WIDE' một khối ở giữa. */
  largeLayout: string = 'SPLIT';
  fuzzy: string[] = [];
  /** Chế độ đang dùng; lần đầu là tiếng Anh, tự nhận diện sẽ sang tiếng Việt khi gõ chữ Việt. */
  mode: Mode = Mode.ENGLISH;
  /** Việt hay Anh lần cuối, để quay lại từ tiếng Trung. */
  latin: Mode = Mode.ENGLISH;
  /** Lúc màn hình cài đặt xoá từ đã học (bàn phím ở tiến trình khác thì đọc lại file). */
  learnedClearedAt: number = 0;
}

export const MODERN_TONE = 'modernTone';
export const SPELL_CHECK = 'spellCheck';
export const RESTORE = 'restoreNonVietnamese';
export const TRADITIONAL = 'traditional';
export const LEARN = 'learnWords';
export const FULL_WIDTH = 'fullWidthPunctuation';
export const HAPTICS = 'haptics';
export const AUTO_CAP = 'autoCapitalize';
export const DOUBLE_SPACE = 'doubleSpacePeriod';
export const KEY_POPUP = 'keyPopup';
export const THEME = 'theme';
export const LARGE_LAYOUT = 'largeLayout';
export const FUZZY = 'fuzzy';
export const LEARNED_CLEARED_AT = 'learnedClearedAt';
const MODE = 'mode';
const LATIN = 'latin';
const NAME = 'vipi';

function store(ctx: common.Context): preferences.Preferences {
  return preferences.getPreferencesSync(ctx, { name: NAME } as preferences.Options);
}

function bool(p: preferences.Preferences, key: string, fallback: boolean): boolean {
  const v = p.getSync(key, fallback);
  return typeof v === 'boolean' ? v : fallback;
}

function num(p: preferences.Preferences, key: string, fallback: number): number {
  const v = p.getSync(key, fallback);
  return typeof v === 'number' ? v : fallback;
}

/**
 * Đọc cài đặt. Bàn phím và màn hình cài đặt là hai tiến trình, mỗi bên giữ bản đệm riêng:
 * `fresh` bỏ bản đệm để thấy thay đổi bên kia vừa ghi.
 */
export function loadSettings(ctx: common.Context, fresh: boolean): Settings {
  if (fresh) {
    preferences.removePreferencesFromCacheSync(ctx, { name: NAME } as preferences.Options);
  }
  const p = store(ctx);
  const s = new Settings();
  s.modernTone = bool(p, MODERN_TONE, s.modernTone);
  s.spellCheck = bool(p, SPELL_CHECK, s.spellCheck);
  s.restore = bool(p, RESTORE, s.restore);
  s.traditional = bool(p, TRADITIONAL, s.traditional);
  s.learn = bool(p, LEARN, s.learn);
  s.fullWidth = bool(p, FULL_WIDTH, s.fullWidth);
  s.haptics = bool(p, HAPTICS, s.haptics);
  s.autoCap = bool(p, AUTO_CAP, s.autoCap);
  s.doubleSpace = bool(p, DOUBLE_SPACE, s.doubleSpace);
  s.keyPopup = bool(p, KEY_POPUP, s.keyPopup);
  const theme = p.getSync(THEME, s.theme);
  s.theme = typeof theme === 'string' ? theme : s.theme;
  const large = p.getSync(LARGE_LAYOUT, s.largeLayout);
  s.largeLayout = large === 'WIDE' ? 'WIDE' : 'SPLIT';
  const fuzzy = p.getSync(FUZZY, [] as string[]);
  s.fuzzy = Array.isArray(fuzzy) ? (fuzzy as string[]) : [];
  s.mode = num(p, MODE, Mode.ENGLISH) as Mode;
  s.latin = num(p, LATIN, Mode.ENGLISH) as Mode;
  s.learnedClearedAt = num(p, LEARNED_CLEARED_AT, 0);
  return s;
}

export function saveBool(ctx: common.Context, key: string, value: boolean): void {
  const p = store(ctx);
  p.putSync(key, value);
  p.flush();
}

export function saveString(ctx: common.Context, key: string, value: string): void {
  const p = store(ctx);
  p.putSync(key, value);
  p.flush();
}

export function saveStrings(ctx: common.Context, key: string, value: string[]): void {
  const p = store(ctx);
  p.putSync(key, value);
  p.flush();
}

export function saveNumber(ctx: common.Context, key: string, value: number): void {
  const p = store(ctx);
  p.putSync(key, value);
  p.flush();
}

export function saveMode(ctx: common.Context, mode: Mode): void {
  const p = store(ctx);
  p.putSync(MODE, mode);
  if (mode !== Mode.CHINESE) {
    p.putSync(LATIN, mode);
  }
  p.flush();
}
