<p align="center"><img src="assets/logo-256.png" width="128" alt="ViPi logo"></p>

# ViPi

**Vi**etnamese (Telex) + **Pi**nyin (Chinese) in one macOS menu-bar input tool.

- **Telex** typing with UniKey-style rules: `aa→â aw→ă ee→ê oo→ô ow→ơ uw/w→ư dd→đ`, tones `s f r x j`, `z` clears the tone, typing a key twice undoes it (`ass→as`), free tone order (`tosan→toán`), spell check (invalid words such as `class`, `text` stay as typed), classic or modern tone placement (`hòa`/`hoà`).
- **Pinyin** with a candidate window: full pinyin, `'` separator (`xi'an`), unfinished last syllable (`nih→你好`), initials-only abbreviations (`nh→你好`), whole-sentence suggestion (`woshizhongguoren→我是中国人`), partial selection, full-width punctuation.
- **Control+Shift** cycles Vietnamese → Chinese → English (press both, release without another key).
- **Secure Input Monitor**: shows which app holds macOS Secure Input (the reason input tools suddenly stop typing), with history, PID, path and Show/Quit buttons. The menu-bar icon turns into a lock while it is held.
- **Launch at Login** (on by default, toggle in the menu).

## Install

1. Download `ViPi-x.y.z.zip` from [Releases](../../releases) (or the `ViPi` artifact of the latest CI run), unzip, move `ViPi.app` to `/Applications`.
2. The build is ad-hoc signed, so clear the download quarantine once:
   `xattr -dr com.apple.quarantine /Applications/ViPi.app`
3. Open ViPi and allow it in **System Settings → Privacy & Security → Accessibility**. ViPi starts working within 2 seconds of the grant.

Ad-hoc builds get a new signature every time, so after updating you must remove ViPi from the Accessibility list and add it again. Builds signed with a Developer ID (CI does this when the `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` secrets are set) are notarized: no quarantine step, and the Accessibility grant survives updates.

## Keys

| Mode | Keys |
|---|---|
| Vietnamese | Telex as above; any non-letter ends the word |
| Chinese | `a-z` pinyin (`v` = ü) · `1-9` pick · `Space` pick highlighted · `←/→` move · `-`/`=` or `↑/↓` page · `Enter` type raw pinyin · `Esc` cancel · `Backspace` edit/undo pick |
| Any | `Control+Shift` switch mode |

## Build

macOS 13+, Xcode command line tools:

```sh
swift test                      # engines (also runs on Linux)
VERSION=0.1.0 scripts/build-app.sh   # → build/ViPi.app + build/ViPi-0.1.0.zip
```

CI (`.github/workflows/build.yml`) tests, builds a universal app and uploads it; pushing a `v*` tag publishes a release.

The Pinyin dictionary `Resources/pinyin.tsv` is generated from [rime-ice](https://github.com/iDvel/rime-ice) by `scripts/build_pinyin_dict.py`.

## License

GPL-3.0. Telex rules and vowel tables follow [UniKey](https://www.unikey.org) (GPL); the Pinyin dictionary comes from rime-ice (GPL-3.0).
