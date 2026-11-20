# Changelog

What changed in each ViPi release. Download the latest from [Releases](../../releases/latest).

## Unreleased

Android 0.4.0.

### Changed
- **Android: word suggestions, slip correction and keys that follow the sentence,** as on iPhone and iPad (from Vikey; Vietnamese · English typing). The logic is the shared Rust core's, checked against the iPhone keyboard's.
  - The bar offers ways to finish the English word you are typing, ranked by the words before it, and likely next words in English and Vietnamese. Tap one to put it in. While a Vietnamese word is being typed the bar still shows the keys you typed and the word with marks.
  - An English word typed with slips onto neighbouring keys is fixed at the space or the punctuation mark when it is clearly another word: `rhonk` → `think`. The bar shows what the space will put in; tap the quoted word to keep yours. Backspace right after a fix puts your word back and keeps it. Left alone, as on iPhone: words either language knows, Vietnamese spellings, chat shorthand and brands, abbreviations without a vowel, lengthened words, words under three letters or with two capitals, and words stuck to a digit or symbol.
  - On the phone's letter keys, while a word is under way, a touch near the border of two keys types the letter that is likelier next, and a touch in the gap above the space bar after a finished word is a space (`thank you`, not `thanknyou`). In Vietnamese the next Telex key is weighed the same way. The split, wide and floating keyboards of large screens keep their key areas.
  - Two switches in Settings: Word suggestions and Auto-correct typos, both on. Off in web address, email, number and password fields and wherever the app turns suggestions off.
  - The models make the download 53 MB bigger and take 65 MB on the phone. The first time the keyboard opens they are copied out of the app in the background (0.3 s on the emulator); the keyboard works meanwhile, only without suggestions. They are read only after the keyboard has appeared.
- **Android: a pad of big digit keys in number, phone and date fields,** instead of the 123 page. Four columns: the digits, Backspace and the field's action key, plus the marks that field needs (`-` `,` `.` for numbers, `*` `#` `+` for phone numbers, `/` `:` `-` for dates and times). `!?#` opens the 123 page for anything else; a space typed there, or `?123` on the letters page, comes back to the pad. Phones only, upright and turned: the split, wide and floating keyboards of large screens keep the 123 page. Nothing changes on iPhone: in the simulator iOS showed Apple's own number pad in these fields, not a keyboard from an app (not yet checked on a device).
- **Android: the app shows its version and build number** next to its name at the top of the settings screen.

### Fixed
- **iPhone and iPad: the keyboard no longer stays on the 123 page after a number field.** Moving from a number field to a text field without closing the keyboard brings the letters back.
- **iPhone and iPad: Chinese candidates no longer pile on top of each other.** On a device, typing Pinyin past the first syllable (`nih`, `nihao`) drew all candidates in one black smudge at the start of the bar; candidates of two or more characters also kept the width of a single one.

## 0.5.7 · 2026-11-19

macOS 0.5.7. The other platforms get this fix with their next build.

### Fixed
- **A tone key pressed twice to take the mark off stays off** (all platforms, Vietnamese · English typing). Typing `USD` shows `Ú` after the S; pressing S again to get `US` and going on to `USD` no longer turns into `USSD` at the space. The same for `ESP`, `ASP`, `ISP`, `IRS`, which could not be typed at all while typing Vietnamese (`ESP` gave `ÉP`, `ESSP` stayed `ESSP`). The rule: a doubled s, f, r, x or j right before a consonant, with no vowel after it, in a word the English list does not know. Known words keep both letters (`USSR`, `pass`, `class`), so do lowercase plurals (`quaffs`) and everything typed after the keyboard has switched to English. For a real doubled letter in such a word press the key three times, as Telex always worked: `USSSD` → `USSD`, `ISSSN` → `ISSN`. This takes back the `ussd` change of 0.5.5.

## 0.5.6 · 2026-11-18

macOS 0.5.6 and Android 0.3.7. The iPhone and iPad changes are in TestFlight; HarmonyOS gets its share with its next store build.

### Changed
- **iPhone and iPad: the 123 and #+= pages go back to letters after a space or an apostrophe,** like the Apple keyboard. Number fields stay on the page you chose.
- **A doubled tone key is read more carefully** (all platforms). It counts as an undo only right before a consonant and when the word then reads as English: `tesstflight` → `testflight`, `gesstures` → `gestures`. Real doubled letters stay, also in words the built-in list does not know: `correlate`, `assail`, `riffle`. Checked against a 236,000-word dictionary: version 0.5.5 changed 743 of them in the English state, now 1.

- **iPhone and iPad: word suggestions, slip correction and keys that follow the sentence** (from Vikey; Vietnamese · English typing).
  - The bar offers ways to finish the English word you are typing, ranked by the words before it, and likely next words in English and Vietnamese. Tap one to put it in.
  - An English word typed with slips onto neighbouring keys is fixed at the space or the punctuation mark when it is clearly another word: `rhonk` → `think`. The bar shows what the space will put in; tap the quoted word to keep yours. Backspace right after a fix puts your word back and keeps it. Left alone: words either language knows, Vietnamese spellings, a list of chat shorthand and brands, abbreviations without a vowel, lengthened words (`oiii`), words under three letters or with two capitals, and words stuck to a digit or symbol. The fix must also fit the sentence. In a simulation of touches scattered 8 pt around the keys, unlisted chat shorthand typed right was changed 0.16% of the time, and 61 of 70 mistyped English words were fixed, none wrongly.
  - While a word is under way, a touch near the border of two keys types the letter that is likelier next, and a touch in the gap above the space bar after a finished word is a space (`thank you`, not `thanknyou`). In Vietnamese the next Telex key is weighed the same way.
  - Two switches in the app: Word suggestions and Auto-correct typos. Off in web address, email and number fields and wherever the app turns autocorrection off. The models (65 MB more in the app) are read only after the keyboard has appeared.
- **Chat abbreviations and teencode stay as you mean them** (all platforms). Abbreviations with đ come out with the đ wherever it stands: `bdds` → `bđs`, `sddt` → `sđt`, `vndd` → `vnđ`, `BDDS` → `BĐS` (before, only `đc`, `đt`, `đk`). Toned chat spellings are no longer put back to their keys at the space: `gòi`, `hỉu`, `chời`, `zậy`, `dzô` and about 290 more, in `Resources/autoswitch-vi-chat.tsv`. English words typed with the same keys stay English (`gets`, `fair`, `zoo`), and so do `HDD` and `DDR`.

- **Enter in a search or address field sends what you see** (all platforms; the Go and Search keys and web address fields on phones, the browser's address bar on the Mac). A word that still shows exactly the keys you typed is not changed at that Enter, so `ver` + Enter opens the page the browser was offering instead of searching for `vẻ`. Type a space first to have the word fixed. Enter in other fields (a new line, Send) still fixes the word, and a word that already changed on screen (`púh`) is still put back.

### Fixed
- **Deleting the digits of a code brings Vietnamese back** (all platforms): after `a1` and two Backspaces, `vieejt` gives `việt` again.
- **Android and HarmonyOS:** an English word in progress is forgotten when the app empties the text box right after a key (Send in chat apps), so the next word is not judged together with it.
- **HarmonyOS:** the second letter of a sentence is no longer capitalised too (`HEllo`); a word in progress survives the app changing its Enter key while you type (chat boxes that enable Send once there is text); the settings app no longer copies 23 MB of dictionaries into its own storage and removes the copy earlier versions left there.

### Faster
- **iPhone and iPad:** each closed keyboard gives its views back. Measured in the simulator after 26 openings: 26 sets of keyboard views alive before, 1 now.
- **iPhone and iPad:** a key press redraws only that key, the key callout is a small view, and pinyin candidates reuse their buttons from one key to the next. Not measured on a device.

## 0.5.5 · 2026-11-18

macOS 0.5.5. The same fixes reach iPhone, iPad, Android and HarmonyOS with their next store builds.

### Fixed
- **Doubled letters stay when nothing else looks like Telex** (all platforms): `ussd` and `Ussd` no longer become `usd`, and acronyms typed after VE has switched to English keep both letters (`USS`, `USSD`). A doubled tone key still undoes the mark in words like `tesstflight` → `testflight`.

## 0.5.4 · 2026-11-18

macOS 0.5.4. The iPhone, iPad, Android and HarmonyOS fixes below reach those apps with their next store builds.

### Changed
- **Backspace after an automatic switch now works in two steps** (all platforms, following Vikey 1.0.33). The first Backspace only takes the space back and keeps the corrected word, so you can add a comma: `được ` ⌫ `,` gives `được,`. A second Backspace right after it puts the word back as you typed it. Typing a letter after the first Backspace goes on with the corrected word, so a missing tone can still be added: `vây ` ⌫ `j` gives `vậy`.

### Fixed
- **Letters typed right after a digit are no longer lost in Vietnamese** on Android, iPhone and iPad: `abc1def`, `h2o` and `65w` come out whole.
- **An English word ended by a digit or a symbol comes back as typed, like with a space** (all platforms): `pass1`, `affair-based` and `access_token` no longer lose a doubled letter.
- **A doubled tone key typed on purpose stays undone in English words** (all platforms): `tesstflight` gives `testflight` and `posstgres` gives `postgres`, also after VE has switched to English. Names with real doubled letters stay as typed: `currentState`, `boss`.
- **Typing a digit while the pinyin has no candidate no longer swallows the keys that follow** (all platforms): `java2` in Chinese mode gives `java2`.
- **Double-tapping Shift at the start of a sentence turns on caps lock** (Android, iPhone, iPad, HarmonyOS). Shift was already on there, so it took three taps.
- **Sliding to the next key and back types the key under your finger,** not the neighbour (Android, iPhone, iPad, HarmonyOS).
- **Number, phone and date fields stay on the number keys after a space** (Android, HarmonyOS).
- **Android:** a dead key on a hardware keyboard (`^`, `´`, `~` on international layouts) no longer crashes the keyboard; the clipboard history skips passwords marked by password managers on Android 12 and earlier, and copied images or files; two spaces in a password field stay two spaces.
- **iPhone and iPad:** the keyboard no longer comes up as a blank panel after about a day of use (it ran out of address space because the drawings of earlier keyboards were never released, then crashed when opening); it no longer crashes when you type a space and then tap 123 before the first finger has lifted; moving the cursor or sending a message while typing English no longer changes text in the wrong place; a field that opens on the number keys no longer jumps back to them after every letter.
- **HarmonyOS:** settings changed in the app are no longer overwritten by the keyboard (and the other way round); Clear learned words works when learning is off, and the count is current; typing Chinese lays out only the candidates you can see; the keyboard stops asking for vibration on every key when the system refuses it.
- **macOS:** after the system pauses the keyboard listener, the word in progress is dropped, so the next tone key cannot edit the wrong letters.

## Android 0.3.6 · 2026-11-11

### Fixed
- **Sending a message right after typing no longer brings the last word back.** In apps that clear the text box the moment you tap Send (such as Telegram), the next word you typed came out with the previous one in front of it.

## Android 0.3.5 · 2026-11-11

### Changed
- **Keys are sized like the iPhone keyboard:** a little shorter with more room between rows (43 dp, or 45 dp on phones 410 dp and wider), and a little more space at the edges. In landscape the keys are lower so more of the app stays visible.

### Fixed
- **Fast typing no longer lands on the key next to the one you meant.** A slight slide while typing now keeps the key you touched; slide more than half a key to change your mind.

## Android 0.3.4 · 2026-11-09

### Changed
- **ViPi for Android no longer goes online.** The built-in updater is gone, and with it the internet, install and notification permissions. The only permission left is vibration, so what you type cannot leave your phone.
- **Learned words and settings are no longer included in Android cloud backups.**

### Fixed
- **The Settings screen no longer slides under the status bar** on Android 15 and later, and section titles are readable in dark mode.

### Added
- **A privacy policy,** linked from Settings → About and from the website.

## Android 0.3.3 · 2026-11-08

### Added
- **ViPi for Android updates itself.** Once a day it checks GitHub, downloads a new version on Wi-Fi, confirms it is signed by the ViPi developer and installs it while the keyboard is closed. Android asks you to confirm the first time. Turn it off, or check by hand, under **Settings → Updates**. To do this the app now has internet access, used only for this update check; what you type stays on your phone.

### Changed
- **The website shows the right version for your device:** macOS, Android or HarmonyOS, with a key to switch to another.

## 0.5.3 · 2026-11-08

macOS 0.5.3 and Android 0.3.2.

### Changed
- **VE fixes the word before when it becomes clear you are writing English.** `this makes` no longer leaves `thí makes`. Common Vietnamese words stay: `bên server`, `cả server`.
- **English words keep every letter.** `currentState`, `mirrorless`, `cheese` and `ASUS` no longer lose a doubled letter, and names like `Momo` stay as typed.
- **18,000 more English word forms** (`resets`, `quests`), so they no longer turn into something like `rêts`.
- **Caps Lock Vietnamese works under VE.** `THOONG` becomes `THÔNG`, while `HDD` and `DDR` stay.
- **`đc`, `đt` and `đk` are typed as chat shorthand under VE.** Units and codes stay as typed: `65w`, `abc1def`.

## 0.5.2 · 2026-11-06

### Fixed
- **The dropdowns in Settings respond to the mouse again.** Since 0.5.0, clicking Language, Appearance, Tone placement or Characters did nothing.

## 0.5.1 · 2026-11-06

### Changed
- **ViPi's interface now starts in Vietnamese** instead of following the macOS language. Choose English or 简体中文 in **Settings → General**, and ViPi remembers your choice. If you never chose a language, the interface turns Vietnamese after this update.
- The language setting is now labelled in all three languages, Ngôn ngữ · Language · 语言, so you can find it whichever language is showing. The list runs Tiếng Việt, English, 简体中文.

## 0.5.0 · 2026-11-06

### Changed
- **Vietnamese and English now work as one input, VE, and this is on by default.** The menu bar shows **VE** instead of VI or EN, the switch shortcut moves between VE and Chinese, and ViPi follows what you type. To use Vietnamese or English on their own, turn off **Settings → Vietnamese → Switch between Vietnamese and English automatically**.
- The 5-second hold after switching by hand is gone: VE has no separate Vietnamese or English to hold, and a Backspace right after an automatic switch still undoes it.
- While VE is on, text shortcuts work in both languages if either switch in **Settings → Text Shortcuts** is on.
- **A new look built on Liquid Glass.** Settings, About, the Secure Input Monitor, the menu-bar icon, the input switch banner and the Chinese candidate panel are all redrawn, in light and dark. Macs older than macOS 26 get the same layout with standard translucent materials.
- **First-run screen:** ViPi now walks you through Accessibility permission, your input and the switch shortcut.
- The Text Shortcuts list now uses all the space in its tab, and the menu shows symbols instead of emoji.
- **Automatically install updates** now lives only in **Settings → General**; About links to it.

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
