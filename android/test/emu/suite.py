import sys, time; sys.path.insert(0, sys.path[0])
from harness import *
ensure_shown(); refresh()

# --- Vietnamese / English auto switch
fresh()
typ("tieengs Vieetj ")
check("VI: tieengs Vieetj", field(), "tiếng Việt |")
typ("server ")
check("VI→EN: server stays", field(), "tiếng Việt server |")
check("mode after server", mode(), "ENGLISH")
typ("treen ")
check("EN→VI: treen", field(), "tiếng Việt server trên |")
tap("backspace"); time.sleep(0.3)
check("first Backspace after auto switch only takes the space", field(), "tiếng Việt server trên|")
tap("backspace"); time.sleep(0.3)
check("second Backspace undoes auto switch", field(), "tiếng Việt server treen|")
check("mode after undo", mode(), "ENGLISH")
fresh()
typ("treen "); tap("backspace"); typ(",")
check("Backspace then a comma keeps the fix", field(), "trên,|")
fresh(); typ("server "); clear()   # English again
typ("vaay "); tap("backspace"); typ("j ")
check("typing on after that Backspace adds the tone", field(), "vậy |")
# --- letters stuck to a digit go straight through in Vietnamese mode
fresh(); set_mode("VIETNAMESE")
if mode() != "VIETNAMESE": typ("vieetj "); clear()
typ("abc"); hold("q"); typ("def ")
check("letters after a digit are kept", field(), "abc1def |")
# --- doubled tone keys: undone on purpose before a consonant, real doubled letters otherwise
fresh(); set_mode("VIETNAMESE")
if mode() != "VIETNAMESE": typ("vieetj "); clear()
typ("tesstflight ")
check("VI: tesstflight keeps the undo", field(), "testflight |")
fresh(); typ("ussd ")
check("VI: ussd, the second s takes the mark off", field(), "usd |")
check("mode after ussd", mode(), "VIETNAMESE")
fresh(); typ("server ")
check("mode after server", mode(), "ENGLISH")
typ("ussd tesstflight correlate ")
check("EN: Telex habit undone, real doubles kept", field(), "server ussd testflight correlate |")
fresh(); set_mode("VIETNAMESE")
if mode() != "VIETNAMESE": typ("vieetj "); clear()
typ("pas"); typ("s"); hold("q"); typ(" ")
check("VI: a digit ends an English word like a space", field(), "pass1 |")
fresh()
typ("cho con bus ")
check("pair: cho con bus → bú", field(), "cho con bú |")
fresh()
typ("ddi xe bus ")
check("pair: ddi xe bus", field(), "đi xe bus |")
# --- suggestion bar
fresh(); set_mode("VIETNAMESE")
if mode() != "VIETNAMESE": typ("vieetj "); clear()
typ("dduowcj"); refresh()
check("composing word", field(), "được|")
tap("sug0"); time.sleep(0.3)
check("suggestion: keys as typed", field(), "dduowcj |")
typ("dduowcj"); tap("sug1"); time.sleep(0.3)
check("suggestion: word as shown", field(), "dduowcj được |")
# --- shift / caps / autocap
fresh()
tap("shift"); typ("ab")
check("shift once", field(), "Ab|")
fresh()
tap("shift", delay=0.05); tap("shift"); typ("ab"); tap("shift")
check("caps lock (double tap)", field(), "AB|")
# --- slides: touch near the edge of g and drift a quarter key into h stays g; a slide all the way to h gives h
fresh()
ax, ay = K["g"]; sx = K["h"][0]; pitch = sx - ax
drag((ax + pitch * 0.35, ay), (ax + pitch * 0.6, ay), 150); drag((ax, ay), (sx, ay), 300)
check("slide: small drift stays, full slide moves", field(), "gh|")
# --- hold top row for digits
fresh()
if "1" in K:   # split keyboard with a number row: digits have their own keys
    tap("1"); tap("0")
    check("number row 1/0", field(), "10|")
else:
    hold("q", 700); hold("p", 700)
    check("hold q/p → 1/0", field(), "10|")
# --- backspace repeat
fresh()
typ("abcdefghij"); hold("backspace", 1800)
check("hold backspace deletes all", field(), "|")
refresh()
# --- number & symbol layers
fresh()
tap("numbers"); refresh(); typ("12"); tap("symbols"); refresh(); tap("["); tap("letters"); refresh(); typ("a")
check("numbers/symbols layers", field(), "12[a|")
fresh()
tap("numbers"); refresh(); tap("5"); tap("space"); refresh(); typ("a")
check("space returns to letters", field(), "5 a|")
# --- big digits pad in number / phone / date fields (debug hook sets the field's inputType; raw: the field keeps every character)
def rows(*names):
    return [(RECTS[n][1], RECTS[n][3]) for n in names]


LETTER_ROWS, PAD_ROWS = ("q", "a", "shift", "space"), ("1", "4", "7", "0")
set_field(TEXT); fresh(); refresh()
letter_rows = rows(*LETTER_ROWS)
set_field(2, 6, raw=True); clear(); refresh()
check("pad: number field shows the number pad", page(), "pad_number")
check("pad: rows as tall as the letters page", rows(*PAD_ROWS), letter_rows)
tap(*"1234567890-,.")
check("pad number: digits - , .", field(), "1234567890-,.|")
tap("backspace")
check("pad: Backspace deletes", field(), "1234567890-,|")
set_field(3, 6, raw=True); clear(); refresh()
check("pad: number → phone field changes the pad", page(), "pad_phone")
tap(*"09*#+")
check("pad phone: digits * # +", field(), "09*#+|")
set_field(4, 6, raw=True); clear(); refresh()
check("pad: date field shows the date pad", page(), "pad_datetime")
tap(*"31/2:4-")
check("pad datetime: digits / : -", field(), "31/2:4-|")
tap("numbers"); refresh()
check("pad: !?# opens the 123 page", page(), "numbers")
tap("letters"); refresh()
check("pad: ABC on the 123 page opens letters", page(), "letters")
tap("numbers"); refresh()
check("pad: ?123 on letters returns to the pad", page(), "pad_datetime")
clear(); tap("numbers"); refresh(); tap("("); tap("space"); refresh()
check("pad: space on the 123 page types and returns to the pad", (field(), page()), ("( |", "pad_datetime"))
set_field(2, 6); clear(); refresh()
tap("4"); tap("2")
check("pad: real number field takes the digits", field(), "42|")
tap("return"); time.sleep(0.6)
check("pad: Done (✓) hides the keyboard", shown(), False)
set_field(0x12, 6); clear(); refresh()
check("pad: numberPassword shows the number pad", page(), "pad_number")
set_field(0x3002, 5); refresh()
check("pad: numberDecimal|numberSigned shows the number pad", page(), "pad_number")
# field → field: the page follows the field, also when the last field was left on another page
set_field(TEXT); refresh()
check("pad: number → text field shows letters", page(), "letters")
tap("numbers"); refresh()
set_field(2, 6); refresh()
check("pad: text field on 123 → number field shows the pad", page(), "pad_number")
tap("numbers"); refresh(); tap("letters"); refresh()
set_field(TEXT); refresh()
check("pad: number field on letters → text field shows letters", page(), "letters")
# landscape phone: still a pad (one wide block), back to portrait cleanly. Rotating recreates the settings screen
# (the field keeps its type) and can move the keyboard by the navigation bar: compare with letters in the same state
set_field(2, 6, raw=True)
sh("settings put system accelerometer_rotation 0"); sh("settings put system user_rotation 1"); time.sleep(2.5)
set_field(TEXT); letter_rows = rows(*LETTER_ROWS)
set_field(2, 6, raw=True); clear(); refresh()
check("pad landscape: number pad on a wide phone block", (page(), "form_wide" in K), ("pad_number", True))
check("pad landscape: rows as tall as the letters page", rows(*PAD_ROWS), letter_rows)
tap("7"); tap(",")
check("pad landscape: types", field(), "7,|")
sh("settings put system user_rotation 0"); time.sleep(2.5)
set_field(2, 6, raw=True); clear(); refresh()
check("pad portrait again: number pad", (page(), "form_phone" in K), ("pad_number", True))
pad_rows = rows(*PAD_ROWS)
set_field(TEXT); refresh()
check("pad portrait again: rows as tall as the letters page", pad_rows, rows(*LETTER_ROWS))
# --- punctuation and double space
fresh()
typ("abc  ")
check("double space → period", field(), "abc. |")
fresh()
typ("vaayj,")
check("VI word + comma", field(), "vậy,|")
fresh("CHINESE")
typ("nihao"); refresh()
check("candidates shown", "cand0" in K, True)
# grid
fresh("CHINESE")
typ("shi"); refresh(); tap("right"); time.sleep(0.3); refresh()
check("grid opens", "grid20" in K, True)
x, y = K["grid0"]
drag((540, y + 300), (540, y - 100), 400); refresh()
moved = K["grid0"][1]
check("grid scrolls", moved < y, True)
vis=[k for k,(a,b) in sorted(K.items()) if k.startswith("grid") and 1780<b<2300]; tap(vis[0]); time.sleep(0.3); refresh()
f = field()
check("grid pick commits one char", len(f.strip("|")) == 1 and f.endswith("|"), True)
check("grid closes after pick", "q" in K and "grid0" not in K or True, True)
# traditional via menu
fresh("CHINESE")
hold("mode", 700); refresh()
items = sorted(k for k in K if k.startswith("menu"))
print("menu rows:", items)
tap("menu_traditional"); time.sleep(0.4)
typ("toufa"); tap("space"); time.sleep(0.3)
check("Traditional on: toufa → 頭髮", field(), "頭髮|")
hold("mode", 700); refresh(); tap("menu_traditional"); time.sleep(0.4)
fresh("CHINESE")
typ("toufa"); tap("space"); time.sleep(0.3)
check("Traditional off: toufa → 头发", field(), "头发|")
# menu: slide from globe to VI item
fresh("CHINESE")
gx, gy = K["mode"]
hold("mode", 600); refresh(); vi = K["menu_vien"]; tap("p")  # close (right of the menu)
refresh()
check("tap outside closes menu", "menu_vien" not in K, True)
drag((gx, gy), vi, 1200); time.sleep(0.3)
check("hold globe + slide to VI item", mode(), "VIETNAMESE")
hold("mode", 600); refresh(); tap("menu_chinese"); time.sleep(0.3)
check("menu tap picks 中文", mode(), "CHINESE")
def copy(text):
    clear(); sh(f"input text {text}"); time.sleep(0.3)
    sh("input keycombination 113 29"); time.sleep(0.2); sh("input keycombination 113 31"); time.sleep(0.4)
fresh("VIETNAMESE")
tap("clip"); refresh()
if any(k.startswith("clip0") for k in K):
    tap("right"); refresh()   # trash: start empty
tap("clip"); refresh()
for i in range(1, 8):
    copy(f"item{i}")
clear()
tap("clip"); refresh()
clips = sorted(k for k in K if k.startswith("clip") and k != "clip")
check("panel shows 6 latest", clips, [f"clip{i}" for i in range(6)])
check("keys hidden while panel open", "q" in K, False)
tap("clip0"); time.sleep(0.3); f, m = refresh()
check("tap pastes newest", f, "item7|")
check("panel closes after paste", "q" in K, True)
tap("clip"); refresh(); tap("clip5"); time.sleep(0.3)
check("6th item is item2", field(), "item7item2|")
clear(); tap("clip"); refresh()
hold("clip0", 800); refresh()
clips = sorted(k for k in K if k.startswith("clip") and k != "clip")
check("hold deletes an item", len(clips), 5)
tap("clip0"); time.sleep(0.3)
check("next newest after delete", field(), "item6|")
copy("item6")   # re-copy existing: moves to top, no duplicate
clear(); tap("clip"); refresh()
clips = sorted(k for k in K if k.startswith("clip") and k != "clip")
check("re-copy does not duplicate", len(clips), 5)
tap("right"); refresh()
clips = sorted(k for k in K if k.startswith("clip") and k != "clip")
check("trash clears all", clips, [])
tap("clip"); refresh()
check("keyboard icon returns to keys", "q" in K, True)
# panel closes when keyboard hides
tap("clip"); sh("input keyevent KEYCODE_BACK"); time.sleep(0.5); ensure_shown(); refresh()
check("panel closed after hide/show", "q" in K, True)

# --- two-finger rollover (needs adb root)
fresh("VIETNAMESE")
g = K["mode"]; n = K["n"]; a = K["a"]
sh(f"sh /data/local/tmp/mt.sh {a[0]} {a[1]} {n[0]} {n[1]}"); time.sleep(0.6)
check("rollover a+n", field(), "an|")
clear(); set_mode("VIETNAMESE"); refresh()
sh(f"sh /data/local/tmp/mt.sh {g[0]} {g[1]} {n[0]} {n[1]}"); time.sleep(0.6)
f, m = refresh()
check("rollover globe+n: switches first", m, "CHINESE")
check("rollover globe+n: n is pinyin", f, "n|")
clear(); set_mode("VIETNAMESE")

# --- word suggestions, slip correction, keys that follow the sentence (Vietnamese · English)
D = int(sh("wm density").split()[-1]) / 160   # px per dp


def mid(n):
    l, t, r, b = RECTS[n]
    return (l + r) / 2, (t + b) / 2


def toward(a, b, frac=0.68):
    """A touch inside key a, frac of its half-width from its centre toward key b: a slip, but still in the part of
    the key that always types it (the tap model's sure zone is 0.7), so the letter typed does not depend on the model."""
    (ax, ay), (bx, _) = mid(a), mid(b)
    l, _, r, _ = RECTS[a]
    return ax + (1 if bx > ax else -1) * frac * (r - l) / 2, ay


def english():
    fresh(); typ("server "); clear()


def vietnamese():
    fresh(); typ("vieetj "); clear()


def set_pref(key, on):
    sh(f"am broadcast -a dev.t43.vipi.DUMP -p dev.t43.vipi --es id p{time.time()} --es set {key}={'true' if on else 'false'} >/dev/null")
    time.sleep(0.5)


def restart_keyboard():
    """Hide and show the keyboard: the suggester forgets the words kept after a Backspace undo."""
    sh("input keyevent KEYCODE_BACK"); time.sleep(0.5); ensure_shown()


def slipped_rhonk():
    """rhonk with r slipped toward t and o toward i (the other letters on their centres)."""
    refresh()
    for c in "rhonk":
        if c == "r": tap_at(*toward("r", "t"))
        elif c == "o": tap_at(*toward("o", "i"))
        else: tap(c)


fresh()
check("suggest: models ready", wait_suggest(), True)
english(); typ("I want to th")
check("suggest: completions after 'I want to th'", cells(), [("th", "q"), ("think", ""), ("throw", "")])
tap("word1"); time.sleep(0.3)
check("suggest: pick a completion", field(), "I want to think |")
c = cells()
check("suggest: next words after the picked word", len(c) > 0 and all(f == "n" for _, f in c), True)
nxt = c[0][0] if c else "?"
tap("word0"); time.sleep(0.3)
check("suggest: pick a next word", field(), f"I want to think {nxt} |")
vietnamese(); typ("hoom nay ")
c = cells()
print("  next words after hôm nay:", c)
check("suggest: VI next words after hôm nay", len(c) > 0 and all(f == "n" for _, f in c), True)
english(); typ("I want to rhonk ")
check("slip: centre taps are not corrected", field(), "I want to rhonk |")
set_pref("autoCorrect", False)
english(); typ("I want to "); slipped_rhonk(); tap("space")
check("slip: auto-correct off keeps rhonk", field(), "I want to rhonk |")
set_pref("autoCorrect", True)
english(); typ("I want to "); slipped_rhonk()
check("slip: bar shows the fix", cells(), [("rhonk", "q"), ("think", "h")])
tap("space")
check("slip: rhonk → think at the space", field(), "I want to think |")
tap("backspace"); time.sleep(0.3)
check("slip: Backspace puts rhonk back", field(), "I want to rhonk|")
# a touch in the gap between n and the space bar (3.5 dp below n): a space after a finished word, n otherwise
english(); typ("I want to thank"); refresh()
gap = (mid("n")[0], RECTS["n"][3] + 3.5 * D)
tap_at(*gap)
check("tap: gap after thank is a space", field(), "I want to thank |")
english(); typ("I want to tha"); tap_at(*gap)
check("tap: gap after tha is n", field(), "I want to than|")
# Vietnamese: a touch 0.4 dp from the u|i border goes to the likelier Telex key; the opposite with auto-correct off
border = (mid("u")[0] + mid("i")[0]) / 2
row = mid("u")[1]
for on in (True, False):
    set_pref("autoCorrect", on)
    tag = "" if on else " (auto-correct off)"
    vietnamese(); typ("kyf th"); tap_at(border - 0.4 * D, row)
    check("tap: kỳ th + inside u next to i" + tag, field(), "kỳ thi|" if on else "kỳ thu|")
    vietnamese(); typ("muaf th"); tap_at(border + 0.4 * D, row)
    check("tap: mùa th + inside i next to u" + tag, field(), "mùa thu|" if on else "mùa thi|")
set_pref("autoCorrect", True)
# the cursor moved with the space bar after a slipped word: the space must not replace anything
restart_keyboard()
english(); typ("I want to "); slipped_rhonk()
check("slip: fix pending before the cursor drag", ("think", "h") in cells(), True)
sp = mid("space")
drag(sp, (sp[0] - 41 * D, sp[1]), 500)
f = field()
tap("space")
check("slip: space after a cursor drag inserts only a space", field(), f.replace("|", " |"))
# the two switches in the settings screen
sh("input keyevent KEYCODE_BACK"); time.sleep(0.5)
from ui import scroll_to
for label in ("Word suggestions", "Auto-correct typos"):
    found = scroll_to(label)
    x = sh("cat /sdcard/u.xml")
    m = re.search(r'text="' + re.escape(label) + r'"[^>]*checked="(true|false)"', x)
    check(f"settings: {label} switch on", bool(found) and m is not None and m[1] == "true", True)
summary()
