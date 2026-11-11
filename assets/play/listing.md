# ViPi on Google Play

Text and answers for Play Console. Limits: name 30, short description 80, full description 4000 characters.

## App signing (do this before the first upload)

Keep the existing release key so that people who installed the APK from GitHub can move to Play without uninstalling. In Play Console, under App integrity, App signing, choose to use a different key and export it from a Java keystore. Download `pepk.jar` and the encryption key from that page, then run the command the page shows. It has this shape, and asks for the passwords itself:

```
java -jar pepk.jar --keystore=$ANDROID_KEYSTORE --alias=${ANDROID_KEY_ALIAS:-vipi} --output=build/vipi-pepk.zip --include-cert --rsa-aes-encryption --encryption-key-path=<encryption key from Console>
```

Upload `build/vipi-pepk.zip`. This cannot be changed once a release reaches open testing or production.

## Store listing

**App name (all languages):** ViPi: Vietnamese & Pinyin

**Category:** Tools. **Price:** Free. **Privacy policy:** https://vipi.t43.app/privacy. **Website:** https://vipi.t43.app

### English (en-US, default)

Short description:

> Type Vietnamese with Telex and Chinese with Pinyin on one private keyboard.

Full description:

```
ViPi is a keyboard for people who write in Vietnamese, Chinese and English every day.

VIETNAMESE AND ENGLISH, WITHOUT SWITCHING
Type Telex and ViPi tells the two languages apart as you go: treen becomes trên, and server stays server. Spell checking only adds marks where they make a real Vietnamese syllable, and words that are not Vietnamese go back to what you typed.

CHINESE PINYIN
Tap the globe key for Pinyin, with a large word list and suggestions that follow what you have just typed. Choose Simplified or Traditional characters, turn on fuzzy Pinyin for sounds you mix up, and use full-width punctuation. Words you pick can come first next time.

MADE FOR YOUR PHONE
• Hold a key on the top row for its number
• Clipboard history that keeps your last 6 items for one hour
• Light and dark themes, with Material You colors on Android 12 and later
• On an unfolded phone or a tablet, split the keyboard around the fold, keep it in the middle, or float it anywhere

YOUR TYPING STAYS ON YOUR PHONE
ViPi has no internet permission, so it cannot send what you type anywhere. There are no accounts, ads or analytics. Learned words and clipboard history stay on your phone.

FREE AND OPEN SOURCE
ViPi is free software under GPL-3.0. Read the code at github.com/t43dev/ViPi.

To start, open ViPi, tap Turn on ViPi in Settings, then Switch to ViPi. Android shows its usual notice for any keyboard you turn on; ViPi does not collect what you type.
```

### Tiếng Việt (vi)

Short description:

> Gõ tiếng Việt kiểu Telex và tiếng Trung Pinyin trên một bàn phím riêng tư.

Full description:

```
ViPi là bàn phím cho người viết tiếng Việt, tiếng Trung và tiếng Anh mỗi ngày.

TIẾNG VIỆT VÀ TIẾNG ANH, KHÔNG CẦN CHUYỂN
Cứ gõ Telex, ViPi tự phân biệt hai thứ tiếng: treen thành trên, còn server vẫn là server. Kiểm tra chính tả chỉ thêm dấu khi tạo thành âm tiết tiếng Việt thật, và từ không phải tiếng Việt sẽ trở về đúng phím đã gõ.

TIẾNG TRUNG PINYIN
Chạm phím quả địa cầu để gõ Pinyin, với kho từ lớn và gợi ý theo những gì vừa gõ. Chọn chữ Giản thể hoặc Phồn thể, bật Pinyin gần đúng cho những âm hay nhầm, và dùng dấu câu toàn khổ. Từ đã chọn có thể được ưu tiên ở lần sau.

HỢP VỚI ĐIỆN THOẠI CỦA BẠN
• Giữ một phím ở hàng trên cùng để gõ số
• Lịch sử bảng tạm giữ 6 mục gần nhất trong một giờ
• Giao diện sáng và tối, màu Material You từ Android 12
• Trên điện thoại mở gập hoặc máy tính bảng: tách đôi bàn phím quanh nếp gấp, đặt ở giữa, hoặc thả nổi ở bất kỳ đâu

NHỮNG GÌ BẠN GÕ Ở LẠI TRÊN MÁY
ViPi không có quyền truy cập Internet nên không thể gửi đi những gì bạn gõ. Không tài khoản, không quảng cáo, không thống kê. Từ đã học và lịch sử bảng tạm chỉ nằm trên điện thoại của bạn.

MIỄN PHÍ VÀ MÃ NGUỒN MỞ
ViPi là phần mềm tự do theo giấy phép GPL-3.0. Xem mã nguồn tại github.com/t43dev/ViPi.

Để bắt đầu, mở ViPi, chạm Turn on ViPi in Settings, rồi Switch to ViPi. Android sẽ hiện thông báo thường lệ cho mọi bàn phím mới bật; ViPi không thu thập những gì bạn gõ.
```

### 简体中文 (zh-CN)

Short description:

> 在同一个私密键盘上，用 Telex 输入越南语，用拼音输入中文。

Full description:

```
ViPi 是为每天使用越南语、中文和英语的人设计的键盘。

越南语和英语，无需切换
直接用 Telex 输入，ViPi 会自动区分两种语言：treen 变成 trên，server 仍是 server。拼写检查只在能组成真实越南语音节时才加声调，不是越南语的词会恢复为原来输入的字母。

中文拼音
点按地球键即可输入拼音，词库丰富，并根据刚输入的内容给出建议。可选简体或繁体，为容易混淆的读音开启模糊拼音，并使用全角标点。选过的词下次可以优先显示。

为手机而设计
• 长按第一排按键输入数字
• 剪贴板历史保留最近 6 项，时长一小时
• 浅色和深色主题，Android 12 及以上支持 Material You 配色
• 在展开的折叠屏或平板上，可将键盘分开放在折痕两侧、居中，或浮动到任意位置

输入内容只留在手机上
ViPi 没有联网权限，无法将您输入的内容发送到任何地方。没有账户、广告或统计。学习的词语和剪贴板历史只保存在您的手机上。

免费开源
ViPi 是遵循 GPL-3.0 的自由软件。源代码：github.com/t43dev/ViPi。

开始使用：打开 ViPi，点按 Turn on ViPi in Settings，然后点按 Switch to ViPi。Android 对任何新启用的键盘都会显示常规提示；ViPi 不会收集您输入的内容。
```

### Release notes (0.3.4, en-US)

```
First release on Google Play. Vietnamese Telex and Chinese Pinyin on one keyboard, with no internet permission.
```

## Graphics (this folder)

- `icon-512.png`: app icon, 512 × 512
- `feature-1024x500.png`: feature graphic
- `phone-*.png`: phone screenshots, 1080 × 1920, no alpha

## App content answers

| Form | Answer |
|---|---|
| Privacy policy | https://vipi.t43.app/privacy |
| Ads | No ads |
| App access | All functionality is available without special access |
| Content rating | Category: Utility, Productivity, Communication, or Other. Every content question: No. No user interaction, no sharing of location, no purchases |
| Target audience | 13 and over. Do not select any age under 13 |
| News app | No |
| Health apps | None |
| Financial features | None |
| Government app | No |
| Advertising ID | No |
| Data safety | "Does your app collect or share any of the required user data types?" No. ViPi has no internet permission and nothing leaves the device |

## Notes for app review

```
ViPi is an input method. To use it: open ViPi, tap "Turn on ViPi in Settings", enable ViPi, return, tap "Switch to ViPi", then type in the "Try it here" field. No account or login is needed. The app has no INTERNET permission. Learned words and clipboard history stay in private app storage on the device.
```
