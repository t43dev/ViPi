# ViPi for HarmonyOS

Vietnamese Telex, English and Chinese Pinyin on one keyboard, for HarmonyOS 6.0 (API 20) and later.
Same Rust engine as the Android, iOS and macOS versions; the keyboard is drawn on a Canvas with the same layout and
colours as Android.

Status: first version, builds and passes the tests below, **not yet run on a device**.

## Layout

| Path | What |
|---|---|
| `native/` | NAPI bridge from `core/` to ArkTS (`libvipi.so`, Rust + ohos-rs) |
| `entry/libs/<abi>/libvipi.so` | prebuilt bridge, so DevEco Studio needs no Rust toolchain |
| `entry/src/main/ets/ime/` | the keyboard: `InputMethodService` → `KeyboardController` (text field, engine) → `Board` (layout, touch, drawing) → `KeyboardPage` (two Canvas layers) |
| `entry/src/main/ets/settings/` | settings app (same options as Android) |
| `entry/src/main/ets/common/` | engine loading (data copied from `rawfile/vipi` to `filesDir/res-<versionCode>/` on first run), preferences |
| `entry/hvigorfile.ts` | copies the engine data from `../Resources` into `rawfile/vipi` on every build |
| `test/` | runs `KeyboardController` and `Board` in Node with the real Rust core and a fake text field |

## Run on a phone

1. Open `harmony/` in DevEco Studio 6.0 or later.
2. File → Project Structure → Signing Configs → sign in and tick **Automatically generate signature**.
3. Connect the phone (developer mode, USB debugging) and press Run.
4. On the phone: Settings → search for "keyboard" → turn on ViPi, then switch to it
   (or `hdc shell ime -e dev.t43.vipi` and `hdc shell ime -s dev.t43.vipi`).

## Foldables (tuned for Huawei Pura X Max)

- Cover screen (~389 × 569 vp): phone layout with compact 42 vp keys, so the app keeps more than half the screen.
- Inner screen unfolded (~795 × 562 vp): split keyboard, 64 vp keys, one half on each side of the hinge;
  Settings → Keyboard → "Wide" puts one block in the middle instead.
- Folding or unfolding resizes the keyboard (display `change` and `foldStatusChange`); the word being typed is kept.

## Install from Linux (no DevEco)

DevEco Studio only exists for Windows and macOS. From Linux, sign with an AppGallery Connect debug certificate:

1. `scripts/harmony-install.sh udid` with the phone plugged in (developer mode, USB debugging): register the UDID
   in AppGallery Connect → Certificates, App IDs and Profiles → Devices.
2. Create a debug certificate from the CSR of the key in `HARMONY_KEYSTORE`, an app ID for `dev.t43.vipi` and a
   debug profile (that certificate + that device). Put the paths in `.env` as `HARMONY_CERT` and `HARMONY_PROFILE`.
3. `scripts/harmony-build.sh` then `scripts/harmony-install.sh`: signs, installs, enables and switches to ViPi.

## Build and test on Linux (no DevEco)

```sh
# Rust bridge → entry/libs (needs the OpenHarmony SDK and rustup targets *-unknown-linux-ohos)
OHOS_SDK=<sdk>/linux/20 scripts/harmony-native.sh
# ArkTS compile check of an unsigned HAP against the public OpenHarmony SDK of the same API level
OHOS_SDK_ROOT=<sdk>/linux HVIGOR_NODE_MODULES=<dir>/node_modules scripts/harmony-build.sh
# keyboard logic with the real engine; `render` also draws the keyboard into test/out/*.png
scripts/harmony-test.sh render
```

The SDK is `ohos-sdk-windows_linux-public.tar.gz` from the OpenHarmony 6.0 release mirror; hvigor is
`@ohos/hvigor` and `@ohos/hvigor-ohos-plugin` from `https://repo.harmonyos.com/npm/`.

## Not in this version

The floating keyboard, clipboard history
(the clipboard button pastes), voice input, the immersive keyboard style, and the transparent strip above the keys:
the globe menu is drawn over the keys instead.
