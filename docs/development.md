# Building ViPi from source

macOS 13+, Xcode command line tools:

```sh
swift test                           # engines (also runs on Linux)
VERSION=0.1.0 scripts/build-app.sh   # → build/ViPi.app + build/ViPi-0.1.0.zip (ad-hoc signed)
```

With `SIGN_IDENTITY="Developer ID Application: …"` the script signs with the hardened runtime and makes `build/ViPi-x.y.z.dmg`; with `NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` (App Store Connect API key) it also notarizes and staples the DMG. `scripts/mac-release.sh <version>` does all of this on a build Mac and attaches the DMG to the GitHub release `v<version>`.

`open -n /Applications/ViPi.app --args --selftest <words.txt> <out.txt> [gapMs] [holdMs] [variant]` types every word through the running ViPi with overlapping key presses and reports any word that comes out wrong.

CI (`.github/workflows/build.yml`) runs the tests and uploads an unsigned build as an artifact.

The Pinyin dictionary `Resources/pinyin.tsv` is generated from [rime-ice](https://github.com/iDvel/rime-ice) by `scripts/build_pinyin_dict.py`.
The word bigram model `Resources/bigram.bin` is built from [libpinyin](https://github.com/libpinyin/libpinyin)'s `interpolation2.text` by `scripts/make-bigram.py` (see the script header for the download).
The Simplified→Traditional table `Resources/s2t.tsv` is `STCharacters.txt` + `STPhrases.txt` from [OpenCC](https://github.com/BYVoid/OpenCC), first variant of each entry, one `simplified<TAB>traditional` line each.

The app does not read the `.tsv` files. `python3 -I scripts/build-tables.py` turns `pinyin.tsv` and `s2t.tsv` into `pinyin-words.bin`, `pinyin-abbrev.bin` and `s2t.bin`, which ViPi maps into memory and searches in place (format: [data-format.md](data-format.md)). Run it after changing either `.tsv` and commit the `.bin` files with it.

## Shared Rust core

`core/` is the input engine in Rust (crate `vipi-core`) for the Android, iOS and, later, macOS apps: Telex, Pinyin, the Vietnamese/English auto switch, text shortcuts, and `Composer`, which runs the per-mode key handling of `InputController.swift` and tells the platform what to delete, insert or let through. It reads the same `Resources/` files.

```sh
cd core && cargo test --release      # unit tests, Composer tests, and parity with the Swift engines
```

`core/tests/golden/` holds what the Swift engines produce for about 200,000 inputs (every syllable, English words, random keys, Pinyin sentences, selections, learning, Traditional output). `scripts/make-golden.sh` regenerates it from `Tests/ViPiCoreTests/GoldenTests.swift`; while both engines exist, change them together and rerun it.

Swift and Kotlin bindings come from [uniffi](https://mozilla.github.io/uniffi-rs/) (feature `uniffi`). Generate them from an unstripped build:

```sh
cargo build --features uniffi
cargo run --features bindgen --bin uniffi-bindgen -- generate --library target/debug/libvipi_core.so --language kotlin --out-dir <dir>
ANDROID_NDK_HOME=<ndk> cargo ndk -t arm64-v8a -t x86_64 -o <jniLibs> build --release --features uniffi
```

## Android

`android/` is the Android keyboard (`InputMethodService`) on top of the Rust core. Gradle builds the core for arm64-v8a, armeabi-v7a and x86_64 with `cargo ndk`, generates the Kotlin bindings with uniffi and copies the data files from `Resources/` into the APK, so it needs Rust with those Android targets, `cargo-ndk` and the NDK named in `app/build.gradle.kts`. Set `sdk.dir` in `android/local.properties`.

```sh
cd android && ./gradlew assembleDebug    # → app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell ime enable dev.t43.vipi/.ViPiInputMethod && adb shell ime set dev.t43.vipi/.ViPiInputMethod
```

On first launch the data files are copied from the APK to the app's files directory, where the core maps them into memory. A hardware keyboard goes through the same path as the on-screen keys, so `adb shell input text "tieengs%sVieetj%s"` types into the focused field; debug builds log every key's screen position under the logcat tag `ViPiKeys` for `adb shell input tap`.

`KeyboardView.kt` draws the whole keyboard on a canvas, following the Material 3 design (colours and sizes in dp from the design spec). The unpressed keys are recorded once into a `RenderNode`; each frame only adds the pressed keys, the key popup and the suggestion bar. The view is 124 dp taller than the keyboard (96 dp on short screens such as a phone in landscape, where the keys are smaller too): that transparent strip on top is where the globe key menu opens. `ViPiInputMethod.onComputeInsets` keeps apps laid out against the real keyboard top and passes touches on the strip through to the app unless the menu is open.

## Website

`site/` is the static page served at [vipi.t43.app](https://vipi.t43.app) (Cloudflare Pages project `vipi`). `scripts/site.sh` assembles `build/site` from it, the README screenshots, the syllable list and a cut-down Pinyin dictionary (`scripts/site-pinyin.py`); `scripts/site.sh deploy` also uploads it, using `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from `.env`. The typing demo in `site/app.js` ports the Telex rules of `TelexEngine.swift`; keep them in step when the engine changes.
