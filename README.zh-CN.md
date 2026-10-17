<p align="center"><img src="assets/logo-256.png" width="128" alt="ViPi logo"></p>

<h1 align="center">ViPi</h1>

<p align="center"><b>Vi</b>越南语 Telex + <b>Pi</b>拼音：为同时输入越南语和中文的人打造的 macOS 输入工具。</p>

<p align="center"><a href="README.md">English</a> · <a href="README.vi.md">Tiếng Việt</a> · <b>简体中文</b></p>

> **Alpha 测试版。** ViPi 刚刚发布，难免有不完善之处，欢迎在 [Issues](../../issues) 反馈。

## 为什么做 ViPi

我每天都要输入越南语和中文，可在 macOS 上一直没有顺手的方案：通常要装一个越南语输入法，再加上苹果自带的拼音和英文，三个输入源来回切换，两个输入法还会互相抢键盘。ViPi 把 Telex 和拼音放进一个小巧的菜单栏应用，一个快捷键就能切换语言。

## 功能

- **越南语（Telex）**，规则与 UniKey 一致：`aa→â aw→ă ee→ê oo→ô ow→ơ uw/w→ư dd→đ`，声调 `s f r x j`，`z` 清除声调，同一键连按两次撤销（`ass→as`）。声调可以放在词中任意位置（`tosan→toán`），自动还原英文：一个词输入结束时，如果结果不是真实存在的越南语音节，ViPi 会按原样重新输入你按下的键（`user`、`data`、`class` 保持英文；与越南语音节相同的词，如 `of→ò`，请用 `Control+Shift` 或双击声调键撤销），可选传统或新式声调位置（`hòa` / `hoà`）。已在真实 Mac 上端到端测试：以每键 8–12 毫秒的速度输入全部 8,329 个有效音节，没有丢失任何按键。
- **中文（拼音）**，候选窗跟随光标：全拼，`'` 分隔音节（`xi'an`），最后一个音节未输完也能出字（`nih→你好`），首字母简拼（`nh→你好`），整句联想（`woshizhongguoren→我是中国人`），分段选词，全角标点。
- **Control+Shift**：按一次回到上一个输入法，快速按两次切换到下一个（按最近使用顺序，与 ⌘Space 相同）。快捷键可在 **Settings** 中修改，例如 Option+Shift 或 Control+Space。
- **安全输入监视器**：显示哪个应用占用了 macOS 的安全输入（Secure Input）。这是所有输入法突然无法输入的常见原因。可查看历史、PID、路径，并可一键显示或退出该应用；安全输入开启时，菜单栏图标会变成锁。
- **快捷短语**：`vn` + 空格 → `Việt Nam`，`ko` → `không`；大小写跟随输入（`VN` → `VIỆT NAM`）。可在 **Settings → Text Shortcuts** 中编辑。
- **设置窗口**（菜单 → Settings…，⌘,）：切换快捷键、拼写检查开关、英文还原、声调位置、快捷短语、全角标点、开机启动、自动更新。
- **开机自动启动**，默认开启。
- **自动更新**：每隔几小时从 GitHub Releases 检查新版本，确认下载文件带有 ViPi 开发者的签名后自动安装，并在你停止打字后重新启动。可在 **About ViPi** 中关闭或手动检查。
- **隐私**：按键只在本机处理，不会发送到任何地方。唯一的联网操作是到 GitHub 检查更新。

## 安装

1. 从 [Releases](../../releases) 下载 `ViPi-x.y.z.dmg`，打开后把 **ViPi** 拖到 **Applications**（应用程序）。
2. 打开 ViPi，在 **系统设置 → 隐私与安全性 → 辅助功能** 中允许它。授权后 2 秒内即可使用。
3. 关闭其他越南语输入法（UniKey、EVKey、GoNhanh 等），输入源使用普通的 **ABC**，让 ViPi 单独处理输入。

发布版使用 Developer ID 签名并经过苹果公证（notarization），macOS 可直接打开，没有安全警告；升级后也无需重新授权辅助功能。需要 macOS 13 或更高版本，支持 Apple 芯片和 Intel。

## 按键

| 模式 | 按键 |
|---|---|
| 越南语 | 按上文 Telex 规则；输入任何非字母字符即结束当前词 |
| 中文 | `a-z` 拼音（`v` = ü）· `1-9` 选词 · `空格` 选择高亮项 · `←/→` 移动 · `-`/`=` 或 `↑/↓` 翻页 · `回车` 输出原始拼音 · `Esc` 取消 · `退格` 修改 / 撤销选词 |
| 任意模式 | `Control+Shift` 回到上一个输入法 · 快速按两次：切换到下一个 |

## 从源码构建

请参阅英文版的 [Build](README.md#build) 一节。

## 许可证

GPL-3.0。Telex 规则和元音表参照 [UniKey](https://www.unikey.org)（GPL）；拼音词库来自 [rime-ice（雾凇拼音）](https://github.com/iDvel/rime-ice)（GPL-3.0）；越南语音节表取自 [Ho Ngoc Duc 的词表](https://github.com/duyet/vietnamese-wordlist)（GPL）。Logo 的红金配色、V–P 连笔和星星的含义见 [assets/logo-meaning.md](assets/logo-meaning.md)。
