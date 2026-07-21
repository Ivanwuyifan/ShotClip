# ShotClip

**English** · [中文](#中文)

A menu-bar macOS app that gives you a hotkey-summoned card wall at the bottom of the screen — your recent **screenshots** and **clipboard history** in one place. Drag a card into any app, or click to copy. Everything is stored temporarily and auto-expires after 30 days.

![menu bar app](icon_1024.png)

## Features

- **⌘⇧4** — capture a screen region straight into ShotClip's own store (not the Desktop).
  - > **Turn off the native ⌘⇧4 first** so it doesn't clash: *System Settings → Keyboard → Keyboard Shortcuts… → Screenshots*, uncheck **"Save picture of selected area as a file"** (and the copy-to-clipboard one).
- **Edit mode** — a menu-bar toggle (**off by default**). When on, ⌘⇧4 opens a built-in **annotation editor** before the shot is stored; when off, the shot goes straight to the store + clipboard + send panel.
- **Annotation editor** (edit mode on) — a floating window with a toolbar:
  - **Rectangle / Ellipse / Arrow / Pen / Text / Mosaic** — draw on the shot; pick a colour from the swatch row (the selected colour is highlighted).
  - **Mosaic** is a brush — hold and drag, and everything the stroke passes over is pixellated (blur out sensitive info).
  - **Text** — click to type; switching colour while editing recolours the text you're typing.
  - **OCR** — recognise text in the shot (offline, macOS Vision; Chinese + English) and copy it to the clipboard.
  - **Scrolling Capture** — select a region and scroll manually; ShotClip grabs frames and stitches them into one tall image.
  - **Undo** (⌘Z), **Save to file**, **✓ Done** (copy + send), **✕ Cancel** (Esc / Return to finish).
  - Small screenshots keep their original size — the editor centers them with a black letterbox instead of stretching. The exported image has no letterbox.
  - The editor window only moves by its title bar — dragging on the image draws, it doesn't move the window.
- **Scrolling Capture** — also available directly from the menu bar (**Scrolling Capture…**): select a region, scroll the content yourself, and ShotClip stitches it into a long image. Needs only Screen Recording (no synthetic scrolling).
- **Permissions & Setup guide** — on first launch a welcome window explains the app and lets you grant each permission with one click (Screen Recording, Accessibility, and freeing up ⌘⇧4). Reopen it any time from the menu bar → **Permissions & Setup…**.
- **⌘⇧Space** — toggle the bottom card wall (click anywhere outside it to dismiss).
- One scrolling row, screenshots and clipboard mixed, newest first:
  - 🟢 **Screenshot** — screenshot thumbnail
  - 🔵 **Image** — copied image
  - 🟣 **Link** — copied URL
  - 🟡 **Text** — copied text
- **Drag** a card into any app:
  - Screenshot / image → drops the **file path** (drag into Ghostty to get the image path)
  - Text / link → drops the **text itself**
- **Click** a card = copy it back to the clipboard:
  - Screenshot / image → copies the **image** (paste with ⌘V into chat / docs)
  - Text / link → copies the text
  - A prominent glow + **✓ Copied** badge confirms the copy
- **Auto-copy on capture** — after ⌘⇧4 the screenshot is already on the clipboard, ⌘V anywhere.
- **Send-to-app panel** — after capture, pick a running app and the screenshot is auto-pasted (terminals get the path, other apps get the image). Recently-used apps sort first; irrelevant apps (Calendar, Finder, …) are filtered out.
- **Auto-hide** — disappears 5s after showing (hovering resets the timer), or right after a drag.
- **Extract Text from Screen (⌘⇧E)** — select any on-screen region and ShotClip OCRs it (offline, macOS Vision, Chinese + English) and puts the text on the clipboard + into the history. Perfect for text that apps won't let you copy (images, PDFs, video subtitles, protected UIs).
- **Translate Screenshot (⌘⇧T)** — select a region; its text is OCR'd and translated by your configured AI backend, shown in a popup and auto-copied.
- **Translate Selection (⌘⇧L)** — select text in any app, hit the hotkey, get the translation in a popup (auto-copied). Target language configurable; default auto-swaps 中 ↔ EN.
- **AI Settings…** — pick the translation backend:
  - **Claude Code (subscription)** — uses the `claude` CLI you're already logged into; no API key needed.
  - **Codex (ChatGPT subscription)** — uses the `codex` CLI login; no API key needed.
  - **Anthropic API key** or any **OpenAI-compatible endpoint** (base URL + key + model). Keys are stored in the macOS Keychain, never in plain text.
- **Clipboard History panel (⌘⇧V)** — a searchable vertical list of everything you've copied (up to 200 entries): text, links, images, screenshots. Type to filter, click to copy.
- **Temporary + auto-expiry** — everything lives in a temp dir and is purged after 30 days (max 40 screenshots, 200 clipboard entries).
- **Self-update** — checks GitHub Releases on launch (and via the menu); downloads, replaces itself, and relaunches.

## Install / Build

Requires a Swift toolchain (Xcode or Command Line Tools).

```bash
git clone https://github.com/Ivanwuyifan/ShotClip.git
cd ShotClip
./build_app.sh        # builds release + packages ShotClip.app (self-signed; permissions survive rebuilds)
open ShotClip.app
```

A ShotClip icon appears in the menu bar with **Show bar / Capture region / Scrolling Capture / Edit mode / Permissions & Setup / Check for Updates / Quit**.

> Or grab the packaged `ShotClip.app.zip` from [Releases](https://github.com/Ivanwuyifan/ShotClip/releases/latest). The zip contains `ShotClip.app` and **`install.command`** — double-click `install.command` to copy it into Applications, clear the quarantine flag, and launch it (this avoids the "unidentified developer / damaged" prompt for the self-signed build, and lets self-update work). Or move `ShotClip.app` into Applications yourself and right-click → Open on first launch.

## First-run system settings

### 1. Screen Recording (required for capture)

macOS prompts on the first ⌘⇧4. Enable **ShotClip** in
*System Settings → Privacy & Security → Screen Recording*, then relaunch.

> The app is signed with a fixed self-signed cert (`build_app.sh` handles it), so you grant this **once** — rebuilds won't revoke it.

### 2. Accessibility (for auto-paste to apps)

The send-to-app auto-paste synthesizes ⌘V, which needs
*System Settings → Privacy & Security → Accessibility* → enable **ShotClip**, then relaunch.
Without it, the screenshot is still copied and the target app is brought to front — just ⌘V yourself.

### 3. Disable native ⌘⇧4 (avoid the shortcut clash)

ShotClip uses ⌘⇧4 for capture, which collides with the native screenshot shortcut. In
*System Settings → Keyboard → Keyboard Shortcuts → Screenshots*, uncheck
**"Save picture of selected area as a file"** (and the copy-to-clipboard one) so ⌘⇧4 is ShotClip-only.

To keep native ⌘⇧4 and use a different key for ShotClip, change the keyCode in
`register(id: 2, ...)` in `Sources/ShotClip/main.swift`.

## Uninstall

Run the bundled script — it quits ShotClip, removes the login item, deletes the app, and clears its data:

```bash
./uninstall.sh
```

If a leftover **ShotClip** entry remains in *System Settings → General → Login Items*, remove it there.

## Storage

- Directory: `$TMPDIR/ShotClip/`
- Screenshots: `shot-*.png`
- Copied images: `clip-*.png`
- Clipboard text history: `clips.json` (restored on relaunch)

## Architecture

| File | Responsibility |
|---|---|
| `main.swift` | Menu-bar agent (`LSUIElement`), global hotkeys, hover-keep-alive, update check |
| `Store.swift` | Temp store, timeline merge, 30-day expiry, clipboard persistence |
| `ClipboardMonitor.swift` | Polls `NSPasteboard`, captures text / images |
| `Capture.swift` | Runs `screencapture -i`, hands the shot to the annotator |
| `Annotator.swift` | Annotation editor window, toolbar, shapes / pen / text / brush-mosaic, letterbox layout, render & export |
| `OCR.swift` | Vision text recognition (offline, zh + en) |
| `ScreenGrabber.swift` | Region capture — ScreenCaptureKit (14+) with CGWindowList fallback (13) |
| `ScrollCapture.swift` | Scrolling capture: region select, manual-scroll frame grab, live control bar |
| `Stitcher.swift` | Incremental frame stitching with fixed-header detection + robust overlap |
| `Onboarding.swift` | First-run welcome + permissions guide (screen recording / accessibility / shortcut) |
| `Hotkeys.swift` | Carbon global hotkeys (no Accessibility permission) |
| `DragViews.swift` | Card views; per-type drag / click routing; copy highlight |
| `OverlayWindow.swift` | Bottom floating panel, single-row card wall, auto-hide |
| `SendPanel.swift` | Send-to-app picker, smart image/path routing, auto-paste |
| `Updater.swift` | GitHub Releases check, download & replace, relaunch |

## Notes

- Native AppKit, no third-party dependencies.
- Global hotkeys use Carbon `RegisterEventHotKey` — no Accessibility permission needed for the hotkeys themselves.
- The bottom panel is a `.nonactivatingPanel`, so summoning it doesn't steal focus from the current app.

---

## 中文

[English](#shotclip) · **中文**

一个常驻菜单栏的 macOS 小工具：用快捷键在屏幕底部呼出一条卡片墙,把**最近截图**和**剪贴板历史**放在一起。可以把卡片拖进任意应用,也可以点一下复制。所有内容临时存放,30 天后自动清除。

## 功能

- **⌘⇧4** — 截取屏幕区域,直接存进 ShotClip 自己的库(不再落到桌面)。
  - > **先关掉系统原生 ⌘⇧4** 免得冲突:*系统设置 → 键盘 → 键盘快捷键… → 截屏*,取消勾选 **「将所选部分的图片存储为文件」**(以及「拷贝到剪贴板」那条)。
- **编辑模式** — 菜单栏里的开关(**默认关闭**)。开启时 ⌘⇧4 会先进内置**标注编辑器**再入库;关闭时截图直接入库 + 复制 + 弹发送面板。
- **标注编辑器**(编辑模式开启时) — 悬浮窗,带工具栏:
  - **矩形 / 圆 / 箭头 / 画笔 / 文字 / 马赛克** — 在截图上画,颜色从色板挑(选中的颜色会高亮)。
  - **马赛克是画笔** — 按住拖动,笔刷经过的地方被打码(遮住敏感信息)。
  - **文字** — 点一下开始打字;打字过程中切颜色,正在编辑的文字会跟着变色。
  - **OCR** — 识别截图里的文字(离线,macOS Vision,中英文),复制到剪贴板。
  - **长截图** — 框一个区域,自己手动往下滚,ShotClip 逐帧抓取拼成一张长图。也可从菜单栏「Scrolling Capture…」直接进入。只需屏幕录制权限(不合成滚轮)。
  - **撤销**(⌘Z)、**保存到文件**、**✓ 完成**(复制 + 发送)、**✕ 取消**(Esc / 回车完成)。
  - 小截图保持原尺寸 —— 编辑器用黑色边框居中显示,不拉伸;导出的图没有黑边。
  - 编辑器窗口只能拖标题栏移动 —— 在图上拖是画标注,不会拖走窗口。
- **权限引导** — 首次启动弹一个欢迎窗,说明功能并一键授权各项权限(屏幕录制、辅助功能、释放 ⌘⇧4)。之后随时可从菜单栏 → **Permissions & Setup…** 重新打开。
- **⌘⇧Space** — 呼出/隐藏底部卡片墙(点它以外的区域即可关闭)。
- 单行卡片墙,截图和剪贴板混排,按时间倒序:
  - 🟢 **Screenshot** — 截图缩略图
  - 🔵 **Image** — 复制的图片
  - 🟣 **Link** — 复制的网址
  - 🟡 **Text** — 复制的文字
- **拖拽**卡片到目标应用:
  - 截图 / 图片 → 落下的是**文件路径**(拖进 Ghostty 得到图片路径)
  - 文字 / 链接 → 落下的是**文字本身**
- **点击**卡片 = 重新复制到剪贴板:
  - 截图 / 图片 → 复制**图片本身**(可直接 ⌘V 粘贴到聊天 / 文档)
  - 文字 / 链接 → 复制文字
  - 复制成功后卡片会发光 + 弹出 **✓ Copied** 明确确认
- **截图自动进剪贴板** — 按完 ⌘⇧4,截图已在剪贴板,可直接 ⌘V。
- **发送到 App 面板** — 截图后选一个正在运行的 App,截图自动粘贴过去(终端给路径,其它 App 给图片)。最近用过的 App 排在前面;无关 App(日历、访达等)自动过滤。
- **自动隐藏** — 呼出 5 秒后自动消失(鼠标悬停会重置计时),或拖拽完成后立即隐藏。
- **屏幕取字(⌘⇧E)** — 框选屏幕上任意区域,ShotClip 离线 OCR(macOS Vision,中英文)后把文字放进剪贴板和历史。专治**复制不了的文字**:图片、PDF、视频字幕、禁止复制的界面,框一下直接拿到文本。
- **截屏翻译(⌘⇧T)** — 框选一个区域,先 OCR 再交给你配置的 AI 翻译,弹窗显示译文并自动复制。
- **划词翻译(⌘⇧L)** — 在任意 App 里选中文字按快捷键,译文弹窗显示并自动复制。目标语言可配置,默认中英互换。
- **AI Settings…** — 选择翻译后端:
  - **Claude Code(订阅)** — 直接用你已登录的 `claude` CLI,无需 API key。
  - **Codex(ChatGPT 订阅)** — 用 `codex` CLI 的登录态,无需 API key。
  - **Anthropic API key** 或任意 **OpenAI 兼容接口**(base URL + key + 模型)。密钥存在 macOS 钥匙串里,不落明文。
- **剪贴板历史面板(⌘⇧V)** — 竖排可搜索的完整历史(最多 200 条):文字、链接、图片、截图。打字过滤,点击复制。
- **临时存放 + 自动过期** — 所有内容存在临时目录,30 天后自动清除(截图最多 40 条,剪贴板历史最多 200 条)。
- **自动更新** — 启动时(及菜单里)检查 GitHub Releases,自动下载、替换、重启。

## 安装 / 构建

需要 Swift 工具链(Xcode 或 Command Line Tools)。

```bash
git clone https://github.com/Ivanwuyifan/ShotClip.git
cd ShotClip
./build_app.sh        # 编译 release + 打包成 ShotClip.app(自签名,权限重建不失效)
open ShotClip.app
```

菜单栏会出现 ShotClip 图标,点它有「Show bar / Capture region / Edit mode / Permissions & Setup / Check for Updates / Quit」菜单。

> 也可以从 [Releases](https://github.com/Ivanwuyifan/ShotClip/releases/latest) 下载打包好的 `ShotClip.app.zip`。里面含 `ShotClip.app` 和 **`install.command`** —— 双击 `install.command` 会自动拷进 Applications、清除隔离属性、打开(自签名 App 借此免掉「身份不明/已损坏」提示,也让自动更新正常)。或自己把 `ShotClip.app` 拖进 Applications,首次右键 → 打开。

## 首次使用需要的系统设置

### 1. 屏幕录制权限(截图必需)

第一次按 ⌘⇧4 时 macOS 会弹授权。到
*系统设置 → 隐私与安全性 → 屏幕录制* 里给 **ShotClip** 打勾,然后重启 App。

> 本项目用一个固定的自签名证书签名(`build_app.sh` 自动处理),所以授权一次后即使重新构建也不会失效。

### 2. 辅助功能权限(自动粘贴到 App 需要)

发送到 App 的自动粘贴要合成 ⌘V,需要到
*系统设置 → 隐私与安全性 → 辅助功能* 里给 **ShotClip** 打勾,然后重启 App。
没授权也没关系:截图仍会复制、目标 App 会被置前,你手动 ⌘V 即可。

### 3. 关闭系统原生 ⌘⇧4(避免快捷键冲突)

ShotClip 用 ⌘⇧4 作为截图键,会和系统原生截图冲突。到
*系统设置 → 键盘 → 键盘快捷键 → 截屏*,取消勾选
**「将所选部分的图片存储为文件」**(以及「拷贝到剪贴板」那条),⌘⇧4 就只由 ShotClip 响应。

想保留系统原生 ⌘⇧4、给 ShotClip 换别的键的话,改
`Sources/ShotClip/main.swift` 里 `register(id: 2, ...)` 的 keyCode 即可。

## 卸载

跑自带的卸载脚本 —— 会退出 ShotClip、取消开机启动项、删除 App、清理数据:

```bash
./uninstall.sh
```

如果 *系统设置 → 通用 → 登录项* 里还残留 **ShotClip** 条目,在那里手动删掉即可。

## 存储位置

- 目录:`$TMPDIR/ShotClip/`
- 截图:`shot-*.png`
- 复制的图片:`clip-*.png`
- 剪贴板文字历史:`clips.json`(重启后自动恢复)

## 架构

| 文件 | 职责 |
|---|---|
| `main.swift` | 菜单栏 agent(`LSUIElement`)、全局快捷键、悬停保活、更新检查 |
| `Store.swift` | 临时库、时间线合并、30 天过期、剪贴板持久化 |
| `ClipboardMonitor.swift` | 轮询 `NSPasteboard`,捕获文字 / 图片 |
| `Capture.swift` | 调 `screencapture -i` 截图,交给标注器 |
| `Annotator.swift` | 标注编辑器窗口、工具栏、图形/画笔/文字/画笔马赛克、letterbox 布局、渲染导出 |
| `OCR.swift` | Vision 文字识别(离线,中 + 英) |
| `ScreenGrabber.swift` | 区域截屏 —— ScreenCaptureKit(14+),CGWindowList 回退(13) |
| `ScrollCapture.swift` | 长截图:框选、手动滚逐帧抓取、实时控制条 |
| `Stitcher.swift` | 逐帧增量拼接,固定表头检测 + 鲁棒重叠对齐 |
| `Onboarding.swift` | 首次启动欢迎窗 + 权限引导(屏幕录制/辅助功能/快捷键) |
| `Hotkeys.swift` | Carbon 全局热键(无需辅助功能权限) |
| `DragViews.swift` | 卡片视图,按类型分发拖拽 / 点击,复制高亮 |
| `OverlayWindow.swift` | 底部悬浮面板,单行卡片墙,自动隐藏 |
| `SendPanel.swift` | 发送到 App 选择器,智能图片/路径路由,自动粘贴 |
| `Updater.swift` | GitHub Releases 检查,下载替换,重启 |

## 技术说明

- 原生 AppKit,无第三方依赖。
- 全局热键用 Carbon `RegisterEventHotKey`,热键本身不需要辅助功能权限。
- 底部面板是 `.nonactivatingPanel`,呼出时不抢当前应用焦点。
