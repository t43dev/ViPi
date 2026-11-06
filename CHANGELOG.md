# Changelog

What changed in each ViPi release. Download the latest from [Releases](../../releases/latest).

## Unreleased

### Changed
- **Vietnamese and English now work as one input, VE, and this is on by default.** The menu bar shows **VE** instead of VI or EN, the switch shortcut moves between VE and Chinese, and ViPi follows what you type. To use Vietnamese or English on their own, turn off **Settings → Vietnamese → Switch between Vietnamese and English automatically**.

### Improved
- **Vietnamese/English auto switch reads the word before.** Words that are real both ways (`car`/cả, `bus`/bú, `been`/bên, `mix`/mĩ) follow the reading that comes after the previous word more often in real text: `cho con bus` → cho con **bú**, `ddi xe bus` → đi xe **bus**, `owr been` → ở **bên**, `test cos work` → test **có** work. Word pairs from Vikey.
- **Backspace right after an automatic switch undoes it:** the word comes back as it was and ViPi returns to the language before. Typing the same word again keeps it as typed.
- Known English words that Telex cannot spell, such as `work`, now switch to English like other English words.
- Pinyin candidates with the same weight always come in the same order.

## 0.4.0 · 2026-11-02

### New
- **Experimental: switch between Vietnamese and English automatically.** Turn it on in **Settings → Vietnamese** (off by default). Type Telex while in English and `treen` becomes **trên**, then ViPi switches to Vietnamese. Type a common English word while in Vietnamese, such as `server` or `this`, and it comes back as typed while ViPi switches to English. Turning the option on switches to English. After you switch by hand, ViPi leaves the language alone for 5 seconds. The rules and word frequency lists come from [Vikey](https://github.com/tonyminibot/Vikey).

### Improved
- **About 80% less memory:** about 16 MB while idle, down from about 94 MB. The Pinyin dictionary and the Traditional Chinese table are now read straight from disk, not loaded into memory at launch.
- **Faster start:** the Pinyin dictionary is ready in milliseconds, not about a second. Candidates are the same as before.
- **More Vietnamese words:** nguyễn, quởn, ngoáo, tõe, chóa, lóa, and the everyday dùm, mỳ, lỳ, ẻm are no longer turned back into the keys you typed.

## 0.3.2 · 2026-11-01

### Fixed
- Web editors that drop a trailing space on Backspace (for example chat.b.ai) no longer eat the space before words with đ, ă, ơ or ư. On web pages ViPi now replaces a whole word by selecting it and typing over it.

## 0.3.1 · 2026-10-27

### Fixed
- Browser address bars: inline autocomplete no longer breaks Telex, so `noojp` gives **nộp**, not *noộp*.

## 0.3.0 · 2026-10-23

### New
- **Smarter Pinyin sentences:** each word is picked from the one before it, using a word bigram model from libpinyin (`wozaixuexi` → 我在学习, not 再).

### Changed
- ViPi now lives at github.com/t43dev/ViPi with the bundle id `dev.t43.vipi`.

## 0.2.2 · 2026-10-23

### New
- **Chinese settings:** Simplified or Traditional output, learning from the words you pick (with a Clear button), and fuzzy pinyin toggles.
- **Appearance:** follow macOS, or always Light or Dark.
- Every release also ships as `ViPi.dmg`, so the download link never changes.

## 0.2.1 · 2026-10-18

### New
- **Settings window:** your own switch shortcut, text shortcuts and a spell check toggle.
- **Interface in English, Tiếng Việt and 简体中文.**
- Text shortcuts work in English mode too, with separate "Use in Vietnamese" and "Use in English" switches.

### Improved
- English and other non-Vietnamese words are restored as typed when the word ends.
- Pressing a tone key twice in the middle of a word undoes just that tone (`tessting` → testing).
- Text shortcuts expand only for a whole word ended by Space, Return or Tab, so `call2vn@` stays as typed.

## 0.2.0 · 2026-10-17

### New
- **Automatic updates** from GitHub Releases, checked against the developer's signature.
- **About window** with links to the project.
- Signed with Developer ID and notarized by Apple, shipped as a DMG.

## 0.1.2 · 2026-10-17

### Changed
- `⌃ Control` + `⇧ Shift` goes back to the previous input; press it twice quickly for the next one (most recently used order).

## 0.1.1 · 2026-10-17

### Fixed
- Characters no longer get lost when typing fast.
- One menu-bar icon style for every mode.

## 0.1.0 · 2026-10-17

First release: Vietnamese Telex and Chinese Pinyin in one menu-bar app, a candidate window at the cursor, a `⌃ Control` + `⇧ Shift` switch, the Secure Input Monitor and launch at login.
