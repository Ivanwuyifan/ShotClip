# ShotClip

一个常驻菜单栏的 macOS 小工具：用快捷键在屏幕底部呼出一条「最近截图 + 剪贴板历史」的卡片墙，可以直接拖进 Ghostty（或任意应用），也可以点一下重新复制。所有内容临时存放，30 天后自动清除。

![menu bar app](icon_1024.png)

## 功能

- **⌘⇧4** — 截取屏幕区域，直接存进 ShotClip 自己的库（不再落到桌面）。
- **⌘⇧Space** — 呼出/隐藏底部卡片墙。
- 单行卡片墙，截图和剪贴板混排，按时间倒序：
  - 🟢 **Screenshot** — 截图缩略图
  - 🔵 **Image** — 复制的图片
  - 🟣 **Link** — 复制的网址
  - 🟡 **Text** — 复制的文字
- **拖拽**卡片到目标应用：
  - 截图 / 图片 → 落下的是**文件路径**（拖进 Ghostty 得到图片路径）
  - 文字 / 链接 → 落下的是**文字本身**
- **点击**卡片 = 重新复制到剪贴板：
  - 截图 / 图片 → 复制**图片本身**（可直接 ⌘V 粘贴到聊天 / 文档）
  - 文字 / 链接 → 复制文字
  - 复制成功后卡片墙边框会闪一下确认
- **自动隐藏**：呼出 5 秒后自动消失（鼠标悬停在上面会重置计时），或拖拽完成后立即隐藏。
- **临时存放 + 自动过期**：所有内容存在临时目录，30 天后自动清除（每类最多 40 条）。

## 安装 / 构建

需要 Swift 工具链（Xcode 或 Command Line Tools）。

```bash
git clone <this-repo>
cd ShotClip
./build_app.sh        # 编译 release + 打包成 ShotClip.app（自签名，权限重建不失效）
open ShotClip.app
```

菜单栏会出现 ShotClip 图标，点它有「Show bar / Capture region / Quit」菜单。

## 首次使用需要的两个系统设置

### 1. 屏幕录制权限（截图必需）

第一次按 ⌘⇧4 时 macOS 会弹授权。到
*系统设置 → 隐私与安全性 → 屏幕录制* 里给 **ShotClip** 打勾，然后重启 App。

> 本项目用一个固定的自签名证书签名（`build_app.sh` 自动处理），所以授权一次后即使重新构建也不会失效。

### 2. 关闭系统原生 ⌘⇧4（避免快捷键冲突）

ShotClip 用 ⌘⇧4 作为截图键，会和系统原生截图冲突。到
*系统设置 → 键盘 → 键盘快捷键 → 截屏*，取消勾选
**「将所选部分的图片存储为文件」**（以及「拷贝到剪贴板」那条），⌘⇧4 就只由 ShotClip 响应。

想保留系统原生 ⌘⇧4、给 ShotClip 换别的键的话，改
`Sources/ShotClip/main.swift` 里 `register(id: 2, ...)` 的 keyCode 即可。

## 存储位置

- 目录：`$TMPDIR/ShotClip/`
- 截图：`shot-*.png`
- 复制的图片：`clip-*.png`
- 剪贴板文字历史：`clips.json`（重启后自动恢复）

## 架构

| 文件 | 职责 |
|---|---|
| `main.swift` | 菜单栏 agent（`LSUIElement`）、全局快捷键注册、悬停保活 |
| `Store.swift` | 临时库、时间线合并、30 天过期、剪贴板持久化 |
| `ClipboardMonitor.swift` | 轮询 `NSPasteboard`，捕获文字 / 图片 |
| `Capture.swift` | 调 `screencapture -i` 截图入库 |
| `Hotkeys.swift` | Carbon 全局热键（无需辅助功能权限） |
| `DragViews.swift` | 卡片视图，按类型分发拖拽 / 点击行为 |
| `OverlayWindow.swift` | 底部悬浮面板，单行卡片墙，自动隐藏 |

## 技术说明

- 原生 AppKit，无第三方依赖。
- 全局热键用 Carbon `RegisterEventHotKey`，不需要辅助功能权限。
- 底部面板是 `.nonactivatingPanel`，呼出时不抢当前应用焦点。
