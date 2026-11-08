import { inputMethod, inputMethodEngine, InputMethodExtensionContext } from '@kit.IMEKit';
import { display } from '@kit.ArkUI';
import { ConfigurationConstant, Configuration, EnvironmentCallback, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { KeyCode, KeyEvent, Action as KeyAction } from '@kit.InputKit';
import { vibrator } from '@kit.SensorServiceKit';
import { KeyInput, KeyKind, Mode, Outcome, vipi, openEngine, learnedWordsFile, log, logError } from '../common/Engine';
import { Settings, loadSettings, saveBool, saveMode, TRADITIONAL } from '../common/Prefs';
import {
  Action, Board, BoardListener, Layout, Shift, PICK_CHINESE, PICK_OTHER_KEYBOARD, PICK_SETTINGS, PICK_TOGGLE,
  PICK_TRADITIONAL, PICK_VIEN
} from './Board';

/** Lớp Canvas của trang bàn phím; trang đăng ký khi đã sẵn sàng. */
export interface KeyboardView {
  draw(staticLayer: boolean, dynamicLayer: boolean): void;
}

const PREVIEW_ALL: inputMethodEngine.Range = { start: -1, end: -1 };
const HAPTIC = 'haptic.clock.timer';

/**
 * Bàn phím ViPi cho HarmonyOS. Lõi Rust quyết định chữ; ở đây chỉ đổi kết quả thành thao tác trên ô nhập:
 * - Tiếng Việt và tiếng Anh: chữ đi thẳng vào ô nhập; dấu thanh, gõ tắt, tự đổi thì xoá lùi rồi chèn (như macOS).
 * - Tiếng Trung: pinyin đang gõ là chữ tạm (gạch chân) trong ô nhập nếu ô hỗ trợ, nếu không thì hiện ở đầu
 *   thanh ứng viên; chọn chữ Hán thì thay chỗ pinyin.
 */
class KeyboardController implements BoardListener {
  private ctx: InputMethodExtensionContext | undefined = undefined;
  private panel: inputMethodEngine.Panel | undefined = undefined;
  private client: inputMethodEngine.InputClient | undefined = undefined;
  private keyboard: inputMethodEngine.KeyboardController | undefined = undefined;
  private view: KeyboardView | undefined = undefined;
  readonly board: Board;
  private settings: Settings = new Settings();
  private engineOk: boolean = false;
  /** Ô mật khẩu / số: không qua bộ gõ. */
  private passthrough: boolean = false;
  private autoCapAllowed: boolean = true;
  private enterType: number = 0;
  private previewSupported: boolean = false;
  private previewActive: boolean = false;
  private last: Outcome = vipi.state();
  private lastOwnEdit: number = 0;
  private lastSpaceAt: number = 0;
  private systemDark: boolean = false;
  private hapticPreset: boolean = false;
  private hardwareConsumed: Set<number> = new Set<number>();
  private learnedClearedAt: number = -1;
  private largeSplit: boolean = true;
  private envCallback: number = -1;
  private redrawStatic: boolean = false;
  private redrawDynamic: boolean = false;
  private redrawQueued: boolean = false;

  constructor() {
    this.board = new Board(this);
  }

  // MARK: - Vòng đời

  onCreate(ctx: InputMethodExtensionContext): void {
    this.ctx = ctx;
    this.engineOk = openEngine(ctx);
    this.systemDark = ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      this.hapticPreset = vibrator.isSupportEffectSync(HAPTIC);
    } catch (e) {
      this.hapticPreset = false;
    }
    this.reloadSettings();
    this.createPanel();
    this.register();
  }

  onDestroy(): void {
    const ima = inputMethodEngine.getInputMethodAbility();
    ima.off('inputStart');
    ima.off('inputStop', this.onInputStop);
    ima.off('keyboardShow');
    ima.off('keyboardHide');
    ima.off('discardTypingText');
    const delegate = inputMethodEngine.getKeyboardDelegate();
    delegate.off('selectionChange');
    delegate.off('editorAttributeChanged');
    delegate.off('keyEvent');
    try {
      display.off('change');
      display.off('foldStatusChange');
    } catch (e) {
      // không sao
    }
    if (this.ctx !== undefined && this.envCallback >= 0) {
      this.ctx.getApplicationContext().off('environment', this.envCallback);
    }
    if (this.panel !== undefined) {
      ima.destroyPanel(this.panel);
      this.panel = undefined;
    }
    this.client = undefined;
  }

  attachView(view: KeyboardView | undefined): void {
    this.view = view;
    if (view !== undefined) {
      view.draw(true, true);
    }
  }

  private async createPanel(): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    try {
      const info: inputMethodEngine.PanelInfo = {
        type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
        flag: inputMethodEngine.PanelFlag.FLG_FIXED
      };
      this.panel = await inputMethodEngine.getInputMethodAbility().createPanel(this.ctx, info);
      await this.resizePanel();
      await this.panel.setUiContent('ime/KeyboardPage');
    } catch (e) {
      logError(`cannot create the keyboard panel: ${JSON.stringify(e)}`);
    }
  }

  /** Chiều cao theo màn hình hiện tại (xoay ngang thì gọn hơn); bề ngang bằng màn hình. */
  private async resizePanel(): Promise<void> {
    if (this.panel === undefined) {
      return;
    }
    const d = display.getDefaultDisplaySync();
    const density = d.densityPixels > 0 ? d.densityPixels : 1;
    const vp = Board.heightFor(d.width / density, d.height / density, this.settings.largeLayout !== 'WIDE');
    await this.panel.resize(d.width, Math.round(vp * density));
  }

  private relayout(): void {
    this.board.reset();
    this.resizePanel().catch((e: BusinessError) => logError(`resize: ${e.code} ${e.message}`));
  }

  /** Chiều cao màn hình (vp), để trang bàn phím chọn cỡ phím. */
  screenHeight(): number {
    const d = display.getDefaultDisplaySync();
    return d.height / (d.densityPixels > 0 ? d.densityPixels : 1);
  }

  // ô nhập rời bộ gõ: giữ bàn phím và lõi (nạp lại tốn thời gian), chỉ bỏ phần đang gõ dở
  private readonly onInputStop = (): void => {
    this.previewActive = false;
    vipi.cancel();
    this.client = undefined;
    this.board.reset();
    this.refresh(vipi.state());
  };

  private register(): void {
    const ima = inputMethodEngine.getInputMethodAbility();
    ima.on('inputStart', (kb: inputMethodEngine.KeyboardController, client: inputMethodEngine.InputClient) => {
      this.keyboard = kb;
      this.client = client;
      this.reloadSettings();
      try {
        this.startInput(client.getEditorAttributeSync());
      } catch (e) {
        logError(`inputStart: ${JSON.stringify(e)}`);
      }
    });
    ima.on('inputStop', this.onInputStop);
    ima.on('keyboardShow', () => {
      this.reloadSettings();
      this.redraw(true);
    });
    ima.on('keyboardHide', () => {
      this.board.reset();
      this.endComposition();
    });
    ima.on('discardTypingText', () => this.endComposition());

    const delegate = inputMethodEngine.getKeyboardDelegate();
    delegate.on('selectionChange', (oldBegin: number, oldEnd: number, newBegin: number, newEnd: number) => {
      // con trỏ bị dời ngoài bàn phím (chạm chỗ khác trong ô nhập): bỏ phần đang gõ
      if (Date.now() - this.lastOwnEdit < 300) {
        return;
      }
      if (oldBegin === newBegin && oldEnd === newEnd) {
        return;
      }
      this.endComposition();
      this.updateShift();
    });
    delegate.on('editorAttributeChanged', (attr: inputMethodEngine.EditorAttribute) => this.startInput(attr));
    delegate.on('keyEvent', (e: KeyEvent): boolean => this.onHardwareKey(e));

    // xoay màn, gập/mở máy (Pura X Max: màn ngoài ~389 vp ↔ màn trong ~795 vp): đổi cỡ bảng bàn phím, trang
    // bàn phím nhận cỡ mới (onAreaChange) rồi chọn bố cục; chữ đang gõ trong lõi giữ nguyên
    display.on('change', () => this.relayout());
    try {
      if (display.isFoldable()) {
        display.on('foldStatusChange', () => this.relayout());
      }
    } catch (e) {
      // máy không gập
    }
    if (this.ctx !== undefined) {
      const env: EnvironmentCallback = {
        onConfigurationUpdated: (config: Configuration): void => {
          this.systemDark = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
          this.applyTheme();
        },
        onMemoryLevel: (): void => {
        }
      };
      this.envCallback = this.ctx.getApplicationContext().on('environment', env);
    }
  }

  // MARK: - Ô nhập

  private startInput(attr: inputMethodEngine.EditorAttribute): void {
    const p = attr.inputPattern;
    const password = p === inputMethodEngine.PATTERN_PASSWORD || p === inputMethodEngine.PATTERN_PASSWORD_NUMBER ||
      p === inputMethodEngine.PATTERN_PASSWORD_SCREEN_LOCK || p === inputMethodEngine.PATTERN_NEW_PASSWORD;
    const numeric = p === inputMethodEngine.PATTERN_NUMBER || p === inputMethodEngine.PATTERN_PHONE ||
      p === inputMethodEngine.PATTERN_DATETIME || p === inputMethodEngine.PATTERN_PASSWORD_NUMBER ||
      p === inputMethodEngine.PATTERN_NUMBER_DECIMAL || p === inputMethodEngine.PATTERN_ONE_TIME_CODE;
    this.passthrough = password || numeric || !this.engineOk;
    this.autoCapAllowed = !password && !numeric && p !== inputMethodEngine.PATTERN_EMAIL &&
      p !== inputMethodEngine.PATTERN_URI && p !== inputMethodEngine.PATTERN_USER_NAME;
    this.enterType = attr.enterKeyType;
    this.previewSupported = attr.isTextPreviewSupported === true && !this.passthrough;
    this.previewActive = false;
    vipi.cancel();
    this.board.layout = numeric ? Layout.NUMBERS : Layout.LETTERS;
    this.board.action = this.actionFor(attr.enterKeyType);
    this.board.modeLocked = this.passthrough;
    this.board.shift = Shift.OFF;
    this.refresh(vipi.state());
    this.updateShift();
  }

  private actionFor(type: number): Action {
    switch (type) {
      case 2:
        return Action.GO;
      case 3:
        return Action.SEARCH;
      case 4:
        return Action.SEND;
      case 5:
      case 7:
        return Action.NEXT;
      case 6:
        return Action.DONE;
      default:
        return Action.RETURN;
    }
  }

  // MARK: - Cài đặt

  private reloadSettings(): void {
    if (this.ctx === undefined) {
      return;
    }
    try {
      this.settings = loadSettings(this.ctx, true);
    } catch (e) {
      logError(`cannot read settings: ${JSON.stringify(e)}`);
    }
    const s = this.settings;
    if (this.engineOk) {
      if (this.learnedClearedAt >= 0 && this.learnedClearedAt !== s.learnedClearedAt) {
        // màn hình cài đặt vừa xoá từ đã học: bỏ bản trong bộ nhớ, đọc lại file
        vipi.configure(s.modernTone, s.spellCheck, s.restore, s.fullWidth, s.traditional, false, '', s.fuzzy);
      }
      this.learnedClearedAt = s.learnedClearedAt;
      vipi.configure(s.modernTone, s.spellCheck, s.restore, s.fullWidth, s.traditional, s.learn,
        learnedWordsFile(this.ctx), s.fuzzy);
      if (vipi.state().mode !== s.mode) {
        vipi.setMode(s.mode);
      }
    }
    this.board.keyPopup = s.keyPopup;
    this.board.fullWidth = s.fullWidth;
    this.board.traditional = s.traditional;
    const split = s.largeLayout !== 'WIDE';
    if (this.largeSplit !== split) {
      this.largeSplit = split;
      this.board.largeSplit = split;
      this.resizePanel().catch((e: BusinessError) => logError(`resize: ${e.code} ${e.message}`));
    }
    this.applyTheme();
    this.refresh(vipi.state());
  }

  private applyTheme(): void {
    const t = this.settings.theme;
    this.board.setDark(t === 'DARK' || (t !== 'LIGHT' && this.systemDark));
  }

  // MARK: - Phím

  onKey(key: KeyInput): void {
    const client = this.client;
    if (client === undefined) {
      return;
    }
    this.lastOwnEdit = Date.now();
    try {
      if (!this.engineOk || this.passthrough) {
        this.deliver(client, key);
        this.updateShift();
        return;
      }
      const before = this.last.mode;
      const wasComposing = this.last.composingChinese;
      const r = vipi.handleKey(key.kind, key.text);
      if (key.kind === KeyKind.BACKSPACE && r.hasEdit) {
        // Backspace ngay sau một lần tự đổi: trả lại chữ trước đó (lõi đã về chế độ cũ)
        this.replace(client, r.backspaces, r.insert);
      } else if (before === Mode.CHINESE) {
        this.applyChinese(client, key, r, wasComposing);
      } else {
        this.applyLatin(client, key, r);
      }
      if (r.switchedTo >= 0) {
        this.rememberMode(r.switchedTo as Mode);
      }
      this.refresh(r);
    } catch (e) {
      logError(`key: ${JSON.stringify(e)}`);
    }
    this.updateShift();
  }

  /** Việt / Anh: phím đi qua, hoặc xoá lùi rồi chèn chữ của lõi, rồi gửi lại phím gốc nếu cần. */
  private applyLatin(client: inputMethodEngine.InputClient, key: KeyInput, r: Outcome): void {
    if (!r.handled) {
      this.deliver(client, key);
      return;
    }
    if (r.hasEdit) {
      this.replace(client, r.backspaces, r.insert);
    }
    if (r.repostKey) {
      this.deliver(client, key);
    }
  }

  private applyChinese(client: inputMethodEngine.InputClient, key: KeyInput | null, r: Outcome, wasComposing: boolean): void {
    if (!r.handled) {
      if (key !== null) {
        this.deliver(client, key);
      }
      return;
    }
    // chữ Hán đã chọn thay chỗ pinyin đang gạch chân; còn pinyin chưa chọn (chọn từng phần) thì gạch chân tiếp
    if (r.hasEdit) {
      this.commitChinese(client, r.insert);
    }
    if (r.composingChinese) {
      this.showPreedit(client, r.preedit);
    } else if (this.previewActive) {
      this.clearPreview(client);
    }
    if (r.repostKey && key !== null) {
      this.deliver(client, key);
    }
  }

  private replace(client: inputMethodEngine.InputClient, backspaces: number, insert: string): void {
    if (backspaces > 0) {
      client.deleteForwardSync(backspaces);
    }
    if (insert.length > 0) {
      client.insertTextSync(insert);
    }
  }

  private commitChinese(client: inputMethodEngine.InputClient, text: string): void {
    if (this.previewActive) {
      try {
        client.setPreviewTextSync(text, PREVIEW_ALL);
        client.finishTextPreviewSync();
        this.previewActive = false;
        return;
      } catch (e) {
        this.dropPreview(client, e as BusinessError);
      }
    }
    client.insertTextSync(text);
  }

  private showPreedit(client: inputMethodEngine.InputClient, preedit: string): void {
    if (!this.previewSupported) {
      return;
    }
    try {
      client.setPreviewTextSync(preedit, PREVIEW_ALL);
      this.previewActive = true;
    } catch (e) {
      this.dropPreview(client, e as BusinessError);
    }
  }

  private clearPreview(client: inputMethodEngine.InputClient): void {
    try {
      client.setPreviewTextSync('', PREVIEW_ALL);
      client.finishTextPreviewSync();
    } catch (e) {
      this.dropPreview(client, e as BusinessError);
    }
    this.previewActive = false;
  }

  /** Ô nhập không nhận chữ tạm: từ đây pinyin hiện ở thanh ứng viên. */
  private dropPreview(client: inputMethodEngine.InputClient, e: BusinessError): void {
    logError(`preview text: ${e.code} ${e.message}`);
    if (this.previewActive) {
      try {
        client.finishTextPreviewSync();
      } catch (ignored) {
        // ô nhập đã bỏ chữ tạm
      }
    }
    this.previewActive = false;
    this.previewSupported = false;
  }

  /** Phím đi thẳng tới ô nhập như một bàn phím thường. */
  private deliver(client: inputMethodEngine.InputClient, key: KeyInput): void {
    switch (key.kind) {
      case KeyKind.TEXT:
        client.insertTextSync(key.text);
        break;
      case KeyKind.SPACE:
        this.space(client);
        break;
      case KeyKind.ENTER:
        if (this.enterType >= 2 && this.enterType <= 7) {
          client.sendKeyFunction(this.enterType).catch((e: BusinessError) => logError(`enter: ${e.code}`));
        } else {
          client.insertTextSync('\n');
        }
        break;
      case KeyKind.BACKSPACE:
        client.deleteForwardSync(1);
        break;
      case KeyKind.TAB:
        client.insertTextSync('\t');
        break;
      case KeyKind.LEFT:
        client.moveCursorSync(inputMethodEngine.Direction.CURSOR_LEFT);
        break;
      case KeyKind.RIGHT:
        client.moveCursorSync(inputMethodEngine.Direction.CURSOR_RIGHT);
        break;
      case KeyKind.UP:
        client.moveCursorSync(inputMethodEngine.Direction.CURSOR_UP);
        break;
      case KeyKind.DOWN:
        client.moveCursorSync(inputMethodEngine.Direction.CURSOR_DOWN);
        break;
      default:
        break;
    }
    if (key.kind !== KeyKind.SPACE) {
      this.lastSpaceAt = 0;
    }
  }

  /** Hai lần cách liền nhau sau một chữ: ". " (như iOS). */
  private space(client: inputMethodEngine.InputClient): void {
    const now = Date.now();
    if (this.settings.doubleSpace && now - this.lastSpaceAt < 600) {
      const before = client.getForwardSync(2);
      if (before.length === 2 && before[1] === ' ' && /[\p{L}\p{N}]/u.test(before[0])) {
        client.deleteForwardSync(1);
        client.insertTextSync('. ');
        this.lastSpaceAt = 0;
        return;
      }
    }
    client.insertTextSync(' ');
    this.lastSpaceAt = now;
  }

  onCandidate(index: number): void {
    const client = this.client;
    if (client === undefined || !this.engineOk) {
      return;
    }
    this.lastOwnEdit = Date.now();
    try {
      const r = vipi.selectCandidate(index);
      this.applyChinese(client, null, r, true);
      this.refresh(r);
    } catch (e) {
      logError(`candidate: ${JSON.stringify(e)}`);
    }
  }

  /** Thanh gợi ý tiếng Việt: giữ đúng các phím đã gõ (0) hoặc chữ đang hiện (1), rồi một dấu cách. */
  onSuggestion(index: number): void {
    const client = this.client;
    if (client === undefined || !this.engineOk) {
      return;
    }
    this.lastOwnEdit = Date.now();
    try {
      const word = this.last.word;
      const text = index === 0 ? this.last.keys : word;
      this.replace(client, word.length, text + ' ');
      vipi.cancel();
      this.refresh(vipi.state());
    } catch (e) {
      logError(`suggestion: ${JSON.stringify(e)}`);
    }
    this.updateShift();
  }

  onCursor(delta: number): void {
    const client = this.client;
    if (client === undefined) {
      return;
    }
    this.endComposition();
    this.lastOwnEdit = Date.now();
    try {
      client.moveCursorSync(delta > 0 ? inputMethodEngine.Direction.CURSOR_RIGHT : inputMethodEngine.Direction.CURSOR_LEFT);
    } catch (e) {
      logError(`cursor: ${JSON.stringify(e)}`);
    }
  }

  /** Nút bảng tạm: dán (không cần quyền đọc bảng tạm). */
  onPaste(): void {
    const client = this.client;
    if (client === undefined) {
      return;
    }
    this.endComposition();
    client.sendExtendAction(inputMethodEngine.ExtendAction.PASTE)
      .catch((e: BusinessError) => logError(`paste: ${e.code} ${e.message}`));
  }

  feedback(): void {
    if (!this.settings.haptics) {
      return;
    }
    try {
      const effect: vibrator.VibrateEffect = this.hapticPreset ?
        { type: 'preset', effectId: HAPTIC, count: 1 } as vibrator.VibratePreset :
        { type: 'time', duration: 8 } as vibrator.VibrateTime;
      const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };
      vibrator.startVibration(effect, attribute).catch(() => {
      });
    } catch (e) {
      // máy không rung được
    }
  }

  // MARK: - Chế độ

  /** Phím quả địa cầu: chạm đổi Việt·Anh ↔ Trung; giữ lâu: menu. */
  onPickInput(choice: number): void {
    const chinese = this.last.mode === Mode.CHINESE;
    switch (choice) {
      case PICK_VIEN:
        if (chinese) {
          this.setMode(this.settings.latin);
        }
        break;
      case PICK_CHINESE:
        if (!chinese) {
          this.setMode(Mode.CHINESE);
        }
        break;
      case PICK_TOGGLE:
        if (!this.passthrough) {
          this.setMode(chinese ? this.settings.latin : Mode.CHINESE);
        }
        break;
      case PICK_SETTINGS:
        this.openSettings();
        break;
      case PICK_TRADITIONAL:
        if (this.ctx !== undefined) {
          saveBool(this.ctx, TRADITIONAL, !this.settings.traditional);
          this.reloadSettings();
        }
        break;
      case PICK_OTHER_KEYBOARD:
        this.nextKeyboard();
        break;
      default:
        break;
    }
  }

  private setMode(mode: Mode): void {
    if (!this.engineOk) {
      return;
    }
    this.endComposition();
    vipi.setMode(mode);
    this.rememberMode(mode);
    this.refresh(vipi.state());
    this.updateShift();
  }

  private rememberMode(mode: Mode): void {
    this.settings.mode = mode;
    if (mode !== Mode.CHINESE) {
      this.settings.latin = mode;
    }
    if (this.ctx !== undefined) {
      saveMode(this.ctx, mode);
    }
  }

  private openSettings(): void {
    if (this.ctx === undefined) {
      return;
    }
    const want: Want = { bundleName: this.ctx.applicationInfo.name, abilityName: 'EntryAbility' };
    this.ctx.startAbility(want).catch((e: BusinessError) => logError(`settings: ${e.code} ${e.message}`));
  }

  /** Sang bàn phím đang bật tiếp theo (HarmonyOS không cho bộ gõ bên thứ ba mở bảng chọn bàn phím). */
  private nextKeyboard(): void {
    try {
      const list = inputMethod.getSetting().getInputMethodsSync(true);
      const current = inputMethod.getCurrentInputMethod();
      const i = list.findIndex((m: inputMethod.InputMethodProperty) => m.name === current.name);
      for (let step = 1; step < list.length; step++) {
        const next = list[(Math.max(i, 0) + step) % list.length];
        if (next.name !== current.name) {
          inputMethod.switchInputMethod(next).catch((e: BusinessError) => logError(`switch: ${e.code} ${e.message}`));
          return;
        }
      }
    } catch (e) {
      logError(`next keyboard: ${JSON.stringify(e)}`);
    }
  }

  /** Bỏ phần đang gõ: chữ Việt đã nằm trong ô nhập, pinyin chưa chọn thì xoá. */
  private endComposition(): void {
    const client = this.client;
    if (client !== undefined && this.previewActive) {
      this.clearPreview(client);
    }
    this.previewActive = false;
    vipi.cancel();
    this.refresh(vipi.state());
  }

  private refresh(r: Outcome): void {
    this.last = r;
    const engine = this.engineOk && !this.passthrough;
    const chinese = engine && r.mode === Mode.CHINESE;
    this.board.chinese = chinese;
    const composing = chinese && r.composingChinese;
    this.board.setCandidates(composing ? r.candidates : [], composing && !this.previewActive ? r.preedit : '');
    const viet = engine && r.mode === Mode.VIETNAMESE;
    this.board.setSuggestions(viet ? r.keys : '', viet ? r.word : '');
  }

  /** Tự viết hoa đầu câu: đầu ô nhập, sau ". ", "? ", "! " hoặc xuống dòng. */
  private updateShift(): void {
    const board = this.board;
    if (board.shift === Shift.LOCK || board.layout !== Layout.LETTERS) {
      return;
    }
    // tiếng Trung: không tự viết hoa (chữ hoa không phải pinyin, sẽ đi thẳng vào ô nhập)
    const chinese = !this.passthrough && this.last.mode === Mode.CHINESE;
    if (!this.settings.autoCap || chinese) {
      if (chinese && board.shift === Shift.ONCE) {
        board.shift = Shift.OFF;
      }
      return;
    }
    if (!this.autoCapAllowed || this.last.word.length > 0 || this.client === undefined) {
      board.shift = Shift.OFF;
      return;
    }
    let before = '';
    try {
      before = this.client.getForwardSync(3);
    } catch (e) {
      return;
    }
    const caps = before.length === 0 || /(^|[.!?])\s+$/.test(before) || before.endsWith('\n');
    board.shift = caps ? Shift.ONCE : Shift.OFF;
  }

  // MARK: - Bàn phím thật (Bluetooth / USB): cùng đường đi qua lõi

  private onHardwareKey(e: KeyEvent): boolean {
    const code = e.key.code;
    if (e.action === KeyAction.UP) {
      return this.hardwareConsumed.delete(code);
    }
    if (e.action !== KeyAction.DOWN || this.client === undefined || !this.engineOk || this.passthrough) {
      return false;
    }
    if (e.ctrlKey || e.altKey || e.logoKey) {
      this.endComposition();
      return false;
    }
    const chinese = this.last.composingChinese;
    let key: KeyInput | null = null;
    switch (code) {
      case KeyCode.KEYCODE_DEL:
        key = new KeyInput(KeyKind.BACKSPACE);
        break;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        key = new KeyInput(KeyKind.ENTER);
        break;
      case KeyCode.KEYCODE_SPACE:
        key = new KeyInput(KeyKind.SPACE);
        break;
      case KeyCode.KEYCODE_TAB:
        key = chinese ? new KeyInput(KeyKind.TAB) : null;
        break;
      case KeyCode.KEYCODE_ESCAPE:
        key = chinese ? new KeyInput(KeyKind.ESCAPE) : null;
        break;
      case KeyCode.KEYCODE_DPAD_LEFT:
        key = chinese ? new KeyInput(KeyKind.LEFT) : null;
        break;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        key = chinese ? new KeyInput(KeyKind.RIGHT) : null;
        break;
      case KeyCode.KEYCODE_DPAD_UP:
        key = chinese ? new KeyInput(KeyKind.UP) : null;
        break;
      case KeyCode.KEYCODE_DPAD_DOWN:
        key = chinese ? new KeyInput(KeyKind.DOWN) : null;
        break;
      case KeyCode.KEYCODE_PAGE_UP:
        key = chinese ? new KeyInput(KeyKind.PAGE_UP) : null;
        break;
      case KeyCode.KEYCODE_PAGE_DOWN:
        key = chinese ? new KeyInput(KeyKind.PAGE_DOWN) : null;
        break;
      default: {
        const u = e.unicodeChar;
        if (u >= 32 && u !== 127) {
          let s = String.fromCodePoint(u);
          if (e.shiftKey && s >= 'a' && s <= 'z') {
            s = s.toUpperCase();
          }
          key = KeyInput.char(s);
        }
      }
    }
    if (key === null) {
      this.endComposition();
      return false;
    }
    this.hardwareConsumed.add(code);
    this.onKey(key);
    return true;
  }

  // MARK: - Vẽ lại (gộp các yêu cầu trong cùng một lượt)

  redraw(staticLayer: boolean): void {
    this.redrawDynamic = true;
    if (staticLayer) {
      this.redrawStatic = true;
    }
    if (this.redrawQueued) {
      return;
    }
    this.redrawQueued = true;
    setTimeout(() => {
      this.redrawQueued = false;
      const s = this.redrawStatic;
      const d = this.redrawDynamic;
      this.redrawStatic = false;
      this.redrawDynamic = false;
      if (this.view !== undefined) {
        this.view.draw(s, d);
      }
    }, 0);
  }
}

export const keyboardController = new KeyboardController();
