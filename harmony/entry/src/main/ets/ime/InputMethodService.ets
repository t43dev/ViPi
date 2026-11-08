import { InputMethodExtensionAbility } from '@kit.IMEKit';
import { Want } from '@kit.AbilityKit';
import { keyboardController } from './KeyboardController';

/** Bộ gõ ViPi: mọi việc nằm trong KeyboardController (bảng bàn phím, lõi, ô nhập). */
export default class InputMethodService extends InputMethodExtensionAbility {
  onCreate(want: Want): void {
    keyboardController.onCreate(this.context);
  }

  onDestroy(): void {
    keyboardController.onDestroy();
  }
}
