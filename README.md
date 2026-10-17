<p align="center"><img src="assets/logo-256.png" width="128" alt="ViPi logo"></p>

# ViPi

**Vi**etnamese (Telex) + **Pi**nyin (Chinese) in one macOS menu-bar input tool.

- **Telex** typing with UniKey-style rules: `aa→â aw→ă ee→ê oo→ô ow→ơ uw/w→ư dd→đ`, tones `s f r x j`, `z` clears the tone, typing a key twice undoes it (`ass→as`), free tone order (`tosan→toán`), spell check (invalid words such as `class`, `text` stay as typed), classic or modern tone placement (`hòa`/`hoà`).
- **Pinyin** with a candidate window: full pinyin, `'` separator (`xi'an`), unfinished last syllable (`nih→你好`), initials-only abbreviations (`nh→你好`), whole-sentence suggestion (`woshizhongguoren→我是中国人`), partial selection, full-width punctuation.
- **Control+Shift** jumps back to the previous input (press both, release without another key); press it twice quickly to move on to the next one (most-recently-used order, like ⌘Space).
- **Secure Input Monitor**: shows which app holds macOS Secure Input (the reason input tools suddenly stop typing), with history, PID, path and Show/Quit buttons. The menu-bar icon turns into a lock while it is held.
- **Launch at Login** (on by default, toggle in the menu).

## Install

1. Download `ViPi-x.y.z.dmg` from [Releases](../../releases), open it and drag **ViPi** onto **Applications**.
2. Open ViPi from Applications and allow it in **System Settings → Privacy & Security → Accessibility**. ViPi starts working within 2 seconds of the grant and adds itself to Login Items.

Releases are signed with a Developer ID and notarized by Apple, so macOS opens them without warnings and the Accessibility grant survives updates. Requires macOS 13 or later (Apple silicon or Intel).

## Keys

| Mode | Keys |
|---|---|
| Vietnamese | Telex as above; any non-letter ends the word |
| Chinese | `a-z` pinyin (`v` = ü) · `1-9` pick · `Space` pick highlighted · `←/→` move · `-`/`=` or `↑/↓` page · `Enter` type raw pinyin · `Esc` cancel · `Backspace` edit/undo pick |
| Any | `Control+Shift` previous mode · twice quickly: next mode |

## Build

macOS 13+, Xcode command line tools:

```sh
swift test                      # engines (also runs on Linux)
VERSION=0.1.0 scripts/build-app.sh   # → build/ViPi.app + build/ViPi-0.1.0.zip (ad-hoc signed)
```

With `SIGN_IDENTITY="Developer ID Application: …"` the script signs with the hardened runtime and makes `build/ViPi-x.y.z.dmg`; with `NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` (App Store Connect API key) it also notarizes and staples the DMG. `scripts/mac-release.sh <version>` does all of this on a build Mac and attaches the DMG to the GitHub release `v<version>`.

CI (`.github/workflows/build.yml`) runs the tests and uploads an unsigned build as an artifact.

The Pinyin dictionary `Resources/pinyin.tsv` is generated from [rime-ice](https://github.com/iDvel/rime-ice) by `scripts/build_pinyin_dict.py`.

## License

GPL-3.0. Telex rules and vowel tables follow [UniKey](https://www.unikey.org) (GPL); the Pinyin dictionary comes from rime-ice (GPL-3.0).
