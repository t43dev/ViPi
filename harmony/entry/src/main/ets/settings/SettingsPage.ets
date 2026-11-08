import { common, Want } from '@kit.AbilityKit';
import { inputMethod } from '@kit.IMEKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FuzzyOption } from 'libvipi.so';
import { vipi, openEngine, learnedWordsFile, logError } from '../common/Engine';
import {
  Settings, loadSettings, saveBool, saveString, saveStrings, saveNumber, MODERN_TONE, SPELL_CHECK, RESTORE,
  TRADITIONAL, LEARN, FULL_WIDTH, HAPTICS, AUTO_CAP, DOUBLE_SPACE, KEY_POPUP, THEME, FUZZY, LEARNED_CLEARED_AT,
  LARGE_LAYOUT
} from '../common/Prefs';

const RED = '#C8102E';

class ToggleRow {
  title: string;
  key: string;
  detail: string;

  constructor(title: string, key: string, detail: string) {
    this.title = title;
    this.key = key;
    this.detail = detail;
  }
}

class ThemeChoice {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

const VIETNAMESE: ToggleRow[] = [
  new ToggleRow('Check spelling', SPELL_CHECK,
    'Only add marks where they make a real Vietnamese syllable, so words like "class" stay as typed.'),
  new ToggleRow('Restore non-Vietnamese words', RESTORE,
    'When a word ends and is not Vietnamese, put back the keys you typed: user, data, more.'),
  new ToggleRow('Modern tone placement', MODERN_TONE, 'hoà, khoẻ, thuý instead of hòa, khỏe, thúy.'),
];

const CHINESE: ToggleRow[] = [
  new ToggleRow('Traditional characters', TRADITIONAL, '头发 becomes 頭髮.'),
  new ToggleRow('Learn the words I pick', LEARN, 'Words you pick come first next time. Stored only on this device.'),
  new ToggleRow('Full-width punctuation', FULL_WIDTH, '，。？！ while typing Chinese.'),
];

const KEYBOARD: ToggleRow[] = [
  new ToggleRow('Show key popup', KEY_POPUP, 'Show a larger letter above the key you press.'),
  new ToggleRow('Vibrate on key press', HAPTICS, ''),
  new ToggleRow('Auto-capitalize', AUTO_CAP, 'Start sentences with a capital letter.'),
  new ToggleRow('"." shortcut', DOUBLE_SPACE, 'Double-tap the space bar for a period and a space.'),
];

const LARGE: ThemeChoice[] = [
  new ThemeChoice('Split: one half on each side of the fold', 'SPLIT'),
  new ThemeChoice('Wide: one keyboard in the middle', 'WIDE'),
];

const THEMES: ThemeChoice[] = [new ThemeChoice('System', 'SYSTEM'), new ThemeChoice('Light', 'LIGHT'), new ThemeChoice('Dark', 'DARK')];

/** Cài đặt và hướng dẫn bật bàn phím. Giao diện tiếng Anh, cùng nội dung với bản Android. */
@Entry
@Component
struct SettingsPage {
  @State settings: Settings = new Settings();
  @State status: string = '';
  @State learned: string = '';
  @State fuzzyOptions: FuzzyOption[] = [];
  @State tryText: string = '';
  private ctx: common.UIAbilityContext = AppStorage.get<common.UIAbilityContext>('abilityContext') as common.UIAbilityContext;

  aboutToAppear(): void {
    this.settings = loadSettings(this.ctx, true);
    if (openEngine(this.ctx)) {
      vipi.configure(false, true, true, true, false, this.settings.learn, learnedWordsFile(this.ctx), []);
      this.fuzzyOptions = vipi.fuzzyOptions();
    }
    this.refresh();
  }

  onPageShow(): void {
    this.refresh();
  }

  private refresh(): void {
    const n = vipi.isOpen() ? vipi.learnedCount() : 0;
    this.learned = n === 0 ? 'No learned words yet.' : `${n} learned words and phrases.`;
    this.refreshStatus().catch(() => {
      this.status = 'Open Settings and search for "keyboard" to turn on ViPi.';
    });
  }

  private async refreshStatus(): Promise<void> {
    const current = inputMethod.getCurrentInputMethod();
    if (current !== undefined && current.name === this.ctx.applicationInfo.name) {
      this.status = 'ViPi is your keyboard.';
      return;
    }
    const state = await inputMethod.getSetting().getInputMethodState();
    this.status = state === inputMethod.EnabledState.DISABLED ?
      '1. Open Settings and search for "keyboard". 2. Turn on ViPi. 3. Come back and tap Switch to ViPi.' :
      'ViPi is on. Switch to it to start typing.';
  }

  private value(key: string): boolean {
    const s = this.settings;
    switch (key) {
      case MODERN_TONE:
        return s.modernTone;
      case SPELL_CHECK:
        return s.spellCheck;
      case RESTORE:
        return s.restore;
      case TRADITIONAL:
        return s.traditional;
      case LEARN:
        return s.learn;
      case FULL_WIDTH:
        return s.fullWidth;
      case HAPTICS:
        return s.haptics;
      case AUTO_CAP:
        return s.autoCap;
      case DOUBLE_SPACE:
        return s.doubleSpace;
      case KEY_POPUP:
        return s.keyPopup;
      default:
        return false;
    }
  }

  private set(key: string, on: boolean): void {
    saveBool(this.ctx, key, on);
    this.settings = loadSettings(this.ctx, false);
  }

  private setTheme(value: string): void {
    saveString(this.ctx, THEME, value);
    this.settings = loadSettings(this.ctx, false);
  }

  private setLarge(value: string): void {
    saveString(this.ctx, LARGE_LAYOUT, value);
    this.settings = loadSettings(this.ctx, false);
  }

  private setFuzzy(id: string, on: boolean): void {
    const list = this.settings.fuzzy.filter((x: string) => x !== id);
    if (on) {
      list.push(id);
    }
    saveStrings(this.ctx, FUZZY, list);
    this.settings = loadSettings(this.ctx, false);
  }

  private clearLearned(): void {
    if (vipi.isOpen()) {
      vipi.clearLearned();
    }
    // bàn phím chạy ở tiến trình khác: nó thấy mốc này lần mở sau thì đọc lại file đã xoá
    saveNumber(this.ctx, LEARNED_CLEARED_AT, Date.now());
    this.refresh();
  }

  private switchToViPi(): void {
    try {
      const list = inputMethod.getSetting().getInputMethodsSync(true);
      const ours = list.find((m: inputMethod.InputMethodProperty) => m.name === this.ctx.applicationInfo.name);
      if (ours === undefined) {
        this.status = 'Turn on ViPi first: open Settings and search for "keyboard".';
        return;
      }
      inputMethod.switchInputMethod(ours).then(() => this.refresh()).catch((e: BusinessError) => {
        logError(`switch: ${e.code} ${e.message}`);
        this.status = 'Tap the text box below, then pick ViPi with the keyboard button.';
      });
    } catch (e) {
      this.status = 'Tap the text box below, then pick ViPi with the keyboard button.';
    }
  }

  private openSource(): void {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://github.com/t43dev/ViPi'
    };
    this.ctx.startAbility(want).catch((e: BusinessError) => logError(`browser: ${e.code} ${e.message}`));
  }

  @Builder
  section(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(RED)
      .margin({ top: 26, bottom: 4 })
      .width('100%')
  }

  @Builder
  note(s: string) {
    Text(s)
      .fontSize(14)
      .opacity(0.75)
      .width('100%')
  }

  @Builder
  toggle(row: ToggleRow) {
    Column() {
      Row() {
        Text(row.title).fontSize(16).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.value(row.key) })
          .selectedColor(RED)
          .onChange((on: boolean) => this.set(row.key, on))
      }
      .width('100%')
      if (row.detail.length > 0) {
        Text(row.detail).fontSize(13).opacity(0.75).width('100%')
      }
    }
    .padding({ top: 8, bottom: 4 })
    .width('100%')
  }

  @Builder
  button(label: string, action: () => void) {
    Button(label)
      .type(ButtonType.Capsule)
      .backgroundColor(RED)
      .fontColor(Color.White)
      .margin({ top: 8 })
      .onClick(action)
  }

  build() {
    Scroll() {
      Column() {
        Text('ViPi').fontSize(30).fontWeight(FontWeight.Bold).width('100%')
        this.note('Vietnamese Telex and Chinese Pinyin on one keyboard.')

        this.section('Set up')
        this.note(this.status)
        this.button('Switch to ViPi', () => this.switchToViPi())
        TextArea({ placeholder: 'Try it here', text: this.tryText })
          .onChange((v: string) => {
            this.tryText = v;
          })
          .height(80)
          .margin({ top: 8 })

        this.section('Vietnamese')
        this.note('Vietnamese and English are one keyboard: ViPi tells them apart as you type, so treen becomes trên and server stays server. Tap the globe key to switch to Chinese and back; hold it for more choices and these settings. Hold a key on the top row for its number. Word lists from Vikey.')
        ForEach(VIETNAMESE, (row: ToggleRow) => {
          this.toggle(row)
        }, (row: ToggleRow) => row.key)

        this.section('Chinese')
        ForEach(CHINESE, (row: ToggleRow) => {
          this.toggle(row)
        }, (row: ToggleRow) => row.key)
        this.note(this.learned)
        this.button('Clear learned words', () => this.clearLearned())
        Text('Fuzzy pinyin').fontSize(14).opacity(0.75).width('100%').margin({ top: 10 })
        ForEach(this.fuzzyOptions, (o: FuzzyOption) => {
          Row() {
            Checkbox({ name: o.id })
              .select(this.settings.fuzzy.includes(o.id))
              .selectedColor(RED)
              .onChange((on: boolean) => this.setFuzzy(o.id, on))
            Text(o.label).fontSize(15)
          }
          .width('100%')
        }, (o: FuzzyOption) => o.id)

        this.section('Appearance')
        Row() {
          ForEach(THEMES, (t: ThemeChoice) => {
            Row() {
              Radio({ value: t.value, group: 'theme' })
                .checked(this.settings.theme === t.value)
                .onChange((on: boolean) => {
                  if (on) {
                    this.setTheme(t.value);
                  }
                })
              Text(t.label).fontSize(15).margin({ right: 16 })
            }
          }, (t: ThemeChoice) => t.value)
        }
        .width('100%')

        this.section('Keyboard')
        Text('On large screens (an unfolded phone or a tablet)').fontSize(14).opacity(0.75).width('100%').margin({ top: 6 })
        ForEach(LARGE, (t: ThemeChoice) => {
          Row() {
            Radio({ value: t.value, group: 'large' })
              .checked(this.settings.largeLayout === t.value)
              .onChange((on: boolean) => {
                if (on) {
                  this.setLarge(t.value);
                }
              })
            Text(t.label).fontSize(15)
          }
          .width('100%')
        }, (t: ThemeChoice) => t.value)
        ForEach(KEYBOARD, (row: ToggleRow) => {
          this.toggle(row)
        }, (row: ToggleRow) => row.key)

        this.section('About')
        this.note('ViPi is free software under GPL-3.0. Typing stays on this device.')
        this.button('Source code on GitHub', () => this.openSource())
      }
      .padding({ left: 20, right: 20, top: 28, bottom: 28 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }
}
