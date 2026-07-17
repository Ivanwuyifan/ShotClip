import AppKit
import Carbon.HIToolbox

enum Sender {
    // 终端类 App：吃文本，不吃图片对象 → 粘贴文件路径
    private static let terminalBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "org.alacritty",
    ]

    static func isTerminal(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return terminalBundleIDs.contains(id)
    }

    static func copyImage(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let img = NSImage(contentsOf: url) { pb.writeObjects([img]) }
    }


    static func copyPath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }

    static func send(imageURL: URL, to app: NSRunningApplication) {
        ClipboardMonitor.shared.suppressNext()
        if isTerminal(app) {
            copyPath(imageURL)      // 终端粘路径
        } else {
            copyImage(imageURL)     // 其它粘图片
        }
        app.activate(options: [.activateAllWindows])
        // 等目标真正到前台再粘（Electron 类 App 如 Teams 激活较慢，
        // 固定延迟会偶发丢粘贴）。轮询最多 ~1.6s。
        pasteWhenFront(app, attempt: 0)
    }

    private static func pasteWhenFront(_ app: NSRunningApplication, attempt: Int) {
        let isFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleIdentifier
        if isFront || attempt >= 8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pasteViaKeystroke()
            }
        } else {
            app.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pasteWhenFront(app, attempt: attempt + 1)
            }
        }
    }

    private static func pasteViaKeystroke() {
        // CGEvent 发 ⌘V（快）。关键：显式只带 Command 一个修饰键，
        // 并先发一个空的“抬起所有修饰键”事件，清掉截图 ⌘⇧4 的残留，
        // 否则残留的 Shift 会让 Ghostty 收到 ⌘⇧V 或丢掉 Command，只敲进 "v"。
        let src = CGEventSource(stateID: .combinedSessionState)

        // 清残留修饰键
        let clear = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        clear?.flags = []
        clear?.post(tap: .cghidEventTap)

        let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

final class SendPanel: NSPanel {
    private let imageURL: URL
    private let row = NSStackView()
    private var hideTimer: Timer?

    init(imageURL: URL) {
        self.imageURL = imageURL
        let w: CGFloat = 520, h: CGFloat = 132
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .vibrantDark)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        container.autoresizingMask = [.width, .height]
        contentView = container

        build(in: container)
    }

    private func build(in container: NSView) {
        let title = NSTextField(labelWithString: "Send screenshot to…")
        title.font = .systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = NSColor(white: 1, alpha: 0.6)
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = row
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 4),
            row.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        for app in targetApps() {
            row.addArrangedSubview(AppTargetView(app: app) { [weak self] in
                self?.pick(app)
            })
        }
    }

    // 不接受图片/路径粘贴、或没有发送诉求的 App
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.iCal",                 // 日历
        "com.apple.reminders",            // 提醒事项
        "com.apple.systempreferences",    // 系统设置
        "com.apple.finder",               // 访达
        "com.apple.ActivityMonitor",      // 活动监视器
        "com.apple.calculator",           // 计算器
        "com.apple.weather",              // 天气
        "com.apple.clock",                // 时钟
        "com.apple.AddressBook",          // 通讯录
        "com.apple.Maps",                 // 地图
        "com.apple.podcasts",             // 播客
        "com.apple.Music",                // 音乐
        "com.apple.tv",                   // TV
    ]

    private func targetApps() -> [NSRunningApplication] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !Self.excludedBundleIDs.contains($0.bundleIdentifier ?? "")
        }
        let recents = SendPanel.recentBundleIDs
        return apps.sorted { a, b in
            let ra = recents.firstIndex(of: a.bundleIdentifier ?? "") ?? Int.max
            let rb = recents.firstIndex(of: b.bundleIdentifier ?? "") ?? Int.max
            if ra != rb { return ra < rb }                     // 最近发送过的靠前
            return (a.localizedName ?? "") < (b.localizedName ?? "")
        }
    }

    // 最近发送过的 App（bundleID），最新在前，持久化到 UserDefaults
    static var recentBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "ShotClip.recentTargets") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(12)), forKey: "ShotClip.recentTargets") }
    }

    static func markRecent(_ bundleID: String?) {
        guard let id = bundleID else { return }
        var list = recentBundleIDs.filter { $0 != id }
        list.insert(id, at: 0)
        recentBundleIDs = list
    }

    private func pick(_ app: NSRunningApplication) {
        hideTimer?.invalidate()
        orderOut(nil)
        SendPanel.markRecent(app.bundleIdentifier)
        if Sender.hasAccessibility() {
            Sender.send(imageURL: imageURL, to: app)
        } else {
            // 无权限：复制图 + 激活目标 App，让用户手动 ⌘V（100% 可用的兜底），
            // 同时只弹一次系统授权框 + 一次性说明，不再每次静默重复弹。
            Sender.copyImage(imageURL)
            app.activate(options: [.activateAllWindows])
            showAccessibilityGuide()
        }
    }

    private func showAccessibilityGuide() {
        let alert = NSAlert()
        alert.messageText = "已复制截图，请按 ⌘V 粘贴"
        alert.informativeText = "想让 ShotClip 截图后自动粘贴到目标 App，需要开启一次「辅助功能」权限：\n\n1. 打开系统设置 → 隐私与安全性 → 辅助功能\n2. 勾选 ShotClip\n3. 退出并重新打开 ShotClip（授权对已运行的 App 不即时生效）\n\n在此之前，截图已复制到剪贴板，目标 App 已置前，直接 ⌘V 即可。"
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "以后再说")
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            Sender.promptAccessibility()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func present() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        setFrameOrigin(NSPoint(x: vf.midX - frame.width/2, y: vf.midY - frame.height/2))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            self?.orderOut(nil)
        }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        hideTimer?.invalidate()
        orderOut(nil)
    }
}

final class AppTargetView: NSView {
    private let action: () -> Void
    private var trackingArea: NSTrackingArea?

    init(app: NSRunningApplication, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 76, height: 88))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        let icon = NSImageView(frame: NSRect(x: 18, y: 34, width: 40, height: 40))
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let name = NSTextField(labelWithString: app.localizedName ?? "App")
        name.font = .systemFont(ofSize: 10, weight: .medium)
        name.textColor = NSColor(white: 1, alpha: 0.75)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: 2, y: 10, width: 72, height: 14)
        addSubview(name)

        widthAnchor.constraint(equalToConstant: 76).isActive = true
        heightAnchor.constraint(equalToConstant: 88).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        action()
    }
}
