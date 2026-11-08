// libvipi.so: lõi ViPi (Rust) qua NAPI, xem harmony/native/src/lib.rs. Tên hàm/trường là camelCase của bản Rust.

/** Việc phải làm sau một phím, cùng trạng thái mới của lõi. */
export interface Outcome {
  /** false: phím đi thẳng tới ô nhập như bàn phím thường. */
  handled: boolean;
  /** Có edit: xoá `backspaces` ký tự trước con trỏ rồi chèn `insert`. */
  hasEdit: boolean;
  backspaces: number;
  insert: string;
  wholeWord: boolean;
  /** Sau edit, gửi lại phím gốc. */
  repostKey: boolean;
  /** Chế độ mới nếu tự đổi Anh/Việt vừa đổi, -1 nếu không. */
  switchedTo: number;
  /** 0 Việt, 1 Trung, 2 Anh. */
  mode: number;
  word: string;
  keys: string;
  preedit: string;
  composingChinese: boolean;
  candidates: string[];
}

export interface FuzzyOption {
  id: string;
  label: string;
}

/** Nạp dữ liệu; "" nếu được, hoặc lời báo lỗi. */
export const open: (dir: string) => string;
export const isOpen: () => boolean;
export const handleKey: (kind: number, text: string) => Outcome;
export const selectCandidate: (index: number) => Outcome;
export const state: () => Outcome;
export const cancel: () => void;
export const setMode: (mode: number) => void;
export const pauseAutoSwitch: () => void;
export const configure: (modernTone: boolean, spellCheck: boolean, restore: boolean, fullWidth: boolean,
  traditional: boolean, learn: boolean, learnFile: string, fuzzy: string[]) => void;
export const clearLearned: () => void;
export const learnedCount: () => number;
export const fuzzyOptions: () => FuzzyOption[];
