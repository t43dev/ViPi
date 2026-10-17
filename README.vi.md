<p align="center"><img src="assets/logo-256.png" width="128" alt="ViPi logo"></p>

<h1 align="center">ViPi</h1>

<p align="center"><b>Vi</b>ệt Telex + <b>Pi</b>nyin: một bộ gõ macOS cho người gõ cả tiếng Việt lẫn tiếng Trung.</p>

<p align="center"><a href="README.md">English</a> · <b>Tiếng Việt</b> · <a href="README.zh-CN.md">简体中文</a></p>

> **Bản alpha.** ViPi còn mới, chắc chắn còn chỗ chưa ổn. Gặp lỗi gì xin báo ở [Issues](../../issues).

## Vì sao có ViPi

Mình gõ tiếng Việt và tiếng Trung hằng ngày, nhưng trên macOS không có cách nào gõ cả hai cho hợp lý. Cách thường dùng là cài một bộ gõ tiếng Việt, thêm bộ Pinyin của Apple, cộng với tiếng Anh. Thế là phải chuyển qua lại giữa ba nguồn nhập, và hai bộ gõ còn hay giành bàn phím của nhau. ViPi gộp Telex và Pinyin vào một app nhỏ trên thanh menu, chỉ cần một phím tắt để đổi ngôn ngữ.

## Tính năng

- **Tiếng Việt (Telex)** theo quy tắc UniKey: `aa→â aw→ă ee→ê oo→ô ow→ơ uw/w→ư dd→đ`, dấu thanh `s f r x j`, `z` xoá dấu, gõ một phím hai lần để bỏ dấu vừa gõ (`ass→as`). Có thể gõ dấu ở bất kỳ đâu trong từ (`tosan→toán`), có kiểm tra chính tả nên từ tiếng Anh giữ nguyên (`class`, `text`), chọn được kiểu đặt dấu cũ hoặc mới (`hòa` / `hoà`). Đã thử trên máy Mac thật: gõ đủ 8.329 âm tiết hợp lệ với tốc độ 8–12 ms mỗi phím, không mất phím nào.
- **Tiếng Trung (Pinyin)**, ô gợi ý hiện ngay cạnh con trỏ: gõ pinyin đầy đủ, dùng `'` để tách âm (`xi'an`), âm cuối gõ dở vẫn ra chữ (`nih→你好`), gõ tắt bằng phụ âm đầu (`nh→你好`), gợi ý nguyên câu (`woshizhongguoren→我是中国人`), chọn từng phần, dấu câu toàn khổ (full-width).
- **Control+Shift**: bấm một lần để quay về bộ gõ vừa dùng, bấm nhanh hai lần để sang bộ tiếp theo (theo thứ tự dùng gần nhất, giống ⌘Space).
- **Theo dõi Secure Input**: cho biết app nào đang giữ Secure Input của macOS, lý do thường gặp khiến mọi bộ gõ bỗng dưng không gõ được. Có lịch sử, PID, đường dẫn, nút Show/Quit. Biểu tượng trên thanh menu chuyển thành ổ khoá khi Secure Input đang bật.
- **Khởi động cùng máy**, bật sẵn.
- **Riêng tư**: ViPi không có mã kết nối mạng. Phím gõ được xử lý ngay trên máy, không gửi đi đâu.

## Cài đặt

1. Tải `ViPi-x.y.z.dmg` ở [Releases](../../releases), mở ra và kéo **ViPi** vào **Applications**.
2. Mở ViPi rồi cho phép ở **System Settings → Privacy & Security → Accessibility**. ViPi chạy trong vòng 2 giây sau khi được cấp quyền.
3. Tắt các bộ gõ tiếng Việt khác (UniKey, EVKey, GoNhanh…) và dùng nguồn nhập **ABC** thường, để chỉ mình ViPi xử lý chữ gõ.

Bản phát hành được ký Developer ID và đã được Apple notarize, nên macOS mở thẳng không cảnh báo, cập nhật bản mới cũng không phải cấp lại quyền Accessibility. Cần macOS 13 trở lên, chạy được trên cả Apple silicon và Intel.

## Phím

| Chế độ | Phím |
|---|---|
| Tiếng Việt | Telex như trên; gõ bất kỳ ký tự nào không phải chữ cái là kết thúc từ |
| Tiếng Trung | `a-z` pinyin (`v` = ü) · `1-9` chọn · `Space` chọn ô đang sáng · `←/→` di chuyển · `-`/`=` hoặc `↑/↓` lật trang · `Enter` gõ nguyên pinyin · `Esc` huỷ · `Backspace` sửa / bỏ lựa chọn |
| Mọi chế độ | `Control+Shift` về bộ gõ trước · bấm nhanh hai lần: sang bộ tiếp theo |

## Build từ mã nguồn

Xem mục [Build](README.md#build) trong bản tiếng Anh.

## Giấy phép

GPL-3.0. Quy tắc Telex và bảng nguyên âm theo [UniKey](https://www.unikey.org) (GPL); từ điển Pinyin lấy từ [rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0). Ý nghĩa logo (màu đỏ vàng, chữ V–P liền nét, ngôi sao) xem ở [assets/logo-meaning.md](assets/logo-meaning.md).
