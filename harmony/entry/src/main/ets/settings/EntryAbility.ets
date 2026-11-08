import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logError } from '../common/Engine';

/** Màn hình cài đặt của ViPi (mở từ biểu tượng app hoặc từ menu phím quả địa cầu). */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('abilityContext', this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('settings/SettingsPage', (err) => {
      if (err.code) {
        logError(`settings page: ${err.code} ${err.message}`);
      }
    });
  }
}
