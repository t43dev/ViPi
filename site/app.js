// ViPi site: appearance toggle, latest version, settings tabs and the typing demo.
// The Telex rules below are a direct port of Sources/ViPiCore/TelexEngine.swift.
(() => {
  'use strict';
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------- Appearance ----------
  const root = document.documentElement;
  const systemDark = matchMedia('(prefers-color-scheme: dark)');
  const themeButton = $('.theme');
  const isDark = () => (root.dataset.theme ? root.dataset.theme === 'dark' : systemDark.matches);
  const syncTheme = () => themeButton.setAttribute('aria-label', isDark() ? 'Switch to light appearance' : 'Switch to dark appearance');
  themeButton.addEventListener('click', () => {
    const next = isDark() ? 'light' : 'dark';
    try {
      // Chọn trùng với macOS thì bỏ lựa chọn đã lưu để lại đi theo hệ thống.
      if ((next === 'dark') === systemDark.matches) { delete root.dataset.theme; localStorage.removeItem('vipi-theme'); }
      else { root.dataset.theme = next; localStorage.setItem('vipi-theme', next); }
    } catch (e) { root.dataset.theme = next; }
    syncTheme();
  });
  systemDark.addEventListener('change', syncTheme);
  syncTheme();

  // ---------- Latest version ----------
  const versionEl = $('[data-version]');
  fetch('https://api.github.com/repos/t43dev/ViPi/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then((r) => (r.ok ? r.json() : null))
    .then((j) => { if (j && /^v?\d/.test(j.tag_name)) versionEl.textContent = 'Version ' + j.tag_name.replace(/^v/, ''); })
    .catch(() => {});

  // ---------- Settings tabs ----------
  const tabs = $$('[role="tab"]');
  const shot = $('#shot');
  const shotAlt = {
    general: 'ViPi General settings: language, appearance and switching shortcut',
    vietnamese: 'ViPi Vietnamese settings: spell checking and tone placement',
    chinese: 'ViPi Chinese settings: Traditional characters, learning and fuzzy pinyin',
    shortcuts: 'ViPi Text shortcuts settings',
  };
  function selectTab(tab, focus) {
    for (const t of tabs) {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
    }
    const key = tab.dataset.shot;
    const [light, dark] = $$('img', shot);
    light.src = `img/settings-${key}-en-light.png`;
    dark.src = `img/settings-${key}-en-dark.png`;
    light.alt = dark.alt = shotAlt[key];
    shot.setAttribute('aria-labelledby', tab.id);
    if (focus) tab.focus();
  }
  for (const tab of tabs) {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', (e) => {
      const i = tabs.indexOf(tab);
      const next = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[e.key];
      if (next === undefined) return;
      e.preventDefault();
      selectTab(tabs[(next + tabs.length) % tabs.length], true);
    });
  }

  // ---------- Telex ----------
  const TONE_KEYS = { s: 1, f: 2, r: 3, x: 4, j: 5 };
  const ROWS = {
    a: 'aáàảãạ', 'ă': 'ăắằẳẵặ', 'â': 'âấầẩẫậ', e: 'eéèẻẽẹ', 'ê': 'êếềểễệ',
    i: 'iíìỉĩị', o: 'oóòỏõọ', 'ô': 'ôốồổỗộ', 'ơ': 'ơớờởỡợ', u: 'uúùủũụ',
    'ư': 'ưứừửữự', y: 'yýỳỷỹỵ',
  };
  const DECOMPOSE = new Map([['đ', ['đ', 0]], ['Đ', ['đ', 0]]]);
  for (const [l, row] of Object.entries(ROWS)) {
    [...row].forEach((c, i) => { DECOMPOSE.set(c, [l, i]); DECOMPOSE.set(c.toUpperCase(), [l, i]); });
  }
  const decompose = (ch) => DECOMPOSE.get(ch) || (/^[a-z]$/i.test(ch) ? [ch.toLowerCase(), 0] : null);

  const INITIALS = ['ngh', 'ng', 'nh', 'ch', 'gh', 'gi', 'kh', 'ph', 'th', 'tr', 'qu',
    'b', 'c', 'd', 'đ', 'g', 'h', 'k', 'l', 'm', 'n', 'p', 'q', 'r', 's', 't', 'v', 'x'];
  const FINALS = new Set(['c', 'ch', 'm', 'n', 'ng', 'nh', 'p', 't']);
  const CLUSTERS = new Set(('a â ă e ê i o ô ơ u ư y ai ao au ay âu ây eo eu êu ia ie iê iu oa oă oe oi ôi ơi oo ua uâ ue uê ui uo uô uơ ' +
    'uu uy ưa ưi ưo ươ ưu ye yê ieu iêu oai oay oeo uay uây uoi uou uôi uơi uơu uya uye uyê uyu ưoi ưou ươi ươu yeu yêu').split(' '));
  const TAKE_FINAL = new Set('a â ă e ê i o ô ơ u ư y ie iê oa oă oe oo ua uâ ue uê uo uô uơ uy ưo ươ ye yê uye uyê'.split(' '));
  const HORN = {
    a: ['('], o: ['+'], u: ['+'], oa: ['', '('], oi: ['+', ''], ua: ['+', ''], ui: ['+', ''],
    uo: ['', '+'], uu: ['+', ''], uoi: ['', '+', ''], uou: ['', '+', ''],
  };

  const isVowel = (c) => 'aeiouy'.includes(c.base);
  function letterOf(c) {
    const { base: b, mark: m } = c;
    if (m === '^' && 'aeo'.includes(b)) return { a: 'â', e: 'ê', o: 'ô' }[b];
    if (m === '(' && b === 'a') return 'ă';
    if (m === '+' && (b === 'o' || b === 'u')) return b === 'o' ? 'ơ' : 'ư';
    if (m === '-' && b === 'd') return 'đ';
    return b;
  }

  function syllable(cs) {
    const b = cs.map((c) => (c.mark === '-' ? 'đ' : c.base));
    let i = 0;
    let initial = '';
    for (const cons of INITIALS) {
      if (b.length >= cons.length && b.slice(0, cons.length).join('') === cons) {
        let n = cons.length;
        if (cons === 'gi' && !(b.length > 2 && isVowel(cs[2]))) n = 1;
        if (cons === 'qu' && cs[1].mark !== '') n = 1;
        initial = b.slice(0, n).join('');
        i = n;
        break;
      }
    }
    const vowels = [];
    while (i < cs.length && isVowel(cs[i])) vowels.push(i++);
    const final = b.slice(i).join('');
    return { initial, vowels, final, ok: ![...final].some((c) => 'aeiouy'.includes(c)) };
  }

  const newState = () => ({ chars: [], tone: 0, literal: false });
  const cloneState = (s) => ({ chars: s.chars.map((c) => ({ ...c })), tone: s.tone, literal: s.literal });
  const isUpper = (k) => k !== k.toLowerCase();
  const appendKey = (s, key) => s.chars.push({ base: key.toLowerCase(), mark: '', upper: isUpper(key), fromW: false });

  function isValid(s) {
    const p = syllable(s.chars);
    if (!p.ok) return false;
    if (!p.vowels.length) return !p.final;
    const cluster = p.vowels.map((i) => letterOf(s.chars[i])).join('');
    if (!CLUSTERS.has(cluster)) return false;
    if (p.final) {
      if (!FINALS.has(p.final) || !TAKE_FINAL.has(cluster)) return false;
      if (['c', 'ch', 'p', 't'].includes(p.final) && ![0, 1, 5].includes(s.tone)) return false;
    }
    return true;
  }

  function applyW(s, key, p) {
    const v = p.vowels;
    const w = v.find((i) => s.chars[i].fromW);
    if (w !== undefined) {
      s.chars[w] = { base: 'w', mark: '', upper: s.chars[w].upper, fromW: false };
      s.literal = true;
      return true;
    }
    if (!v.length) {
      if (p.final || p.initial === 'q' || p.initial === 'qu') return false;
      s.chars.push({ base: 'u', mark: '+', upper: isUpper(key), fromW: true });
      return true;
    }
    const marks = HORN[v.map((i) => s.chars[i].base).join('')];
    if (!marks) return false;
    const current = v.map((i) => s.chars[i].mark);
    if (marks.every((m, j) => m === '' || current[j] === m)) {
      v.forEach((i, j) => { if (marks[j]) s.chars[i].mark = ''; });
      appendKey(s, key);
      s.literal = true;
    } else {
      v.forEach((i, j) => { if (marks[j]) s.chars[i].mark = marks[j]; });
    }
    return true;
  }

  function transform(s, key, k) {
    const p = syllable(s.chars);
    const tone = TONE_KEYS[k];
    if (tone && p.vowels.length) {
      if (s.tone === tone) { s.tone = 0; appendKey(s, key); s.literal = true; } else s.tone = tone;
      return true;
    }
    if (k === 'z' && s.tone && p.vowels.length) { s.tone = 0; return true; }
    if (k === 'd' && s.chars[0] && s.chars[0].base === 'd') {
      if (s.chars[0].mark === '-') { s.chars[0].mark = ''; appendKey(s, key); s.literal = true; } else s.chars[0].mark = '-';
      return true;
    }
    if ('aeo'.includes(k)) {
      const i = [...p.vowels].reverse().find((j) => s.chars[j].base === k);
      if (i !== undefined) {
        if (s.chars[i].mark === '^') { s.chars[i].mark = ''; appendKey(s, key); s.literal = true; } else s.chars[i].mark = '^';
        return true;
      }
    }
    if (k === 'w') return applyW(s, key, p);
    return false;
  }

  function applyKey(s, key) {
    const k = key.toLowerCase();
    if (s.literal || !/^[a-z]$/.test(k) || !isValid(s)) { appendKey(s, key); return; }
    const t = cloneState(s);
    if (transform(t, key, k) && (t.literal || isValid(t))) Object.assign(s, t);
    else appendKey(s, key);
  }

  function tonePosition(cs, p) {
    const v = p.vowels;
    if (!v.length) return undefined;
    const marked = [...v].reverse().find((i) => cs[i].mark !== '');
    if (marked !== undefined) return marked;
    if (v.length === 1) return v[0];
    if (p.final) return v[v.length - 1];
    if (v.length >= 3) return v[1];
    return v[0]; // kiểu cũ như mặc định của ViPi: hòa, khỏe, thúy
  }

  function stateText(s) {
    const cs = s.chars.map((c) => ({ ...c }));
    const p = syllable(cs);
    const v = p.vowels;
    if (v.length >= 2 && cs[v[0]].base === 'u' && cs[v[1]].base === 'o' && (v.length === 3 || p.final) &&
        (cs[v[0]].mark === '+' || cs[v[1]].mark === '+')) {
      cs[v[0]].mark = '+';
      cs[v[1]].mark = '+';
    }
    const out = cs.map((c) => (c.upper ? letterOf(c).toUpperCase() : letterOf(c)));
    if (s.tone) {
      const i = tonePosition(cs, p);
      const row = i !== undefined && ROWS[letterOf(cs[i])];
      if (row) out[i] = cs[i].upper ? [...row][s.tone].toUpperCase() : [...row][s.tone];
    }
    return out.join('');
  }

  function telex(keys) {
    const s = newState();
    for (const k of keys) applyKey(s, k);
    return s.literal || isValid(s) ? stateText(s) : keys.join('');
  }

  function telexKeys(word) {
    const keys = [];
    let tone = 0;
    for (const ch of word) {
      const d = decompose(ch);
      if (!d) { keys.push(ch); continue; }
      if (d[1]) tone = d[1];
      const up = ch !== ch.toLowerCase();
      const spell = { 'â': 'aa', 'ă': 'aw', 'ê': 'ee', 'ô': 'oo', 'ơ': 'ow', 'ư': 'uw', 'đ': 'dd' }[d[0]] || d[0];
      for (const c of spell) keys.push(up ? c.toUpperCase() : c);
    }
    if (tone) keys.push(' sfrxj'[tone]);
    return keys;
  }

  let lexicon = null;
  const lexiconReady = fetch('data/syllables.txt').then((r) => r.text()).then((t) => {
    lexicon = new Set(t.split('\n').filter(Boolean).map((w) => telexKeys(w.toLowerCase()).join('')));
  }).catch(() => {});

  /** Kết thúc từ: chữ có dấu mà không phải âm tiết có thật thì trả lại đúng các phím đã gõ. */
  function finishWord(keys, output) {
    const raw = keys.join('');
    if (!lexicon || output === raw || !/[^\x00-\x7f]/.test(output)) return output;
    const hasVowel = [...output].some((ch) => { const d = decompose(ch); return d && 'aăâeêioôơuưy'.includes(d[0]); });
    return hasVowel && !lexicon.has(telexKeys(output.toLowerCase()).join('')) ? raw : output;
  }

  // ---------- Pinyin ----------
  let dict = null; // "ni hao" -> [[word, score]]
  let syllables = null;
  let prefixes = null;
  let index = null; // index[n][first letter] -> [{syl, items}]
  const pinyinReady = fetch('data/pinyin.tsv').then((r) => r.text()).then((t) => {
    dict = new Map();
    syllables = new Set();
    prefixes = new Set();
    index = {};
    for (const line of t.split('\n')) {
      if (!line) continue;
      const [key, list] = line.split('\t');
      const items = list.split(' ').map((x) => { const at = x.lastIndexOf(':'); return [x.slice(0, at), +x.slice(at + 1)]; });
      dict.set(key, items);
      const syl = key.split(' ');
      if (syl.length === 1) {
        syllables.add(key);
        for (let i = 1; i <= key.length; i++) prefixes.add(key.slice(0, i));
      }
      ((index[syl.length] ||= {})[key[0]] ||= []).push({ syl, items });
    }
  }).catch(() => {});

  /** Tách chuỗi pinyin thành âm tiết đủ hoặc phần đầu âm tiết (vd "nh" → n, h). */
  function tokenize(raw) {
    const tokens = [];
    for (const part of raw.split("'")) {
      const n = part.length;
      const best = Array(n + 1).fill(null);
      best[n] = { cost: 0, toks: [] };
      for (let i = n - 1; i >= 0; i--) {
        for (let len = Math.min(6, n - i); len >= 1; len--) {
          const piece = part.slice(i, i + len);
          const full = syllables.has(piece) && !(len === 1 && !'aeo'.includes(piece));
          if (!full && !prefixes.has(piece)) continue;
          const rest = best[i + len];
          if (!rest) continue;
          const cost = (full ? 1 : 3) + rest.cost;
          if (!best[i] || cost < best[i].cost) best[i] = { cost, toks: [{ t: piece, full }, ...rest.toks] };
        }
      }
      tokens.push(...(best[0] ? best[0].toks : [...part].map((t) => ({ t, full: false }))));
    }
    return tokens;
  }

  function lookup(tokens, start, n, memo) {
    const id = start + ',' + n;
    if (memo.has(id)) return memo.get(id);
    const toks = tokens.slice(start, start + n);
    const last = tokens.length - 1;
    let result;
    if (toks.every((t, j) => t.full && start + j !== last)) {
      result = dict.get(toks.map((t) => t.t).join(' ')) || [];
    } else {
      result = [];
      for (const e of (index[n] || {})[toks[0].t[0]] || []) {
        let ok = true;
        let exact = true;
        for (let j = 0; j < n && ok; j++) {
          const t = toks[j];
          const syl = e.syl[j];
          if (t.full && start + j !== last) ok = syl === t.t;
          else { ok = syl.startsWith(t.t); if (syl !== t.t) exact = false; }
        }
        if (ok) for (const [w, sc] of e.items) result.push([w, sc + (exact ? 50 : 0)]);
      }
      result.sort((a, b) => b[1] - a[1]);
      result = result.slice(0, 40);
    }
    memo.set(id, result);
    return result;
  }

  /** Cả câu: ít từ nhất, cùng số từ thì từ phổ biến hơn. */
  function sentence(tokens, memo) {
    const m = tokens.length;
    const best = Array(m + 1).fill(null);
    best[0] = { score: 0, words: [] };
    for (let i = 0; i < m; i++) {
      if (!best[i]) continue;
      for (let n = 1; n <= Math.min(4, m - i); n++) {
        const found = lookup(tokens, i, n, memo);
        if (!found.length) continue;
        const score = best[i].score + found[0][1] - 1000;
        if (!best[i + n] || score > best[i + n].score) best[i + n] = { score, words: [...best[i].words, found[0][0]] };
      }
    }
    return best[m] ? best[m].words.join('') : null;
  }

  function pinyinCandidates(raw) {
    if (!dict) return { tokens: [{ t: raw, full: false }], list: [{ w: raw, n: 1 }] };
    const tokens = tokenize(raw);
    const memo = new Map();
    const list = [];
    const seen = new Set();
    const add = (w, n) => { if (!seen.has(w)) { seen.add(w); list.push({ w, n }); } };
    if (tokens.length > 1) { const s = sentence(tokens, memo); if (s) add(s, tokens.length); }
    for (let n = Math.min(4, tokens.length); n >= 1; n--) for (const [w] of lookup(tokens, 0, n, memo)) add(w, n);
    if (!list.length) add(raw, tokens.length);
    return { tokens, list };
  }

  // ---------- Demo ----------
  const demo = $('.demo');
  const field = $('#demo-field');
  const input = $('.demo-input', field);
  const elCommitted = $('.committed', field);
  const elWord = $('.word', field);
  const caret = $('.caret', field);
  const candBox = $('.cands', field);
  const tape = $('.tape');
  const modeButtons = $$('.modes button');
  const PAGE = 5;
  const FULL_WIDTH = { ',': '，', '.': '。', '?': '？', '!': '！', ':': '：', ';': '；', '(': '（', ')': '）' };

  const st = {
    mode: 'vi', mru: ['vi', 'zh', 'en'], committed: '', keys: [], word: '',
    py: '', cands: null, sel: 0, fromScript: false,
  };
  let lastSwitch = { at: 0, count: 0, order: null };

  function commit(text) {
    st.committed += text;
    if (st.committed.length > 140) st.committed = '…' + st.committed.slice(-110);
  }
  function endViWord() {
    if (st.keys.length) commit(finishWord(st.keys, st.word));
    st.keys = [];
    st.word = '';
  }
  function refreshPinyin() {
    st.cands = st.py ? pinyinCandidates(st.py) : null;
    st.sel = 0;
  }
  function pick(i) {
    const c = st.cands && st.cands.list[i];
    if (!c) return;
    commit(c.w);
    st.py = st.cands.tokens.slice(c.n).map((t) => t.t).join('');
    refreshPinyin();
  }
  function flushPinyin() {
    if (st.py) commit(st.py);
    st.py = '';
    st.cands = null;
  }

  function setMode(mode) {
    endViWord();
    flushPinyin();
    st.mode = mode;
    st.mru = [mode, ...st.mru.filter((m) => m !== mode)];
  }
  function switchShortcut() {
    // Bấm một lần: về ngôn ngữ vừa dùng; bấm nhanh lần hai: ngôn ngữ trước đó nữa.
    const now = performance.now();
    if (now - lastSwitch.at < 450 && lastSwitch.count === 1) {
      setMode(lastSwitch.order[2]);
      lastSwitch = { at: now, count: 2, order: lastSwitch.order };
    } else {
      const order = st.mru.slice();
      setMode(order[1]);
      lastSwitch = { at: now, count: 1, order };
    }
  }

  function handle(key) {
    if (key === 'Switch') { switchShortcut(); return; }
    if (st.mode === 'zh' && st.py) {
      const page = Math.floor(st.sel / PAGE);
      const count = st.cands.list.length;
      if (/^[a-z']$/i.test(key)) { st.py += key.toLowerCase(); refreshPinyin(); }
      else if (key === ' ') pick(st.sel);
      else if (/^[1-9]$/.test(key)) { if (+key <= PAGE) pick(page * PAGE + +key - 1); }
      else if (key === 'Enter') flushPinyin();
      else if (key === 'Escape') { st.py = ''; st.cands = null; }
      else if (key === 'Backspace') { st.py = st.py.slice(0, -1); refreshPinyin(); }
      else if (key === 'ArrowRight') st.sel = Math.min(count - 1, st.sel + 1);
      else if (key === 'ArrowLeft') st.sel = Math.max(0, st.sel - 1);
      else if (key === '=' || key === 'ArrowDown') st.sel = Math.min(count - 1, (page + 1) * PAGE);
      else if (key === '-' || key === 'ArrowUp') st.sel = Math.max(0, (page - 1) * PAGE);
      else if (key.length === 1) { pick(st.sel); flushPinyin(); commit(FULL_WIDTH[key] || key); }
      return;
    }
    if (key === 'Backspace') {
      if (st.mode === 'vi' && st.word) {
        // như ViPi: xoá ký tự cuối đang hiển thị rồi dựng lại phím thô từ chữ còn lại
        st.word = [...st.word].slice(0, -1).join('');
        st.keys = telexKeys(st.word);
        if (telex(st.keys) !== st.word) st.keys = [...st.word];
        if (!st.word) st.keys = [];
      } else {
        st.committed = [...st.committed].slice(0, -1).join('');
      }
      return;
    }
    if (key === 'Enter') { endViWord(); commit('\n'); return; }
    if (key.length !== 1) return;
    if (st.mode === 'vi') {
      if (/^[a-z]$/i.test(key)) { st.keys.push(key); st.word = telex(st.keys); }
      else { endViWord(); commit(key); }
    } else if (st.mode === 'zh') {
      if (/^[a-z]$/i.test(key)) { st.py = key.toLowerCase(); refreshPinyin(); }
      else commit(FULL_WIDTH[key] || key);
    } else {
      commit(key);
    }
  }

  const TAPE_LABELS = { ' ': 'space', Backspace: '⌫', Enter: '↵', Escape: 'esc', ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓', Switch: '⌃⇧' };
  function addToTape(key) {
    const k = document.createElement('kbd');
    k.textContent = TAPE_LABELS[key] || key;
    if (key === 'Switch') k.className = 'combo';
    tape.append(k);
    while (tape.children.length > 28) tape.firstElementChild.remove();
  }

  function render() {
    elCommitted.textContent = st.committed;
    elWord.textContent = st.word;
    for (const b of modeButtons) b.setAttribute('aria-pressed', String(b.dataset.mode === st.mode));
    if (!st.cands) { candBox.hidden = true; return; }
    const page = Math.floor(st.sel / PAGE);
    const items = st.cands.list.slice(page * PAGE, page * PAGE + PAGE);
    candBox.replaceChildren();
    const head = document.createElement('span');
    head.className = 'py';
    head.textContent = st.cands.tokens.map((t) => t.t).join(' ');
    candBox.append(head);
    items.forEach((c, i) => {
      const li = document.createElement('li');
      if (page * PAGE + i === st.sel) li.className = 'on';
      const n = document.createElement('small');
      n.textContent = i + 1;
      li.append(n, c.w);
      candBox.append(li);
    });
    candBox.hidden = false;
    // đặt cửa sổ gợi ý ngay dưới con trỏ, không tràn khỏi khung
    const max = field.clientWidth - candBox.offsetWidth - 4;
    candBox.style.left = Math.max(4, Math.min(caret.offsetLeft - 14, max)) + 'px';
    candBox.style.top = caret.offsetTop + caret.offsetHeight + 8 + 'px';
  }

  function press(key, fromUser) {
    if (fromUser && st.fromScript) {
      stopScript();
      Object.assign(st, { committed: '', keys: [], word: '', py: '', cands: null, fromScript: false });
      tape.replaceChildren();
    }
    handle(key);
    addToTape(key);
    render();
  }

  // Keyboard. Desktop keys are handled on keydown; phones fall back to beforeinput and composition.
  let chordArmed = false;
  const SPECIAL = new Set(['Backspace', 'Enter', 'Escape', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown']);
  input.addEventListener('keydown', (e) => {
    if (e.isComposing) return;
    if (e.key === 'Control' || e.key === 'Shift') {
      chordArmed = e.ctrlKey && e.shiftKey && !e.altKey && !e.metaKey;
      return;
    }
    chordArmed = false;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (SPECIAL.has(e.key) || e.key.length === 1) {
      if (e.key.startsWith('Arrow') && !(st.mode === 'zh' && st.py)) return;
      e.preventDefault();
      press(e.key, true);
    }
  });
  input.addEventListener('keyup', (e) => {
    if ((e.key === 'Control' || e.key === 'Shift') && chordArmed) {
      chordArmed = false;
      press('Switch', true);
    }
  });
  input.addEventListener('beforeinput', (e) => {
    if (e.inputType === 'insertText' && e.data) { e.preventDefault(); for (const ch of e.data) press(ch, true); }
    else if (e.inputType === 'deleteContentBackward') { e.preventDefault(); press('Backspace', true); }
    else if (e.inputType === 'insertLineBreak') { e.preventDefault(); press('Enter', true); }
  });
  input.addEventListener('compositionend', (e) => {
    for (const ch of e.data || '') press(ch, true);
    input.value = '';
  });
  input.addEventListener('input', (e) => { if (e.isComposing || !input.value) return; for (const ch of input.value) press(ch, true); input.value = ''; });
  input.addEventListener('focus', () => demo.classList.add('focused'));
  input.addEventListener('blur', () => demo.classList.remove('focused'));
  for (const b of modeButtons) {
    b.addEventListener('click', () => {
      if (st.fromScript) press('Escape', true);
      setMode(b.dataset.mode);
      render();
      input.focus();
    });
  }

  // One scripted run on load: a Vietnamese sentence, the shortcut, then Chinese.
  const SCRIPT = [...'Minhf hocj tieengs Trung: ', 'Switch', ...'woxuexizhongwen', ' ', '.', 'Switch', ...'Vui quas!'];
  let timer = 0;
  function stopScript() { clearTimeout(timer); timer = 0; }
  function runScript() {
    st.fromScript = true;
    if (reduceMotion) { for (const k of SCRIPT) handle(k); render(); return; }
    let i = 0;
    const step = () => {
      if (i >= SCRIPT.length) { timer = 0; return; }
      const key = SCRIPT[i++];
      handle(key);
      addToTape(key);
      render();
      const pause = key === 'Switch' || key === ' ' || key === ':' ? 420 : 55 + Math.random() * 60;
      timer = setTimeout(step, pause);
    };
    timer = setTimeout(step, 500);
  }
  render();
  Promise.all([lexiconReady, pinyinReady]).then(() => { if (!st.committed && !st.word) runScript(); });
})();
