# Emulator tests for the Android keyboard

`suite.py` types through the on-screen keys with `adb` and checks the text field: Telex and the auto switch, word pairs and Backspace undo, the suggestion bar, Shift and Caps Lock, numbers by holding the top row, layers, punctuation, Chinese (candidates, Space, Enter, partial picks, the grid), the globe menu, Traditional characters, the clipboard panel, and two-finger rollover. It needs a **debug** build: the IME answers `adb shell am broadcast -a dev.t43.vipi.DUMP --es id <n>` by logging key positions, the field text and the mode under the logcat tag `ViPiKeys`.

```sh
cd android && ./gradlew assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell ime enable dev.t43.vipi/.ViPiInputMethod && adb shell ime set dev.t43.vipi/.ViPiInputMethod
adb root                                          # rollover writes raw touch events (mt.sh)
adb push test/emu/mt.sh /data/local/tmp/mt.sh
python3 test/emu/suite.py                         # ~10 min; prints PASS/FAIL and a summary
```

- The suite types into the "Try it here" field of ViPi's own settings screen (tap at 540×760 on a 1080×2400 screen) and reopens it when the keyboard is hidden.
- With two emulators running, set `ANDROID_SERIAL=emulator-5556` to pick one.
- The Android 16 AVD reports a hardware keyboard: `adb shell settings put secure show_ime_with_hard_keyboard 1`.
- After `adb install` or a force-stop the emulator falls back to Gboard; run `ime set` again.

## Android 17

The Android 17 image aborts in its gralloc mapper (`!hasReadColorBufferDma`) whenever something reads a screen buffer on the CPU: the gesture bar's colour sampling, `screencap`, the rotation animation, the pointer-location overlay. Boot it with

```sh
emulator -avd <android-17 avd> -no-window -gpu swiftshader_indirect -feature -Vulkan \
  -prop debug.renderengine.backend=skiaglthreaded -no-snapshot
adb shell cmd overlay enable com.android.internal.systemui.navbar.threebutton
```

and take screenshots with `adb emu screenrecord screenshot <absolute path>`. Landscape and gesture navigation cannot be tested there. It has no evdev touchscreen, so `mt.sh` does not work: `mt_uinput.py x0 y0 x1 y1 > mt.json` writes a `uinput` script for the same rollover (`adb push mt.json /data/local/tmp/ && adb shell uinput /data/local/tmp/mt.json`). With three-button navigation the positions in the dump are 63 px (the navigation bar) below the real keys; subtract that for `uinput` (`tap_uinput.py` taps one point to check).
