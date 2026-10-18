import Foundation

/// Ngôn ngữ giao diện. Chuỗi gốc tiếng Anh là khoá tra bảng dịch; thiếu bản dịch thì hiện tiếng Anh.
enum UILanguage: String, CaseIterable, Identifiable {
    case english = "en", vietnamese = "vi", chinese = "zh-Hans"

    var id: String { rawValue }

    /// Tên hiển thị luôn bằng chính ngôn ngữ đó.
    var name: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        case .chinese: return "简体中文"
        }
    }

    /// Theo ngôn ngữ macOS lúc chưa chọn.
    static var system: UILanguage {
        let first = Locale.preferredLanguages.first ?? "en"
        if first.hasPrefix("vi") { return .vietnamese }
        if first.hasPrefix("zh") { return .chinese }
        return .english
    }

    static var current: UILanguage = .english
}

/// Dịch chuỗi giao diện; `%@` lần lượt thay bằng `args`.
func tr(_ english: String, _ args: String...) -> String {
    let row = translations[english]
    let template: String
    switch UILanguage.current {
    case .english: template = english
    case .vietnamese: template = row?.vi ?? english
    case .chinese: template = row?.zh ?? english
    }
    return args.isEmpty ? template : String(format: template, arguments: args)
}

private let translations: [String: (vi: String, zh: String)] = [
    // Menu, biểu tượng, HUD
    "Vietnamese (Telex)": ("Tiếng Việt (Telex)", "越南语 (Telex)"),
    "Chinese (Pinyin)": ("Tiếng Trung (Pinyin)", "中文 (拼音)"),
    "English": ("Tiếng Anh", "英文"),
    "%@: previous · twice: next": ("%@: bộ gõ trước · hai lần: bộ gõ tiếp", "%@：上一个 · 按两次：下一个"),
    "Secure Input held by %@ — typing blocked": ("Secure Input đang bị %@ giữ — không gõ được", "安全输入被 %@ 占用 — 无法输入"),
    "Waiting for Accessibility permission": ("Đang chờ quyền Trợ năng (Accessibility)", "正在等待辅助功能权限"),
    "unknown": ("không rõ", "未知"),
    "unknown app": ("ứng dụng không rõ", "未知应用"),
    "⚠️ Grant Accessibility Permission…": ("⚠️ Cấp quyền Trợ năng (Accessibility)…", "⚠️ 授予辅助功能权限…"),
    "⬆️ Update to ViPi %@…": ("⬆️ Cập nhật lên ViPi %@…", "⬆️ 更新到 ViPi %@…"),
    "⬆️ Relaunch to Finish Updating to %@": ("⬆️ Mở lại để hoàn tất cập nhật lên %@", "⬆️ 重新启动以完成更新到 %@"),
    "🔒 Secure Input held by %@": ("🔒 Secure Input đang bị %@ giữ", "🔒 安全输入被 %@ 占用"),
    "Settings…": ("Cài đặt…", "设置…"),
    "Secure Input Monitor…": ("Theo dõi Secure Input…", "安全输入监视器…"),
    "Check for Updates…": ("Kiểm tra cập nhật…", "检查更新…"),
    "About ViPi": ("Giới thiệu ViPi", "关于 ViPi"),
    "Quit ViPi": ("Thoát ViPi", "退出 ViPi"),

    // Cài đặt
    "ViPi Settings": ("Cài đặt ViPi", "ViPi 设置"),
    "General": ("Cài đặt", "设置"),
    "Vietnamese": ("Tiếng Việt", "越南语"),
    "Chinese": ("Tiếng Trung", "中文"),
    "Language": ("Ngôn ngữ", "语言"),
    "Switch input": ("Chuyển bộ gõ", "切换输入法"),
    "Press once to go back to the previous input, twice quickly for the next one. Use two or more modifier keys (pressed together, then released), or modifiers plus a key such as Control+Space.":
        ("Bấm một lần để quay về bộ gõ trước, bấm nhanh hai lần để sang bộ gõ tiếp theo. Dùng từ hai phím bổ trợ trở lên (nhấn cùng lúc rồi nhả), hoặc phím bổ trợ cộng một phím, ví dụ Control+Space.",
         "按一次切回上一个输入法，快速按两次切到下一个。可使用两个或以上修饰键（同时按下后松开），或修饰键加一个键，例如 Control+Space。"),
    "Reset to Control+Shift": ("Đặt lại Control+Shift", "恢复为 Control+Shift"),
    "Press the new shortcut…": ("Bấm phím tắt mới…", "请按新的快捷键…"),
    "Launch at login": ("Mở cùng macOS khi đăng nhập", "登录时启动"),
    "Automatically install updates": ("Tự động cài bản cập nhật", "自动安装更新"),
    "Secure Input": ("Secure Input", "安全输入"),
    "Open Monitor…": ("Mở trình theo dõi…", "打开监视器…"),
    "Check spelling": ("Kiểm tra chính tả", "拼写检查"),
    "Only add tone and vowel marks where they make a valid Vietnamese syllable, so English words such as “class” or “window” stay as typed. Turn off to apply every Telex key, like UniKey without spell check.":
        ("Chỉ thêm dấu thanh và dấu mũ khi tạo thành âm tiết tiếng Việt hợp lệ, nhờ vậy từ tiếng Anh như “class” hay “window” được giữ nguyên. Tắt đi thì mọi phím Telex đều có tác dụng, giống UniKey khi tắt kiểm tra chính tả.",
         "仅在能构成有效越南语音节时才加声调和元音符号，因此 “class”、“window” 等英文单词会保持原样。关闭后每个 Telex 键都会生效，与关闭拼写检查的 UniKey 相同。"),
    "Restore non-Vietnamese words": ("Khôi phục từ không phải tiếng Việt", "还原非越南语单词"),
    "When a word ends and the result is not a real Vietnamese syllable, retype the keys you pressed: user, data, more.":
        ("Khi gõ xong một từ mà kết quả không phải âm tiết tiếng Việt có thật, ViPi gõ lại đúng các phím đã bấm: user, data, more.",
         "单词结束时，如果结果不是真实的越南语音节，就还原为实际按下的键：user、data、more。"),
    "Tone placement": ("Vị trí dấu thanh", "声调位置"),
    "Classic (hòa, khỏe, thúy)": ("Kiểu cũ (hòa, khỏe, thúy)", "传统 (hòa, khỏe, thúy)"),
    "Modern (hoà, khoẻ, thuý)": ("Kiểu mới (hoà, khoẻ, thuý)", "新式 (hoà, khoẻ, thuý)"),
    "Text Shortcuts": ("Gõ tắt", "快捷短语"),
    "Use in Vietnamese": ("Dùng khi gõ tiếng Việt", "越南语输入时使用"),
    "Use in English": ("Dùng khi gõ tiếng Anh", "英文输入时使用"),
    "Type a shortcut as its own word, then Space, Return or Tab, to replace it with the full text (call2vn@ stays as typed). Letter case follows what you type: vn → Việt Nam, VN → VIỆT NAM. Not used in Chinese mode, where Space picks a candidate.":
        ("Gõ từ tắt đứng riêng rồi bấm Space, Return hoặc Tab để thay bằng cụm từ đầy đủ (call2vn@ vẫn giữ nguyên). Chữ hoa/thường theo cách gõ: vn → Việt Nam, VN → VIỆT NAM. Không dùng khi gõ tiếng Trung, vì Space dùng để chọn chữ.",
         "将缩写作为独立单词输入，再按空格、回车或 Tab，即替换为完整文本（call2vn@ 保持不变）。大小写跟随输入：vn → Việt Nam，VN → VIỆT NAM。中文输入时不使用，因为空格用于选字。"),
    "Shortcut": ("Từ tắt", "缩写"),
    "Replace with": ("Thay bằng", "替换为"),
    "e.g. vn": ("vd: vn", "例如 vn"),
    "e.g. Việt Nam": ("vd: Việt Nam", "例如 Việt Nam"),
    "%@ shortcuts": ("%@ từ tắt", "%@ 条快捷短语"),
    "Full-width punctuation (，。？！)": ("Dấu câu toàn khổ (，。？！)", "全角标点（，。？！）"),

    // Giới thiệu, cập nhật
    "Version %@ (%@)": ("Phiên bản %@ (%@)", "版本 %@ (%@)"),
    "Vietnamese Telex + Chinese Pinyin in one input tool.\nMade because macOS had no sensible way to type both.":
        ("Telex tiếng Việt + Pinyin tiếng Trung trong một bộ gõ.\nRa đời vì macOS chưa có cách nào gõ cả hai cho tiện.",
         "越南语 Telex + 中文拼音，一个输入工具全搞定。\n因为 macOS 没有顺手的方式同时输入这两种语言。"),
    "Releases": ("Các bản phát hành", "发布版本"),
    "Report an Issue": ("Báo lỗi", "报告问题"),
    "previous input": ("bộ gõ trước", "上一个输入法"),
    "next input": ("bộ gõ tiếp theo", "下一个输入法"),
    "aa â · aw ă · ee ê · oo ô · ow ơ · uw ư · dd đ · s f r x j tones · z clears":
        ("aa â · aw ă · ee ê · oo ô · ow ơ · uw ư · dd đ · s f r x j dấu thanh · z xoá dấu",
         "aa â · aw ă · ee ê · oo ô · ow ơ · uw ư · dd đ · s f r x j 声调 · z 清除"),
    "1–9 pick · Space highlighted · −/= page · Enter raw · Esc cancel":
        ("1–9 chọn · Space chọn từ đang sáng · −/= lật trang · Enter giữ chữ gõ · Esc huỷ",
         "1–9 选词 · 空格 选高亮项 · −/= 翻页 · 回车 输入原文 · Esc 取消"),
    "Development build: automatic updates are off.": ("Bản phát triển: tự động cập nhật đang tắt.", "开发版：自动更新已关闭。"),
    "Telex rules:": ("Quy tắc Telex:", "Telex 规则："),
    "· Pinyin dictionary:": ("· Từ điển Pinyin:", "· 拼音词库："),
    "© 2026 ViPi contributors · Free software under the": ("© 2026 các tác giả ViPi · Phần mềm tự do theo giấy phép", "© 2026 ViPi 贡献者 · 自由软件，许可证为"),
    "Updates come from GitHub Releases.": ("Bản cập nhật lấy từ GitHub Releases.", "更新来自 GitHub Releases。"),
    "Checking for updates…": ("Đang kiểm tra bản cập nhật…", "正在检查更新…"),
    "ViPi is up to date.": ("ViPi đã là bản mới nhất.", "ViPi 已是最新版本。"),
    "ViPi %@ is available.": ("Đã có ViPi %@.", "ViPi %@ 已可更新。"),
    "Installing ViPi %@…": ("Đang cài ViPi %@…", "正在安装 ViPi %@…"),
    "ViPi %@ is installed.": ("Đã cài ViPi %@.", "ViPi %@ 已安装。"),
    "Install and Relaunch": ("Cài và mở lại", "安装并重新启动"),
    "Relaunch Now": ("Mở lại ngay", "立即重新启动"),
    "Check for Updates": ("Kiểm tra cập nhật", "检查更新"),
    "Could not reach GitHub: %@": ("Không kết nối được GitHub: %@", "无法连接 GitHub：%@"),
    "Download failed (HTTP %@)": ("Tải về thất bại (HTTP %@)", "下载失败（HTTP %@）"),
    "Cannot replace %@. Open the DMG from GitHub and drag ViPi to Applications.":
        ("Không thay được %@. Hãy mở file DMG tải từ GitHub rồi kéo ViPi vào Applications.",
         "无法替换 %@。请打开从 GitHub 下载的 DMG，把 ViPi 拖到“应用程序”文件夹。"),
    "The update is not signed by the ViPi developer": ("Bản cập nhật không được ký bởi nhà phát triển ViPi", "此更新未经 ViPi 开发者签名"),
    "%@ failed": ("%@ bị lỗi", "%@ 执行失败"),

    // Theo dõi Secure Input
    "Secure Input Monitor": ("Theo dõi Secure Input", "安全输入监视器"),
    "While any app holds Secure Input, macOS hides keystrokes from every input tool, so ViPi cannot type. Usual holders: a focused password field, Terminal/iTerm “Secure Keyboard Entry”, password managers, or loginwindow after the screen was locked. Quitting or switching away from the holder releases it.":
        ("Khi có ứng dụng giữ Secure Input, macOS giấu phím gõ khỏi mọi bộ gõ nên ViPi không gõ được. Thường gặp: ô mật khẩu đang được chọn, “Secure Keyboard Entry” của Terminal/iTerm, trình quản lý mật khẩu, hoặc loginwindow sau khi khoá màn hình. Thoát hoặc chuyển khỏi ứng dụng đó là Secure Input được nhả.",
         "只要有应用占用安全输入，macOS 就会对所有输入法隐藏按键，ViPi 因此无法输入。常见占用者：获得焦点的密码框、终端/iTerm 的“安全键盘输入”、密码管理器，或锁屏后的 loginwindow。退出或切换离开该应用即可释放。"),
    "History": ("Lịch sử", "历史记录"),
    "Time": ("Thời gian", "时间"),
    "Event": ("Sự kiện", "事件"),
    "App": ("Ứng dụng", "应用"),
    "Path": ("Đường dẫn", "路径"),
    "Enabled": ("Bật", "开启"),
    "Released": ("Nhả", "释放"),
    "Secure Input is ON — typing is blocked": ("Secure Input đang BẬT — không gõ được", "安全输入已开启 — 无法输入"),
    "Held by %@ (PID %@)": ("Đang bị %@ giữ (PID %@)", "被 %@ 占用（PID %@）"),
    "Holder unknown": ("Không rõ ứng dụng nào giữ", "占用者未知"),
    "Since %@": ("Từ %@", "开始于 %@"),
    "Secure Input is off — ViPi can type": ("Secure Input đang tắt — ViPi gõ bình thường", "安全输入已关闭 — ViPi 可正常输入"),
    "Show App": ("Hiện ứng dụng", "显示应用"),
    "Reveal in Finder": ("Mở trong Finder", "在访达中显示"),
    "Quit %@": ("Thoát %@", "退出 %@"),
]
