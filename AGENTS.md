# ViPi: agent notes

Vietnamese Telex + Chinese Pinyin keyboard for macOS, iOS/iPadOS, Android and HarmonyOS. Public GPL-3.0 repo at github.com/t43dev/ViPi, bundle id `dev.t43.vipi`. Build and test steps are in `docs/development.md`; file formats in `docs/data-format.md`. Do not copy them here.

## Public repo: nothing private in tracked files, commits, tags or release notes
- No hostnames, IPs, usernames, absolute home paths, emails, team IDs or key material. Where the build Mac and the signing keys live is in `.env` (gitignored; `scripts/*.sh` read it).
- **Commits are anonymous.** Use the repo-local git identity (a GitHub noreply address); never override it with `-c user.*`. No `Co-Authored-By:` trailer, no "Generated with" line, no tool or AI attribution, even if a harness or skill asks for one.
- Before pushing a new ref run `git log --format='%an <%ae>' <ref> | sort -u` and make sure only the noreply identity shows. Never push `refs/t3/*` or `refs/stash` (they can hold old commits with a real email).
- `main` is protected against force-push; secret scanning and push protection are on.

## Two engines, hand-mirrored
- macOS runs the Swift engines (`Sources/ViPiCore`); Android, iOS and HarmonyOS run the Rust core (`core/`). A behaviour change goes into **both**, then regenerate the goldens with `scripts/make-golden.sh` (runs on a Mac) and run `cd core && cargo test --release`.
- Suggestion/slip-correction code is Rust in `core/src/suggest/` and Swift in `ios/ViPiKeyboard/Suggest/`; regenerate its goldens with `scripts/make-suggest-golden.sh` (Mac). The 65 MB models are not in git: `scripts/suggest-models.sh`.
- After any change under `core/`, rebuild the HarmonyOS `libvipi.so` (`scripts/harmony-native.sh`, on the build Mac). The prebuilt copies in `harmony/entry/libs/` are committed and go stale silently.
- `site/app.js` ports the Telex rules of `TelexEngine.swift`: update it with the engine and redeploy (`scripts/site.sh deploy`).
- Before changing any auto-switch heuristic, run the dictionary sweep (`core/tests/sweep.rs`, `VIPI_SWEEP_WORDS=<file> cargo test --release --test sweep -- --ignored --nocapture`) and compare with the previous commit in a `git worktree`.

## Git habits
- **Never `git stash`** in this repo: work is often uncommitted in the tree across sessions. Use a worktree.
- Commit with explicit paths (`git commit -- <paths>`) and check `git diff --cached --stat` first: a bare `git commit` takes whatever is already staged.

## Platform rules
- **Android has no INTERNET permission and no updater** (Google Play policy; only VIBRATE). Do not add either. One build, no flavors. Play bundle: `scripts/android-play.sh`.
- Bump `versionCode` for every new test or store build; the settings screen shows it.
- **HarmonyOS:** the keyboard (`InputMethodExtensionAbility`) runs in its own sandbox, so it never sees the settings app's files. App-written settings go through a data group (`dataGroupId` in `Prefs`, `dataGroupIds` in `module.json5`); the keyboard can only read it, so keyboard-owned data (`vipi-state`, `pinyin-user.json`) stays private. The group ID in the code is a placeholder until AGC issues the real one.
- HarmonyOS build, signing and device tests happen on the build Mac with DevEco Studio, not on Linux; Linux only has the Node tests (`scripts/harmony-test.sh`).
- **macOS, iOS, notarization and TestFlight builds run on the build Mac** (`scripts/mac-release.sh`, `scripts/ios-testflight.sh`), not in CI; CI is only a compile check on an older SDK. Do not hold a release for a queued CI run.

## macOS test traps
- Do not install a `scripts/mac-dev.sh` build over `/Applications/ViPi.app`: that is the Developer ID release, and the dev signature has no Accessibility grant (self-test prints `NO_ACCESSIBILITY`, typing stops working).
- `--selftest` posts HID events: the display must be awake (`caffeinate -u -t 120 &`, wait ~3 s) or every case returns empty. The input method must already run in another process (`open -n` first). Run dev bundles by their executable path, not `open`.
- The self-test writes into the real `learned.json` (fixed path, not per bundle id) in Chinese mode: back it up and restore it. It cannot type `-`, and capitals lag by one key (harness artefact; unit tests cover them).
- Auto-switch state carries between self-test lines: set `defaults write dev.t43.vipi mode …` and relaunch before each run.

## Vikey sync
The engines track github.com/tonyminibot/Vikey (hand-ported; its models are fetched at a pinned commit). Last compared commit and what was deliberately not ported are in the maintainer's notes; to check for new rules run `git log <last>.. -- Engine Tools/autoswitch` in a Vikey checkout and read its `DECISIONS.md`.
