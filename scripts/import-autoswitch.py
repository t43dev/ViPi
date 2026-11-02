#!/usr/bin/env python3
"""Lấy bảng tần suất tự đổi Anh/Việt từ Vikey (GPL-3.0, github.com/tonyminibot/Vikey) sang Resources/.

Dùng: python3 -I scripts/import-autoswitch.py <đường dẫn Vikey>/Engine/AutoSwitchData.h
Ra Resources/autoswitch-vi.tsv (khoá Telex chuẩn hoá: â→aa, ư→uw, đ→dd, thanh ở cuối) và autoswitch-en.tsv,
mỗi dòng "từ<TAB>điểm", điểm = 10·log10(số lần trên một triệu từ).
Tần suất gốc: FrequencyWords (Hermit Dave), OpenSubtitles 2018, CC BY-SA 4.0.
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


def main():
    src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    out = pathlib.Path(__file__).resolve().parent.parent / "Resources"
    for lang, prefix in (("vi", "kAutoSwitchVn"), ("en", "kAutoSwitchEn")):
        w, offsets, scores = words(src, prefix + "Words"), numbers(src, prefix + "Offsets"), numbers(src, prefix + "Scores")
        flat = "\0".join(w)
        entries = [flat[o:flat.index("\0", o)] if "\0" in flat[o:] else flat[o:] for o in offsets]
        assert len(entries) == len(scores), (lang, len(entries), len(scores))
        path = out / f"autoswitch-{lang}.tsv"
        path.write_text("".join(f"{e}\t{s}\n" for e, s in zip(entries, scores)), encoding="utf-8")
        print(path.name, len(entries))


main()
