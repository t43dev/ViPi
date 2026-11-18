import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Mode, logError, DATA_GROUP } from './Engine';

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
  /** Lúc màn hình cài đặt bấm xoá từ đã học: bàn phím xoá file của nó nếu file cũ hơn mốc này. */
  learnedClearedAt: number = 0;
  /** Đã đồng ý chính sách quyền riêng tư (hộp thoại lần mở đầu tiên). */
  privacyAccepted: boolean = false;
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
export const PRIVACY_ACCEPTED = 'privacyAccepted';
const MODE = 'mode';
const LATIN = 'latin';
const NAME = 'vipi';
/** Chế độ đang dùng: chỉ tiến trình bàn phím ghi (ghi cả khi đang gõ, lúc tự đổi Anh/Việt). */
const STATE = 'vipi-state';

/**
 * Bàn phím (InputMethodExtensionAbility) chạy trong sandbox riêng, không thấy thư mục dữ liệu của app: cài đặt
 * phải nằm trong nhóm dữ liệu chung (data-group-ids trong profile ký app, dataGroupIds trong module.json5).
 * Ở chế độ cơ bản bàn phím chỉ đọc được nhóm này, nên thứ bàn phím tự ghi (chế độ gõ) để trong sandbox riêng.
 * Profile chưa có nhóm thì getPreferences báo 15501002: dùng thư mục riêng như cũ để app vẫn chạy.
 */
let useGroup = true;

function options(name: string): preferences.Options {
  return useGroup ? { name: name, dataGroupId: DATA_GROUP } as preferences.Options : { name: name } as preferences.Options;
}

function open(ctx: common.Context, name: string): preferences.Preferences {
  if (useGroup) {
    try {
      return preferences.getPreferencesSync(ctx, options(name));
    } catch (e) {
      logError(`data group ${DATA_GROUP} unavailable: ${JSON.stringify(e)}`);
      useGroup = false;
    }
  }
  return preferences.getPreferencesSync(ctx, options(name));
}

function uncache(ctx: common.Context, name: string): void {
  try {
    preferences.removePreferencesFromCacheSync(ctx, options(name));
  } catch (e) {
    logError(`cannot reload ${name}: ${JSON.stringify(e)}`);
  }
}

function store(ctx: common.Context): preferences.Preferences {
  return open(ctx, NAME);
}

function state(ctx: common.Context): preferences.Preferences {
  return preferences.getPreferencesSync(ctx, { name: STATE } as preferences.Options);
}

/**
 * Ghi một cài đặt. Preferences không dùng chung được giữa hai tiến trình: flush ghi cả bản đệm của tiến trình
 * này đè lên file, nên bản đệm cũ sẽ xoá mất thay đổi bên kia vừa ghi. Vì vậy đọc lại file trước khi sửa, và
 * ghi xong mới trả về (bên kia, hoặc chính mình, đọc lại ngay sau đó là thấy).
 */
function write(ctx: common.Context, key: string, value: preferences.ValueType): void {
  try {
    uncache(ctx, NAME);
    const p = store(ctx);
    p.putSync(key, value);
    p.flushSync();
  } catch (e) {
    logError(`cannot save ${key}: ${JSON.stringify(e)}`);
  }
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
    uncache(ctx, NAME);
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
  // bản cũ để chế độ chung file cài đặt: lần đầu sau khi cập nhật lấy lại từ đó
  const st = state(ctx);
  s.mode = num(st, MODE, num(p, MODE, Mode.ENGLISH)) as Mode;
  s.latin = num(st, LATIN, num(p, LATIN, Mode.ENGLISH)) as Mode;
  s.learnedClearedAt = num(p, LEARNED_CLEARED_AT, 0);
  s.privacyAccepted = bool(p, PRIVACY_ACCEPTED, false);
  return s;
}

export function saveBool(ctx: common.Context, key: string, value: boolean): void {
  write(ctx, key, value);
}

export function saveString(ctx: common.Context, key: string, value: string): void {
  write(ctx, key, value);
}

export function saveStrings(ctx: common.Context, key: string, value: string[]): void {
  write(ctx, key, value);
}

export function saveNumber(ctx: common.Context, key: string, value: number): void {
  write(ctx, key, value);
}

export function saveMode(ctx: common.Context, mode: Mode): void {
  try {
    const p = state(ctx);
    p.putSync(MODE, mode);
    if (mode !== Mode.CHINESE) {
      p.putSync(LATIN, mode);
    }
    p.flush().catch(() => {
    });
  } catch (e) {
    logError(`cannot save the mode: ${JSON.stringify(e)}`);
  }
}

/** Giao diện sáng/tối cho màn hình cài đặt (bàn phím tự áp ở tiến trình của nó). */
export function applyAppTheme(ctx: common.Context, theme: string): void {
  const mode = theme === 'DARK' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
    theme === 'LIGHT' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  try {
    ctx.getApplicationContext().setColorMode(mode);
  } catch (e) {
    logError(`cannot set the color mode: ${JSON.stringify(e)}`);
  }
}
