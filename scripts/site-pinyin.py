"""Cut Resources/pinyin.tsv down to a small dictionary for the website's typing demo.

Output lines: `pinyin<TAB>word:score word:score…`, words sorted by frequency,
score = round(ln(frequency) * 10). Usage: python3 scripts/site-pinyin.py OUT
"""
import math
import sys
from collections import defaultdict
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / 'Resources' / 'pinyin.tsv'
CHARS_PER_SYLLABLE = 8
WORDS = 9000
MUST = ['越南', '越南人', '学习', '中国人', '西安', '老师', '汉语', '中文', '谢谢', '你好']

chars, words = defaultdict(list), []
for line in SRC.read_text(encoding='utf-8').splitlines():
    word, key, freq = line.split('\t')
    freq = int(freq)
    if freq < 2:
        continue
    n = len(key.split(' '))
    if n == 1:
        chars[key].append((freq, word))
    elif n <= 4 and len(word) == n:
        words.append((freq, word, key))

out = defaultdict(list)
for key, items in chars.items():
    for freq, word in sorted(items, reverse=True)[:CHARS_PER_SYLLABLE]:
        out[key].append((freq, word))
words.sort(reverse=True)
keep = words[:WORDS] + [w for w in words[WORDS:] if w[1] in MUST]
for freq, word, key in keep:
    out[key].append((freq, word))

with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for key in sorted(out):
        items = sorted(out[key], reverse=True)
        f.write(key + '\t' + ' '.join(f'{w}:{round(math.log(fr) * 10)}' for fr, w in items) + '\n')
