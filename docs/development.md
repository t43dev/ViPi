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

`core/src/suggest/` is the word suggestion bar, slip correction and sentence-aware key picking of the iOS keyboard (`ios/ViPiKeyboard/Suggest/`, from Vikey), ported for Android and HarmonyOS: the model readers (`lm.rs`, `nn.rs`), the tap model (`tap.rs`), the keep lists (`keep.rs`, `Resources/keep-words*.txt`) and ViPi's rules (`suggester.rs`). Through uniffi it is `ViPiSuggest`, a second object next to `ViPiComposer` with its own lock. Its four model files (65 MB) are not in git: `scripts/suggest-models.sh [dir]` downloads them from Vikey at a pinned commit into `build/suggest` (default) and checks their SHA-256. `cargo test` compares the port with the Swift code (`core/tests/suggest.rs` against `core/tests/golden/suggest.txt.gz`) when the files are in `VIPI_SUGGEST_MODELS` or `build/suggest`, and skips those tests otherwise. After changing the Swift side, regenerate the answers on a Mac with `scripts/make-suggest-golden.sh` (it compiles `ios/Tools/suggest-golden/main.swift` with the keyboard's Swift files; models from `VIPI_SUGGEST_MODELS`, default `ios/Suggest`). Timings: `cargo test --release --test suggest -- --ignored --nocapture`.

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

`KeyboardView.kt` draws the whole keyboard on a canvas, following the Material 3 design (colours and sizes in dp from the design spec). The unpressed keys are recorded once into a `RenderNode`; each frame only adds the pressed keys, the key popup and the suggestion bar. The view is 124 dp taller than the keyboard (96 dp on short screens such as a phone in landscape, where the keys are smaller too): that transparent strip on top is where the globe key menu opens. `ViPiInputMethod.onComputeInsets` keeps apps laid out against the real keyboard top and passes touches on the strip through to the app unless the menu is open. On screens at least 600 dp wide the keyboard is split around the fold (or one wide block, or a floating card, per the setting); the floating card fills the IME window with a transparent view, so apps keep their full size and only the card takes touches. Emulator tests are in `android/test/emu/`.

## iPhone and iPad

`ios/` is the iOS/iPadOS app (iOS 26+, Liquid Glass): a SwiftUI settings app and a keyboard extension in UIKit that draws its keys with Core Graphics, like the Android `KeyboardView`. Both use the Rust core through uniffi; the dictionaries are bundled in the keyboard and read with mmap, so they stay out of the keyboard's memory limit.

```
scripts/ios-dev.sh            # from the dev machine: copy the tree to a Mac (MAC in .env) and build there
scripts/ios-build.sh [--core] # on the Mac: Rust core if needed, xcodegen, simulator build
scripts/ios-core.sh           # on the Mac: ios/Core/ViPiCore.xcframework + ViPiCoreFFI.swift
scripts/ios-type.sh "<taps>" [simulator] [name]  # on the Mac: type with ViPi in the simulator, print the text, take a screenshot
```

TestFlight builds come from the committed `HEAD`, signed on the Mac with the team's Apple Distribution certificate:

```
scripts/ios-profiles.sh    # App Store profiles for dev.t43.vipi and dev.t43.vipi.keyboard (again after any App ID change)
scripts/ios-testflight.sh  # archive, sign, upload, wait for App Store Connect to process the build
```

Both read the signing files through `APPLE_ENV` in `.env`; the team ID is passed in at build time and is not in the repo. The App Group `group.dev.t43.vipi` and the App Store Connect app record cannot be made through the API: create them on developer.apple.com and appstoreconnect.apple.com first.

`ios-type.sh` runs `ios/ViPiUITests`: the first run on a simulator turns ViPi on in Settings, then each run taps the given screen points (in points; `w` waits a second, `p:x,y,s` holds, `2:x,y` double-taps, `d:x1,y1,x2,y2` drags) in the app's "Try it here" field. `SET="<switch label>=1"` sets a switch in the app first, which checks that settings reach the keyboard through the App Group. The keys are drawn, not views, so the taps are coordinates; on an iPhone 18 Pro in portrait with the suggestion bar the key centres are at y 615, 669 and 723 (letter rows) and 777 (bottom row), the bar at 570, and letter key i of a row at x = 3.7 + 39.46 × (i + 0.5) (row 2 starts half a key in, row 3 one and a half). `FIELD=search` gives the trial field a Search key (one line; Enter closes the keyboard).

The iOS keyboard's word suggestions, slip correction and sentence-aware key areas come from Vikey (`ios/ViPiKeyboard/Suggest/`: `SuggestLM.swift`, `SuggestNN.swift` and `TapModel.swift` are Vikey's code, `Suggester.swift` joins them to ViPi's keyboard). Their four model files (65 MB) are not in git: `scripts/ios-suggest-models.sh` (`scripts/suggest-models.sh ios/Suggest`) downloads them from Vikey at a pinned commit into `ios/Suggest/` and checks their SHA-256; `ios-build.sh`, `ios-type.sh` and `ios-testflight.sh` call it. The keep lists the slip correction never changes are `Resources/keep-words.txt` (Vikey's) and `Resources/keep-words-chat.txt` (ViPi's), shared with the Rust core. The keyboard maps them into memory after it has appeared, never while opening. `ios/Tools/suggest-eval/` is a command-line simulation of scattered touches that measures the slip correction's limits (see its header).

`ios/project.yml` is the XcodeGen spec; the `.xcodeproj`, Info.plists, entitlements and `ios/Core/` are generated and not in git. The keyboard works fully without Full Access; Full Access only enables vibration. Settings go from the app to the keyboard through the App Group `group.dev.t43.vipi`, which the keyboard can only read.

## Website

`site/` is the static page served at [vipi.t43.app](https://vipi.t43.app) (Cloudflare Pages project `vipi`). `scripts/site.sh` assembles `build/site` from it, the README screenshots, the syllable list and a cut-down Pinyin dictionary (`scripts/site-pinyin.py`); `scripts/site.sh deploy` also uploads it, using `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from `.env`. The typing demo in `site/app.js` ports the Telex rules of `TelexEngine.swift`; keep them in step when the engine changes.
