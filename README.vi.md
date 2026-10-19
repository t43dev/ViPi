<p align="center"><img src="assets/logo-256.png" width="128" alt="ViPi logo"></p>

<h1 align="center">ViPi</h1>

<p align="center">
  <b>Gõ tiếng Việt và tiếng Trung trên cùng một bàn phím Mac. Một phím tắt để đổi.</b><br>
  Telex + Pinyin trong một app nhỏ trên thanh menu. Miễn phí, mã nguồn mở, chạy 100% offline.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/kulinh/ViPi?label=release&color=c8102e" alt="Bản mới nhất"></a>
  <a href="../../releases"><img src="https://img.shields.io/github/downloads/kulinh/ViPi/total?label=downloads&color=f5b82e" alt="Lượt tải"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Apple-notarized-2ea44f?logo=apple&logoColor=white" alt="Đã được Apple chứng thực">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0"></a>
</p>

<p align="center">
  <a href="../../releases/latest/download/ViPi.dmg"><img src="https://img.shields.io/badge/T%E1%BA%A3i_cho_macOS-ViPi.dmg-c8102e?style=for-the-badge&logo=apple&logoColor=white" alt="Tải ViPi cho macOS"></a>
</p>

<p align="center"><a href="README.md">English</a> · <b>Tiếng Việt</b> · <a href="README.zh-CN.md">简体中文</a></p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/readme/hero-dark.png">
    <img src="assets/readme/hero-light.png" alt="ViPi gõ tiếng Việt bằng Telex và tiếng Trung bằng Pinyin trong cùng một ghi chú" width="100%">
  </picture>
</p>

---

## 🤔 Vì sao nên dùng ViPi?

Nếu bạn viết cả tiếng Việt lẫn tiếng Trung, máy Mac của bạn có lẽ đang thế này:

- ❌ Một bộ gõ tiếng Việt, bộ Pinyin của Apple và ABC: **ba nguồn nhập, hai bộ gõ** giành nhau bàn phím
- ❌ ⌃Space xoay vòng qua tất cả, nên phải **bấm đi bấm lại** mới tới đúng ngôn ngữ
- ❌ Đang gõ câu tiếng Anh thì chữ bị biến thành tiếng Việt
- ❌ Bỗng một ngày mọi bộ gõ **không gõ được nữa** mà chẳng biết vì sao

**ViPi giải quyết hết:**

- ✅ **Một app, một phím tắt.** `⌃ Control` + `⇧ Shift` quay ngay về ngôn ngữ vừa dùng
- ✅ **Tiếng Anh vẫn là tiếng Anh.** `user`, `data`, `class` ra đúng như gõ, không cần chuyển bộ gõ
- ✅ **Pinyin ngay tại con trỏ.** Ô gợi ý hiện đúng chỗ đang gõ, gõ cả câu ra cả câu
- ✅ **Hết treo bí ẩn.** Công cụ theo dõi Secure Input chỉ đích danh app đang khoá bàn phím

## ⚡ Cài đặt trong chưa đầy một phút

1. **[Tải ViPi.dmg](../../releases/latest/download/ViPi.dmg)**, mở ra rồi kéo **ViPi** vào **Applications**.
2. Mở ViPi và cho phép trong **System Settings → Privacy & Security → Accessibility**. ViPi chạy ngay trong vòng 2 giây.
3. Bấm **`⌃ Control` + `⇧ Shift`** và gõ thôi. 🎉

> **Mẹo:** tắt các bộ gõ tiếng Việt khác (UniKey, EVKey, GoNhanh…) và chỉ giữ nguồn nhập **ABC**, để chỉ một mình ViPi xử lý phím gõ.

## ✨ Tính năng

### 🇻🇳 Telex nhanh như tay bạn gõ

| Bạn gõ | Bạn được | |
|:--|:--|:--|
| `tieengs Vieetj` | **tiếng Việt** | Telex kiểu UniKey: `aa` `aw` `ee` `oo` `ow` `uw` `dd`, dấu `s f r x j` |
| `tosan` | **toán** | gõ dấu ở đâu trong từ cũng được |
| `ass` | **as** | bấm một phím hai lần để bỏ dấu vừa gõ |
| `user data class` | **user data class** | gõ xong từ tiếng Anh là tự trả lại nguyên dạng |
| `vn` + Space | **Việt Nam** | gõ tắt theo danh sách của bạn, `VN` → `VIỆT NAM` |

- Đặt dấu kiểu cũ (`hòa`) hoặc kiểu mới (`hoà`), bật/tắt kiểm tra chính tả.
- **Nhanh và chắc:** đã thử trên máy Mac thật với đủ 8.329 âm tiết hợp lệ ở tốc độ 8–12 ms mỗi phím, cộng thêm 753 âm tiết trên Chrome ở 3 ms mỗi phím, không mất một phím hay một dấu nào.

### 🇨🇳 Pinyin có ô gợi ý thật sự

| Bạn gõ | Bạn được | |
|:--|:--|:--|
| `nihao` | **你好** | pinyin đầy đủ, `v` = ü |
| `nh` | **你好** | chỉ gõ phụ âm đầu |
| `nih` | **你好** | âm cuối gõ dở vẫn ra chữ |
| `woshizhongguoren` | **我是中国人** | gõ cả câu một lần |
| `xi'an` | **西安** | `'` để tách âm |

`1`–`9` hoặc `Space` để chọn · `←` `→` di chuyển · `-` `=` hoặc `↑` `↓` lật trang · `Enter` gõ nguyên pinyin · `Esc` huỷ · dấu câu toàn khổ `，。？！`

### ⌨️ Một phím tắt cho mọi ngôn ngữ

Bấm **`⌃ Control` + `⇧ Shift`** một lần để quay về bộ gõ trước, bấm nhanh hai lần để sang bộ tiếp theo. Thứ tự theo lần dùng gần nhất, giống ⌘Tab nhưng cho ngôn ngữ: **VI ⇄ 拼 ⇄ EN**. Thích Option+Shift hay Control+Space hơn? Đổi trong Cài đặt.

### 🛡️ Theo dõi Secure Input

Khi một ô mật khẩu hay cửa sổ terminal bật Secure Input của macOS, mọi bộ gõ đều im lặng. ViPi đổi biểu tượng trên thanh menu thành 🔒 và cho biết **app nào** đang giữ nó, kèm PID, đường dẫn, lịch sử và nút Show/Quit.

### 🎨 Hoà hợp với máy Mac của bạn

- **Ngôn ngữ của bạn:** toàn bộ giao diện có tiếng Anh, tiếng Việt và tiếng Trung giản thể.
- **Sáng hoặc Tối:** theo macOS hoặc tự chọn (từ bản 0.2.2).
- **Tự cập nhật:** ViPi kiểm tra GitHub, xác minh bản tải về có chữ ký của nhà phát triển ViPi, cài đặt và khởi động lại khi bạn ngừng gõ.
- **Tự chạy khi đăng nhập**, nằm gọn trên thanh menu.

<table>
  <tr>
    <td><img src="assets/readme/settings-general-vi.png" alt="Cài đặt chung"></td>
    <td><img src="assets/readme/settings-vietnamese-vi.png" alt="Cài đặt tiếng Việt"></td>
    <td><img src="assets/readme/settings-shortcuts-vi.png" alt="Gõ tắt"></td>
  </tr>
  <tr>
    <td align="center"><sub>Ngôn ngữ, giao diện, phím tắt</sub></td>
    <td align="center"><sub>Chính tả và kiểu đặt dấu</sub></td>
    <td align="center"><sub>Gõ tắt</sub></td>
  </tr>
</table>

## 🔒 Cam kết

- 🚫 **Không thu phí.** Miễn phí mãi mãi, giấy phép GPL-3.0, không có bản Pro.
- 🚫 **Không theo dõi.** Phím gõ được xử lý ngay trên máy và không bao giờ rời khỏi máy. Kết nối mạng duy nhất là kiểm tra cập nhật trên GitHub.
- 🚫 **Không quảng cáo, không tài khoản, không làm phiền.**
- ✅ **Có chữ ký và được Apple chứng thực (notarized)**, nên macOS mở không cảnh báo và quyền Accessibility được giữ nguyên qua các lần cập nhật.

## ❓ Hỏi đáp

<details>
<summary><b>ViPi bỗng không gõ được trong mọi app</b></summary>

Có app vừa bật Secure Input (ô mật khẩu, terminal bật "Secure Keyboard Entry", trình quản lý mật khẩu…). Biểu tượng trên thanh menu hiện 🔒. Mở **menu → Theo dõi Secure Input…** để xem app nào, rồi đóng ô đó hoặc thoát app đó.
</details>

<details>
<summary><b>Một từ tiếng Anh bị biến thành tiếng Việt</b></summary>

Những từ trùng với âm tiết tiếng Việt có thật, như `of` → `ò`, thì không thể tự phân biệt. Bấm phím dấu hai lần (`off` → `of`) hoặc chuyển sang tiếng Anh bằng `⌃ Control` + `⇧ Shift`.
</details>

<details>
<summary><b>Có phải gỡ UniKey, EVKey hay GoNhanh không?</b></summary>

Không cần, chỉ cần tắt chúng khi dùng ViPi. Hai bộ gõ cùng sửa một phím gõ sẽ giành nhau.
</details>

<details>
<summary><b>ViPi chạy trên máy Mac nào?</b></summary>

macOS 13 Ventura trở lên, cả chip Apple lẫn Intel.
</details>

<details>
<summary><b>Gỡ ViPi thế nào?</b></summary>

Chọn **Thoát ViPi** trong menu của nó, rồi kéo ViPi từ Applications vào Thùng rác.
</details>

## 💡 Vì sao có ViPi

Mình gõ tiếng Việt và tiếng Trung hằng ngày, nhưng trên macOS không có cách nào gõ cả hai cho hợp lý. Cách thường dùng là cài một bộ gõ tiếng Việt, thêm bộ Pinyin của Apple, cộng với tiếng Anh. Thế là phải chuyển qua lại giữa ba nguồn nhập, và hai bộ gõ còn hay giành bàn phím của nhau. ViPi gộp Telex và Pinyin vào một app nhỏ, chỉ cần một phím tắt để đổi ngôn ngữ.

ViPi còn mới. Gặp chỗ nào chưa ổn xin [báo ở Issues](../../issues). Nếu ViPi giúp bạn gõ nhẹ nhàng hơn, một ⭐ sẽ giúp người khác tìm thấy nó.

<details>
<summary><h2>🛠️ Tự build từ mã nguồn</h2></summary>

macOS 13+, Xcode command line tools:

```sh
swift test                           # bộ xử lý Telex/Pinyin (chạy được cả trên Linux)
VERSION=0.1.0 scripts/build-app.sh   # → build/ViPi.app + build/ViPi-0.1.0.zip (ký ad-hoc)
```

Có `SIGN_IDENTITY="Developer ID Application: …"` thì script ký với hardened runtime và đóng `build/ViPi-x.y.z.dmg`; có thêm `NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` (API key App Store Connect) thì notarize và staple luôn DMG. `scripts/mac-release.sh <version>` làm tất cả trên một máy Mac build rồi đính DMG vào GitHub release `v<version>`.

`open -n /Applications/ViPi.app --args --selftest <words.txt> <out.txt> [gapMs] [holdMs] [variant]` gõ từng từ qua ViPi đang chạy, các phím đè lên nhau như gõ nhanh thật, rồi báo từ nào ra sai.

CI (`.github/workflows/build.yml`) chạy test và đưa bản build chưa ký lên làm artifact.

Từ điển Pinyin `Resources/pinyin.tsv` được tạo từ [rime-ice](https://github.com/iDvel/rime-ice) bằng `scripts/build_pinyin_dict.py`.
</details>

## 📄 Giấy phép

GPL-3.0. Quy tắc Telex và bảng nguyên âm theo [UniKey](https://www.unikey.org) (GPL); từ điển Pinyin lấy từ [rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0); danh sách âm tiết tiếng Việt lấy từ [danh sách từ của Hồ Ngọc Đức](https://github.com/duyet/vietnamese-wordlist) (GPL). Ý nghĩa màu đỏ vàng, chữ V–P lồng nhau và ngôi sao trên logo xem ở [assets/logo-meaning.md](assets/logo-meaning.md).
