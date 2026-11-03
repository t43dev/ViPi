#!/usr/bin/env python3
"""Lấy bảng tần suất tự đổi Anh/Việt từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey) sang Resources/.

Dùng: python3 -I scripts/import-autoswitch.py <đường dẫn Vikey>/Engine
Ra Resources/autoswitch-vi.tsv (khoá Telex chuẩn hoá: â→aa, ư→uw, đ→dd, thanh ở cuối) và autoswitch-en.tsv,
mỗi dòng "từ<TAB>điểm", điểm = 10·log10(số lần trên một triệu từ).
Tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018, CC BY-SA 4.0.
Và Resources/autoswitch-pairs.tsv (BigramData.h): "từ trước<TAB>từ sau<TAB>8·log2(số lần)" cho các từ đọc được cả
hai cách (bus/bú, been/bên), từ FineWeb-2 / FineWeb (ODC-By), HPLT 2 (CC0), MADLAD-400 (ODC-By), Reddit.
"""
import pathlib
import re
import sys


def array(src, name):
    m = re.search(r"\b%s\[[^\]]*\]\s*=\s*(.*?);" % name, src, re.S)
    if not m:
        sys.exit(f"missing {name}")
    return m.group(1)


def words(src, name):
    body = array(src, name)
    joined = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', body))
    return joined.replace("\\0", "\0").split("\0")


def numbers(src, name):
    return [int(x) for x in re.findall(r"-?\d+", array(src, name))]


def c_bytes(body):
    """Các chuỗi C liền nhau → bytes (\\ooo bát phân, \\t, \\0, \\", \\\\)."""
    out = bytearray()
    for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', body):
        i = 0
        while i < len(lit):
            c = lit[i]
            if c != "\\":
                out += c.encode("utf-8"); i += 1; continue
            n = lit[i + 1]
            if n in "01234567":
                j = i + 1
                while j < len(lit) and j < i + 4 and lit[j] in "01234567": j += 1
                out.append(int(lit[i + 1:j], 8)); i = j
            else:
                out += {"t": b"\t", "n": b"\n", '"': b'"', "\\": b"\\"}[n]; i += 2
    return bytes(out)


def pairs(engine, out):
    src = (engine / "BigramData.h").read_text(encoding="utf-8")
    keys = [k.decode("utf-8") for k in c_bytes(array(src, "kBigramKeys")).split(b"\0") if k]
    logs = numbers(src, "kBigramLogCounts")
    assert len(keys) == len(logs), (len(keys), len(logs))
    path = out / "autoswitch-pairs.tsv"
    path.write_text("".join(f"{k}\t{v}\n" for k, v in zip(keys, logs)), encoding="utf-8")
    print(path.name, len(keys))


def main():
    engine = pathlib.Path(sys.argv[1])
    src = (engine / "AutoSwitchData.h").read_text(encoding="utf-8")
    out = pathlib.Path(__file__).resolve().parent.parent / "Resources"
    for lang, prefix in (("vi", "kAutoSwitchVn"), ("en", "kAutoSwitchEn")):
        w, offsets, scores = words(src, prefix + "Words"), numbers(src, prefix + "Offsets"), numbers(src, prefix + "Scores")
        flat = "\0".join(w)
        entries = [flat[o:flat.index("\0", o)] if "\0" in flat[o:] else flat[o:] for o in offsets]
        assert len(entries) == len(scores), (lang, len(entries), len(scores))
        path = out / f"autoswitch-{lang}.tsv"
        path.write_text("".join(f"{e}\t{s}\n" for e, s in zip(entries, scores)), encoding="utf-8")
        print(path.name, len(entries))
    pairs(engine, out)


main()
