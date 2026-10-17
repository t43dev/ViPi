<p align="center"><img src="assets/logo-256.png" width="128" alt="ViPi logo"></p>

<h1 align="center">ViPi</h1>

<p align="center"><b>Vi</b>etnamese Telex + <b>Pi</b>nyin — one macOS input tool for people who type both.</p>

<p align="center"><b>English</b> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.zh-CN.md">简体中文</a></p>

> **Alpha.** ViPi is new: expect rough edges and please report them in [Issues](../../issues).

## Why ViPi

I type Vietnamese and Chinese every day, and macOS had no sensible way to do both. The usual setup is a Vietnamese input tool, the Apple Pinyin input source and English, then constant hopping between three input sources and two tools that fight over the keyboard. ViPi puts Telex and Pinyin in one small menu-bar app with one shortcut, so switching language takes a single keystroke.

## Features

- **Vietnamese (Telex)** with UniKey-style rules: `aa→â aw→ă ee→ê oo→ô ow→ơ uw/w→ư dd→đ`, tones `s f r x j`, `z` clears the tone, typing a key twice undoes it (`ass→as`), tones can come anywhere in the word (`tosan→toán`), spell check keeps English words as typed (`class`, `text`), classic or modern tone placement (`hòa` / `hoà`). Tested end to end on a real Mac with all 8,329 valid syllables typed at 8–12 ms per key without a single lost key.
- **Chinese (Pinyin)** with a candidate window at the cursor: full pinyin, `'` separator (`xi'an`), unfinished last syllable (`nih→你好`), initials-only abbreviations (`nh→你好`), whole-sentence suggestions (`woshizhongguoren→我是中国人`), partial selection, full-width punctuation.
- **Control+Shift** jumps back to the previous input; press it twice quickly to move on to the next one (most-recently-used order, like ⌘Space).
- **Secure Input Monitor** shows which app holds macOS Secure Input, the usual reason every input tool suddenly stops working, with history, PID, path and Show/Quit buttons. The menu-bar icon turns into a lock while it is held.
- **Launch at Login**, on by default.
- **Private**: ViPi has no network code. Keystrokes are processed on your Mac and never leave it.

## Install

1. Download `ViPi-x.y.z.dmg` from [Releases](../../releases), open it and drag **ViPi** onto **Applications**.
2. Open ViPi and allow it in **System Settings → Privacy & Security → Accessibility**. ViPi starts working within 2 seconds of the grant.
3. Turn off other Vietnamese input tools (UniKey, EVKey, GoNhanh…) and use the plain **ABC** input source, so only ViPi changes what you type.

Releases are signed with a Developer ID and notarized by Apple, so macOS opens them without warnings and the Accessibility grant survives updates. Requires macOS 13 or later, Apple silicon or Intel.

## Keys

| Mode | Keys |
|---|---|
| Vietnamese | Telex as above; any non-letter ends the word |
| Chinese | `a-z` pinyin (`v` = ü) · `1-9` pick · `Space` pick highlighted · `←/→` move · `-`/`=` or `↑/↓` page · `Enter` type raw pinyin · `Esc` cancel · `Backspace` edit/undo pick |
| Any | `Control+Shift` previous input · twice quickly: next input |

## Build

macOS 13+, Xcode command line tools:

```sh
swift test                           # engines (also runs on Linux)
VERSION=0.1.0 scripts/build-app.sh   # → build/ViPi.app + build/ViPi-0.1.0.zip (ad-hoc signed)
```

With `SIGN_IDENTITY="Developer ID Application: …"` the script signs with the hardened runtime and makes `build/ViPi-x.y.z.dmg`; with `NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` (App Store Connect API key) it also notarizes and staples the DMG. `scripts/mac-release.sh <version>` does all of this on a build Mac and attaches the DMG to the GitHub release `v<version>`.

`open -n /Applications/ViPi.app --args --selftest <words.txt> <out.txt> [gapMs] [holdMs] [variant]` types every word through the running ViPi with overlapping key presses and reports any word that comes out wrong.

CI (`.github/workflows/build.yml`) runs the tests and uploads an unsigned build as an artifact.

The Pinyin dictionary `Resources/pinyin.tsv` is generated from [rime-ice](https://github.com/iDvel/rime-ice) by `scripts/build_pinyin_dict.py`.

## License

GPL-3.0. Telex rules and vowel tables follow [UniKey](https://www.unikey.org) (GPL); the Pinyin dictionary comes from [rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0). The logo's red and gold, V–P ligature and star are explained in [assets/logo-meaning.md](assets/logo-meaning.md).
