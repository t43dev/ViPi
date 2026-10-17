#!/usr/bin/env python3
"""Build ViPi's Pinyin dictionary (pinyin.tsv) from rime-ice dictionaries.

Source data: rime-ice by iDvel -- https://github.com/iDvel/rime-ice (GPL-3.0).
  - 8105.dict.yaml : single characters (通用规范汉字表), all valid entries kept.
  - base.dict.yaml : words, kept only when weight >= BASE_MIN_WEIGHT and
                     length <= MAX_WORD_LEN characters.

Cutoff: BASE_MIN_WEIGHT = 1000 keeps the output around 6.7 MB / ~249k lines
(>= 500 gives ~7.7 MB, >= 100 ~10 MB); words longer than 8 chars are dropped.

Output: one entry per line, no header:
    word<TAB>pinyin syllables separated by spaces<TAB>weight(int)
Deduplicated on (word, pinyin) keeping max weight, sorted by pinyin then
weight desc then word, so output is deterministic. ü is spelled "v" (lv, nv)
as in rime-ice.

Usage: python3 -I build_pinyin_dict.py <rime_dict_dir> <output.tsv>
"""
import re
import sys
from pathlib import Path

BASE_MIN_WEIGHT = 1000
MAX_WORD_LEN = 8

PINYIN_RE = re.compile(r"[a-z]+(?: [a-z]+)*")
HAN_RE = re.compile(
    "[〇㐀-䶿一-鿿豈-﫿"
    "\U00020000-\U0002ebef\U00030000-\U0003134f]+"
)


def read_entries(path):
    """Yield (word, pinyin, weight) from a rime dict.yaml body (after '...')."""
    in_body = False
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if not in_body:
                if line.strip() == "...":
                    in_body = True
                continue
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 2:
                continue
            word, pinyin = cols[0].strip(), " ".join(cols[1].split())
            weight = 0
            if len(cols) >= 3 and cols[2].strip():
                try:
                    weight = int(cols[2].strip())
                except ValueError:
                    continue
            if not HAN_RE.fullmatch(word) or not PINYIN_RE.fullmatch(pinyin):
                continue
            if len(pinyin.split(" ")) != len(word):
                continue  # syllable count must match character count
            yield word, pinyin, weight


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: build_pinyin_dict.py <rime_dict_dir> <output.tsv>")
    src, out = Path(sys.argv[1]), Path(sys.argv[2])

    best = {}

    def add(word, pinyin, weight):
        key = (word, pinyin)
        if weight > best.get(key, -1):
            best[key] = weight

    for word, pinyin, weight in read_entries(src / "8105.dict.yaml"):
        if len(word) == 1:
            add(word, pinyin, weight)
    for word, pinyin, weight in read_entries(src / "base.dict.yaml"):
        if weight >= BASE_MIN_WEIGHT and len(word) <= MAX_WORD_LEN:
            add(word, pinyin, weight)

    rows = sorted(best.items(), key=lambda kv: (kv[0][1], -kv[1], kv[0][0]))
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        for (word, pinyin), weight in rows:
            f.write(f"{word}\t{pinyin}\t{weight}\n")
    print(f"wrote {len(rows)} entries to {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
