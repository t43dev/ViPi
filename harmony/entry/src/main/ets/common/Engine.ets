import vipi from 'libvipi.so';
import { Outcome } from 'libvipi.so';
import { common, bundleManager } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** Mã phím gửi sang lõi (khớp `key_from` trong harmony/native/src/lib.rs). */
export enum KeyKind {
  TEXT = 0,
  SPACE = 1,
  ENTER = 2,
  TAB = 3,
  BACKSPACE = 4,
  ESCAPE = 5,
  LEFT = 6,
  RIGHT = 7,
  UP = 8,
  DOWN = 9,
  PAGE_UP = 10,
  PAGE_DOWN = 11,
  OTHER = 12
}

/** Chế độ của lõi. */
export enum Mode {
  VIETNAMESE = 0,
  CHINESE = 1,
  ENGLISH = 2
}

export class KeyInput {
  kind: KeyKind;
  text: string;

  constructor(kind: KeyKind, text: string = '') {
    this.kind = kind;
    this.text = text;
  }

  static char(text: string): KeyInput {
    return new KeyInput(KeyKind.TEXT, text);
  }
}

const TAG = 'ViPi';
const DOMAIN = 0x5650;

/** Dữ liệu trong HAP (rawfile/vipi/), chép ra filesDir/res-<versionCode>/ lần đầu để lõi đọc bằng mmap. */
const FILES: string[] = [
  'vietnamese-syllables.txt', 'pinyin-words.bin', 'pinyin-abbrev.bin', 'bigram.bin', 's2t.bin',
  'autoswitch-vi.bin', 'autoswitch-en.bin', 'autoswitch-pairs.bin',
];

export function log(message: string): void {
  hilog.info(DOMAIN, TAG, '%{public}s', message);
}

export function logError(message: string): void {
  hilog.error(DOMAIN, TAG, '%{public}s', message);
}

function prepareData(ctx: common.Context): string {
  const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
  const dir = `${ctx.filesDir}/res-${info.versionCode}`;
  const marker = `${dir}/.complete`;
  if (fs.accessSync(marker)) {
    return dir;
  }
  for (const name of fs.listFileSync(ctx.filesDir)) {
    const path = `${ctx.filesDir}/${name}`;
    if (name.startsWith('res-') && path !== dir) {
      fs.rmdirSync(path);
    }
  }
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
  // bàn phím và màn hình cài đặt là hai tiến trình, có thể cùng chép: mỗi bên một file tạm riêng
  const stamp = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  for (const name of FILES) {
    const data: Uint8Array = ctx.resourceManager.getRawFileContentSync(`vipi/${name}`);
    const tmp = `${dir}/${name}.${stamp}.tmp`;
    const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(tmp, `${dir}/${name}`);
  }
  const done = fs.openSync(marker, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  fs.writeSync(done.fd, 'ok');
  fs.closeSync(done);
  return dir;
}

/** Nạp lõi một lần cho tiến trình; false nếu không nạp được (khi đó bàn phím gõ như bàn phím thường). */
export function openEngine(ctx: common.Context): boolean {
  if (vipi.isOpen()) {
    return true;
  }
  try {
    const started = Date.now();
    const error = vipi.open(prepareData(ctx));
    if (error.length > 0) {
      logError(`cannot load the input engine: ${error}`);
      return false;
    }
    log(`core loaded in ${Date.now() - started} ms`);
    return true;
  } catch (e) {
    logError(`cannot load the input engine: ${JSON.stringify(e)}`);
    return false;
  }
}

export function learnedWordsFile(ctx: common.Context): string {
  return `${ctx.filesDir}/pinyin-user.json`;
}

export { vipi, Outcome };
