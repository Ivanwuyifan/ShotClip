import AppKit
import Carbon.HIToolbox

enum Sender {
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
            copyPath(imageURL)
        } else {
            copyImage(imageURL)
        }
        app.activate(options: [.activateAllWindows])
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
        let src = CGEventSource(stateID: .combinedSessionState)

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

    private static let excludedBundleIDs: Set<String> = [
        "com.apple.iCal",
        "com.apple.reminders",
        "com.apple.systempreferences",
        "com.apple.finder",
        "com.apple.ActivityMonitor",
        "com.apple.calculator",
        "com.apple.weather",
        "com.apple.clock",
        "com.apple.AddressBook",
        "com.apple.Maps",
        "com.apple.podcasts",
        "com.apple.Music",
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
            if ra != rb { return ra < rb }
            return (a.localizedName ?? "") < (b.localizedName ?? "")
        }
    }

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
            Sender.copyImage(imageURL)
            app.activate(options: [.activateAllWindows])
            showAccessibilityGuide()
        }
    }

    private func showAccessibilityGuide() {
        let alert = NSAlert()
        alert.messageText = "Screenshot copied — press ⌘V to paste"
        alert.informativeText = "To let ShotClip auto-paste into the target app, enable Accessibility once:\n\n1. System Settings → Privacy & Security → Accessibility\n2. Turn on ShotClip\n3. Quit and reopen ShotClip (the permission doesn't apply to an already-running app)\n\nUntil then, the screenshot is already on the clipboard and the target app is in front — just press ⌘V."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")
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
