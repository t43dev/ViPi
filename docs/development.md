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
