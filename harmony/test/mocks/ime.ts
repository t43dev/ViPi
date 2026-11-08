type Fn = (...a: any[]) => any;
export const handlers: Record<string, Fn> = {};
const ability = {
  on: (t: string, f: Fn) => { handlers[t] = f; },
  off: (t: string) => { delete handlers[t]; },
  createPanel: async () => ({ resize: async () => {}, setUiContent: async () => {}, on: () => {} }),
  destroyPanel: async () => {},
};
const delegate = {
  on: (t: string, f: Fn) => { handlers['kd:' + t] = f; },
  off: (t: string) => { delete handlers['kd:' + t]; },
};
export const inputMethodEngine = {
  PATTERN_NULL: -1, PATTERN_TEXT: 0, PATTERN_NUMBER: 2, PATTERN_PHONE: 3, PATTERN_DATETIME: 4, PATTERN_EMAIL: 5,
  PATTERN_URI: 6, PATTERN_PASSWORD: 7, PATTERN_PASSWORD_NUMBER: 8, PATTERN_PASSWORD_SCREEN_LOCK: 9,
  PATTERN_USER_NAME: 10, PATTERN_NEW_PASSWORD: 11, PATTERN_NUMBER_DECIMAL: 12, PATTERN_ONE_TIME_CODE: 13,
  Direction: { CURSOR_UP: 1, CURSOR_DOWN: 2, CURSOR_LEFT: 3, CURSOR_RIGHT: 4 },
  ExtendAction: { SELECT_ALL: 0, CUT: 3, COPY: 4, PASTE: 5 },
  PanelType: { SOFT_KEYBOARD: 0, STATUS_BAR: 1 },
  PanelFlag: { FLG_FIXED: 0, FLG_FLOATING: 1 },
  getInputMethodAbility: () => ability,
  getKeyboardDelegate: () => delegate,
};
export const inputMethod = {
  getSetting: () => ({ getInputMethodsSync: () => [], getInputMethodState: async () => 2 }),
  getCurrentInputMethod: () => ({ name: 'dev.t43.vipi' }),
  switchInputMethod: async () => true,
  EnabledState: { DISABLED: 0, BASIC_MODE: 1, FULL_EXPERIENCE_MODE: 2 },
};
export class InputMethodExtensionAbility {}
export type InputMethodExtensionContext = any;
