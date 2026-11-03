//! Từ và cụm người dùng đã chọn: khoá là đúng các chữ cái đã gõ (bỏ dấu '), giá trị là số lần chọn.
//! Lưu JSON `{khoá: {chữ: số lần}}` (cùng dạng với bản macOS cũ) vào file nếu có, ghi ở luồng nền.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Sender};

pub struct PinyinUserDictionary {
    entries: HashMap<String, HashMap<String, i64>>,
    pub max_entries: usize,
    file: Option<PathBuf>,
    writer: Option<Sender<Write>>,
}

enum Write {
    Save(String),
    Remove,
}

impl PinyinUserDictionary {
    /// Không có file: chỉ học trong bộ nhớ.
    pub fn in_memory() -> PinyinUserDictionary {
        PinyinUserDictionary { entries: HashMap::new(), max_entries: 5000, file: None, writer: None }
    }

    /// Đọc file nếu có; mỗi lần học thêm thì ghi lại (luồng nền, theo thứ tự).
    pub fn with_file(path: PathBuf) -> PinyinUserDictionary {
        let mut d = Self::in_memory();
        if let Ok(text) = std::fs::read_to_string(&path) {
            if let Ok(loaded) = serde_json::from_str::<HashMap<String, HashMap<String, i64>>>(&text) {
                d.entries = loaded;
            }
        }
        let (tx, rx) = channel::<Write>();
        let file = path.clone();
        std::thread::Builder::new()
            .name("vipi-userdict".into())
            .spawn(move || {
                for w in rx {
                    match w {
                        Write::Save(json) => {
                            if let Some(dir) = file.parent() {
                                let _ = std::fs::create_dir_all(dir);
                            }
                            let tmp = file.with_extension("tmp");
                            if std::fs::write(&tmp, json).is_ok() {
                                let _ = std::fs::rename(&tmp, &file);
                            }
                        }
                        Write::Remove => {
                            let _ = std::fs::remove_file(&file);
                        }
                    }
                }
            })
            .ok();
        d.file = Some(path);
        d.writer = Some(tx);
        d
    }

    pub fn count(&self) -> usize {
        self.entries.values().map(|m| m.len()).sum()
    }

    pub fn record(&mut self, key: &str, text: &str) {
        if key.is_empty() || text.is_empty() {
            return;
        }
        *self.entries.entry(key.to_string()).or_default().entry(text.to_string()).or_insert(0) += 1;
        if self.count() > self.max_entries {
            self.prune();
        }
        self.save();
    }

    /// Từ đã học cho đúng khoá này, chọn nhiều lần nhất trước.
    pub fn words(&self, key: &str) -> Vec<String> {
        let Some(m) = self.entries.get(key) else { return vec![] };
        let mut v: Vec<(&String, &i64)> = m.iter().collect();
        v.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
        v.into_iter().map(|(k, _)| k.clone()).collect()
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        if let Some(w) = &self.writer {
            let _ = w.send(Write::Remove);
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(&self.entries).unwrap_or_else(|_| "{}".into())
    }

    pub fn file(&self) -> Option<&PathBuf> {
        self.file.as_ref()
    }

    /// Giữ lại các mục được chọn nhiều nhất.
    fn prune(&mut self) {
        let mut flat: Vec<(String, String, i64)> = vec![];
        for (k, m) in &self.entries {
            for (t, n) in m {
                flat.push((k.clone(), t.clone(), *n));
            }
        }
        flat.sort_by(|a, b| b.2.cmp(&a.2).then_with(|| a.0.cmp(&b.0)).then_with(|| a.1.cmp(&b.1)));
        self.entries.clear();
        for (k, t, n) in flat.into_iter().take(self.max_entries * 9 / 10) {
            self.entries.entry(k).or_default().insert(t, n);
        }
    }

    fn save(&self) {
        if let Some(w) = &self.writer {
            let _ = w.send(Write::Save(self.to_json()));
        }
    }
}
