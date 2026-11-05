import sys, re, time; sys.path.insert(0, __import__('os').path.dirname(__file__))
from harness import *
def find(text):
    sh("uiautomator dump /sdcard/u.xml >/dev/null")
    x = sh("cat /sdcard/u.xml")
    m = re.search(r'text="' + re.escape(text) + r'"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', x)
    return None if not m else ((int(m[1]) + int(m[3])) // 2, (int(m[2]) + int(m[4])) // 2)
def scroll_to(text):
    for _ in range(12):
        p = find(text)
        if p and 300 < p[1] < 1500: return p
        sh("input swipe 540 1500 540 900 300"); time.sleep(0.5)
    return find(text)
