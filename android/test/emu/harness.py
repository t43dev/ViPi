"""ViPi Android keyboard test harness: drives the emulator with adb and checks the text field."""
import re
import subprocess
import sys
import time

SERIAL = None
NONCE = 0
RESULTS = []


def adb(*args, check=False, capture=True):
    cmd = ["adb"] + (["-s", SERIAL] if SERIAL else []) + list(args)
    r = subprocess.run(cmd, capture_output=capture, text=True)
    return r.stdout if capture else ""


def sh(cmd):
    return adb("shell", cmd)


def dump():
    """Ask the IME (debug build) for key positions, field text and mode."""
    global NONCE
    NONCE += 1
    time.sleep(0.6)   # let the last injected tap be handled
    tag = f"{int(time.time())}-{NONCE}"
    adb("logcat", "-c")
    sh(f"am broadcast -a dev.t43.vipi.DUMP -p dev.t43.vipi --es id {tag} >/dev/null")
    for _ in range(30):
        time.sleep(0.1)
        out = adb("logcat", "-d", "-s", "ViPiKeys:I")
        i = out.rfind("begin " + tag)
        if i >= 0 and re.search(r"ViPiKeys: ?mode [A-Z]+\s*$", out[i:], re.M):
            out = out[i:]
            break
    keys, field, mode = {}, None, None
    for line in out.splitlines():
        m = re.search(r"ViPiKeys: ?(.*)$", line)
        if not m:
            continue
        body = m.group(1)
        p = body.rsplit(" ", 2)
        if body.startswith("field "):
            field = body[6:]
        elif len(p) == 3 and p[1].lstrip("-").isdigit() and p[2].lstrip("-").isdigit():
            keys.setdefault(p[0], (int(p[1]), int(p[2])))
        elif body.startswith("mode "):
            mode = body[5:].strip()
    return keys, field, mode


K = {}


def refresh():
    keys, f, m = dump()
    K.clear()
    K.update(keys)
    return f, m


def field():
    return dump()[1]


def mode():
    return dump()[2]


def tap(*names, delay=0.12):
    for n in names:
        if n not in K:
            refresh()
        x, y = K[n]
        sh(f"input tap {x} {y}")
        time.sleep(delay)


def typ(word):
    """Type letters/space/punctuation by key name."""
    for ch in word:
        name = {" ": "space", "\n": "return"}.get(ch, ch)
        if ch.isupper():
            tap("shift")
            name = ch.lower()
        tap(name)


def hold(name, ms=700):
    if name not in K:
        refresh()
    x, y = K[name]
    sh(f"input swipe {x} {y} {x} {y} {ms}")
    time.sleep(0.2)


def drag(a, b, ms=600):
    sh(f"input swipe {a[0]} {a[1]} {b[0]} {b[1]} {ms}")
    time.sleep(0.2)


def clear():
    sh("input keycombination 113 29")  # Ctrl+A
    time.sleep(0.15)
    sh("input keyevent KEYCODE_DEL")
    time.sleep(0.2)


def set_mode(target):
    """target: 'VIETNAMESE'/'ENGLISH' (latin) or 'CHINESE'."""
    m = mode()
    is_zh = m == "CHINESE"
    if (target == "CHINESE") != is_zh:
        tap("mode")
        time.sleep(0.3)


def check(name, got, want):
    ok = got == want
    RESULTS.append((ok, name, got, want))
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  got={got!r} want={want!r}"), flush=True)
    return ok


def summary():
    bad = [r for r in RESULTS if not r[0]]
    print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} passed", flush=True)
    for r in bad:
        print(f"  FAIL {r[1]}: got={r[2]!r} want={r[3]!r}")


def ensure_shown():
    """Make sure ViPi is the IME and its keyboard is showing over the settings test field."""
    if "dev.t43.vipi" not in sh("settings get secure default_input_method"):
        sh("ime set dev.t43.vipi/.ViPiInputMethod")
    if "mInputShown=true" in sh("dumpsys input_method | grep mInputShown"):
        return
    for _ in range(3):
        sh("input keyevent KEYCODE_BACK")
        time.sleep(0.4)
        sh("am start -n dev.t43.vipi/.SettingsActivity")
        time.sleep(1.5)
        sh("input tap 540 760")
        time.sleep(1.5)
        if "mInputShown=true" in sh("dumpsys input_method | grep mInputShown"):
            return
    raise RuntimeError("keyboard does not show")


def fresh(m="VIETNAMESE"):
    ensure_shown()
    refresh()
    if "letters" in K:
        tap("letters")
    clear()
    set_mode(m)
    refresh()
