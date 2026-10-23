#!/usr/bin/env python3
"""Build Resources/bigram.bin from libpinyin's text language model (GPL-3.0).

    curl -L -o model20.text.tar.gz https://downloads.sourceforge.net/libpinyin/models/model20.text.tar.gz
    tar -xzf model20.text.tar.gz interpolation2.text
    python3 scripts/make-bigram.py interpolation2.text

Keeps word pairs where both words exist in Resources/pinyin.tsv and the pair was seen >= 8 times.
Format (little endian): "VPBG", u32 version=1, u32 nUni, u32 nPairs, u64 uniKeys[nUni], u32 uniCounts[nUni],
u64 pairKeys[nPairs], u32 pairCounts[nPairs]; keys are FNV-1a 64 of UTF-8 "w1" / "w1\\tw2", sorted ascending.
The app mmaps the file and binary-searches it, so loading costs no parsing and almost no dirty memory.
"""
import io, os, struct, sys

MIN_COUNT = 8

def fnv1a64(s: str) -> int:
    h = 0xcbf29ce484222325
    for b in s.encode("utf-8"):
        h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h

def main(src: str) -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    words = set(l.split("\t")[0] for l in io.open(os.path.join(root, "Resources/pinyin.tsv"), encoding="utf-8"))
    uni, pairs, sec = {}, {}, None
    for line in io.open(src, encoding="utf-8", errors="replace"):
        if line.startswith("\\1-gram"): sec = 1; continue
        if line.startswith("\\2-gram"): sec = 2; continue
        if not line.startswith("\\item"): continue
        p = line.split()
        if sec == 1 and len(p) == 5 and p[2] in words:
            uni[p[2]] = int(p[4])
        elif sec == 2 and len(p) == 7 and int(p[6]) >= MIN_COUNT and p[2] in words and p[4] in words:
            pairs[(p[2], p[4])] = int(p[6])
    used = {w for a, b in pairs for w in (a, b)}
    uni_rows = sorted((fnv1a64(w), c) for w, c in uni.items() if w in used)
    pair_rows = sorted((fnv1a64(a + "\t" + b), c) for (a, b), c in pairs.items())
    assert len({k for k, _ in pair_rows}) == len(pair_rows), "hash collision"
    out = os.path.join(root, "Resources/bigram.bin")
    with open(out, "wb") as f:
        f.write(b"VPBG" + struct.pack("<III", 1, len(uni_rows), len(pair_rows)))
        f.write(struct.pack(f"<{len(uni_rows)}Q", *(k for k, _ in uni_rows)))
        f.write(struct.pack(f"<{len(uni_rows)}I", *(c for _, c in uni_rows)))
        f.write(struct.pack(f"<{len(pair_rows)}Q", *(k for k, _ in pair_rows)))
        f.write(struct.pack(f"<{len(pair_rows)}I", *(min(c, 0xFFFFFFFF) for _, c in pair_rows)))
    print(f"{out}: {len(uni_rows)} unigrams, {len(pair_rows)} pairs, {os.path.getsize(out) / 1e6:.1f} MB")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "interpolation2.text")
