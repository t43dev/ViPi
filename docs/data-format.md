# Data files

ViPi maps its large tables into memory with `mmap` and searches them in place, so they cost almost no private RAM and load in milliseconds. The same files are meant to be read by future Windows and Android builds. All numbers are little-endian.

## Sorted table (`pinyin-words.bin`, `pinyin-abbrev.bin`, `s2t.bin`, `autoswitch-*.bin`)

Built by `scripts/build-tables.py`, read by `Sources/ViPiCore/SortedTable.swift`.

| Offset | Size | Field |
|:--|:--|:--|
| 0 | 4 | magic `VPST` |
| 4 | 4 | version, `1` |
| 8 | 4 | `n`, number of keys |
| 12 | 4 | reserved, `0` |
| 16 | 8 | `meta`, a float64 the table may use |
| 24 | 4·(n+1) | key offsets into the key block |
| 28+4n | 4·(n+1) | value offsets into the value block |
| 32+8n | | key block: the UTF-8 keys back to back, sorted by bytes |
| | | value block |

Key `i` is the bytes `[keyOffset[i], keyOffset[i+1])` of the key block, and its value is `[valueOffset[i], valueOffset[i+1])` of the value block. To look up a key, binary-search the keys comparing bytes. The first key that is greater than or equal to a prefix tells whether any key starts with that prefix.

Values per file:

- **`pinyin-words.bin`**: the key is the pinyin syllables joined by single spaces, for example `ni hao`. The value is the words for that key, heaviest first. Each word is stored as its UTF-8 length (1 byte), its UTF-8 bytes, then its weight (u32). `meta` is the sum of `max(weight, 1)` over all words.
- **`pinyin-abbrev.bin`**: the key is the first letters of a 2–4 syllable key, for example `nh`. The value is up to 30 u32 offsets, heaviest first. Each offset points at a word record in the value block of `pinyin-words.bin`.
- **`s2t.bin`**: the key is Simplified Chinese and the value is the Traditional UTF-8 text. ViPi converts by taking the longest match first.
- **`autoswitch-vi.bin`, `autoswitch-en.bin`**: the key is a word (Vietnamese as normalised Telex keys, `trên` → `treen`) and the value is one signed byte, `10·log10(occurrences per million)`.

## Bigram model (`bigram.bin`)

Built by `scripts/make-bigram.py`, read by `Sources/ViPiCore/BigramModel.swift`.

| Offset | Size | Field |
|:--|:--|:--|
| 0 | 4 | magic `VPBG` |
| 4 | 4 | version, `1` |
| 8 | 4 | `u`, number of unigrams |
| 12 | 4 | `p`, number of pairs |
| 16 | 8·u | sorted 64-bit FNV-1a hashes of the words |
| | 4·u | counts of the words |
| | 8·p | sorted FNV-1a hashes of `word1<TAB>word2` |
| | 4·p | counts of the pairs |
