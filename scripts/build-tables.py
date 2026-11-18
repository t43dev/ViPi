#!/usr/bin/env python3
"""Dựng các bảng nhị phân ViPi đọc bằng mmap (định dạng: docs/data-format.md) từ các file .tsv nguồn.

Dùng: python3 -I scripts/build-tables.py      (chạy lại mỗi khi sửa một file .tsv trong Resources/)

  pinyin.tsv          → pinyin-words.bin   "ni hao" → [你好 …] theo weight giảm dần; meta = tổng weight
                      → pinyin-abbrev.bin  "nh" → 30 từ 2-4 âm tiết nặng nhất viết tắt bằng phụ âm đầu,
                                           mỗi từ là vị trí (u32) của mục đó trong pinyin-words.bin
  s2t.tsv             → s2t.bin            giản thể → phồn thể (OpenCC)
  autoswitch-vi.tsv + autoswitch-vi-chat.tsv → autoswitch-vi.bin  khoá Telex → điểm tần suất (1 byte có dấu); chữ chat: thêm 1 byte cờ và chính chữ đó
  autoswitch-en.tsv + autoswitch-en-forms.tsv → autoswitch-en.bin (dạng từ của SCOWL, từ đã có trong danh sách thì giữ điểm)
  autoswitch-pairs.tsv → autoswitch-pairs.bin "từ trước<TAB>từ sau" → 8·log2(số lần) (1 byte)
"""
import pathlib
import struct
import unicodedata

RES = pathlib.Path(__file__).resolve().parent.parent / "Resources"
MAGIC, VERSION = b"VPST", 1


def write_table(name, items, meta=0.0):
    """items: {khoá str: giá trị bytes}. Khoá sắp xếp theo byte UTF-8 để tìm kiếm nhị phân."""
    keys = sorted(items, key=lambda k: k.encode())
    kblob, vblob, koff, voff = bytearray(), bytearray(), [0], [0]
    for k in keys:
        kblob += k.encode()
        vblob += items[k]
        koff.append(len(kblob))
        voff.append(len(vblob))
    n = len(keys)
    out = bytearray(MAGIC) + struct.pack("<IIId", VERSION, n, 0, meta)
    out += struct.pack(f"<{n + 1}I", *koff) + struct.pack(f"<{n + 1}I", *voff) + kblob + vblob
    (RES / name).write_bytes(out)
    print(f"{name}: {n} keys, {len(out):,} bytes")


def entries(lst):
    """[(từ, weight)] → mỗi mục: độ dài UTF-8 (1 byte), từ, weight (u32)."""
    out = bytearray()
    for word, weight in lst:
        b = word.encode()
        out += bytes([len(b)]) + b + struct.pack("<I", weight)
    return bytes(out)


def pinyin():
    words, abbrev, total = {}, {}, 0.0   # abbrev: viết tắt → [(khoá, từ, weight)] theo thứ tự trong file
    for line in (RES / "pinyin.tsv").read_text(encoding="utf-8").split("\n"):
        cols = line.split("\t")
        if len(cols) < 2 or not line:
            continue
        word, key = cols[0], cols[1]
        weight = int(cols[2]) if len(cols) > 2 and cols[2].lstrip("-").isdigit() else 0
        assert 0 <= weight < 2**32 and len(word.encode()) < 256, line
        total += max(weight, 1)
        words.setdefault(key, []).append((word, weight))
        sylls = key.split(" ")
        if 2 <= len(sylls) <= 4:
            abbrev.setdefault("".join(s[0] for s in sylls), []).append((key, word, weight))
    # sort ổn định như Swift: cùng weight thì giữ thứ tự trong file
    values = {k: sorted(v, key=lambda e: -e[1]) for k, v in words.items()}
    offset, pos = 0, {}   # (khoá, từ) → vị trí byte của mục trong khối giá trị của pinyin-words.bin
    for k in sorted(values, key=lambda k: k.encode()):
        for word, weight in values[k]:
            pos.setdefault((k, word), offset)
            offset += 1 + len(word.encode()) + 4
    write_table("pinyin-words.bin", {k: entries(v) for k, v in values.items()}, total)
    write_table("pinyin-abbrev.bin", {a: b"".join(struct.pack("<I", pos[(k, w)])
                                                  for k, w, _ in sorted(v, key=lambda e: -e[2])[:30])
                                      for a, v in abbrev.items()})


def s2t():
    table = {}
    for line in (RES / "s2t.tsv").read_text(encoding="utf-8").split("\n"):
        cols = [c for c in line.split("\t") if c]
        if len(cols) >= 2:
            table[cols[0]] = cols[1].encode()   # trùng khoá: dòng sau thắng, như bản đọc .tsv cũ
    write_table("s2t.bin", table)


TONE_KEYS = {"\u0301": "s", "\u0300": "f", "\u0309": "r", "\u0303": "x", "\u0323": "j"}
MARK_KEYS = {"\u0302": lambda c: c, "\u0306": lambda c: "w", "\u031b": lambda c: "w"}   # â ê ô: gõ đôi; ă ơ ư: w


def telex_key(word):
    """Khoá Telex chuẩn hoá của một chữ: â→aa, ă→aw, ơ→ow, ư→uw, đ→dd, phím thanh ở cuối (như `key()` của lõi)."""
    out, tone = [], ""
    for ch in unicodedata.normalize("NFD", word.lower()):
        if ch in TONE_KEYS:
            tone = TONE_KEYS[ch]
        elif ch in MARK_KEYS:
            out.append(MARK_KEYS[ch](out[-1]))
        elif ch == "đ":
            out.append("dd")
        else:
            out.append(ch)
    return "".join(out) + tone


def chat_words(vi):
    """autoswitch-vi-chat.tsv → {khoá: điểm, cờ chữ chat, chữ}. Chữ đã là âm tiết thường thì bỏ (gõ được sẵn).
    Cách gõ nào của một chữ trùng từ tiếng Anh thì lúc gõ bộ gõ vẫn giữ từ tiếng Anh (gets, fair)."""
    syllables = set((RES / "vietnamese-syllables.txt").read_text(encoding="utf-8").split())
    out = {}
    for line in (RES / "autoswitch-vi-chat.tsv").read_text(encoding="utf-8").split("\n"):
        word = line.split("\t")[0].strip()
        if not word or line.startswith("#"):
            continue
        key = telex_key(word)
        assert key.isascii() and key.isalpha(), line
        if word in syllables:
            print(f"  chat word skipped: {word} (a syllable)")
        elif key in out:
            print(f"  chat word skipped: {word} (same keys as {out[key][2:].decode()})")
        else:
            # giá trị: điểm (từ đã có trong bảng tần suất thì giữ điểm của nó), cờ chữ chat, rồi chính chữ đó (UTF-8)
            out[key] = vi.get(key, struct.pack("<b", 5))[:1] + b"\x01" + word.encode()
    return out


def autoswitch():
    tables = {}
    for lang in ("vi", "en"):
        table = tables[lang] = {}
        for line in (RES / f"autoswitch-{lang}.tsv").read_text(encoding="utf-8").split("\n"):
            cols = line.split("\t")
            if len(cols) == 2:
                table[cols[0]] = struct.pack("<b", int(cols[1]))
        if lang == "en":
            for line in (RES / "autoswitch-en-forms.tsv").read_text(encoding="utf-8").split("\n"):
                cols = line.split("\t")
                if len(cols) == 2 and not line.startswith("#"):
                    table.setdefault(cols[0], struct.pack("<b", int(cols[1])))
    chat = chat_words(tables["vi"])
    tables["vi"].update(chat)
    print(f"chat words: {len(chat)}")
    for lang in ("vi", "en"):
        write_table(f"autoswitch-{lang}.bin", tables[lang])
    table = {}
    for line in (RES / "autoswitch-pairs.tsv").read_text(encoding="utf-8").split("\n"):
        cols = line.split("\t")
        if len(cols) == 3:
            table[cols[0] + "\t" + cols[1]] = bytes([int(cols[2])])
    write_table("autoswitch-pairs.bin", table)


pinyin()
s2t()
autoswitch()
