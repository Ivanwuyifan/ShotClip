import AppKit
import CoreGraphics

enum Onboarding {
    private static let shownKey = "ShotClip.onboardingShown"
    private static var window: OnboardingWindow?

    /// Shows on first run, and again on any launch where a required permission
    /// is missing (e.g. after replacing an old version whose grants no longer
    /// match this build's signature).
    static func showIfNeeded() {
        let firstRun = !UserDefaults.standard.bool(forKey: shownKey)
        UserDefaults.standard.set(true, forKey: shownKey)
        guard firstRun || !hasScreenRecording() || !hasAccessibility() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { present() }
    }

    /// Fixes the "System Settings shows the toggle ON but the app still isn't
    /// trusted" state: that happens when the TCC row was recorded against an
    /// older build's signature. Deleting the stale row and re-requesting makes
    /// macOS record the *current* binary.
    static func repairAccessibility() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility",
                           Bundle.main.bundleIdentifier ?? "com.local.shotclip"]
        try? reset.run()
        reset.waitUntilExit()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Restarts the app so freshly granted permissions apply.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(path)\""]
        try? proc.run()
        NSApp.terminate(nil)
    }

    /// Fires every system permission prompt in sequence — one click from the
    /// user per prompt, no digging through System Settings.
    static func grantAll() {
        if !hasAccessibility() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !hasScreenRecording() {
                _ = CGRequestScreenCaptureAccess()
            }
        }
    }

    static func present() {
        let win = OnboardingWindow()
        window = win
        win.onClosed = { window = nil }
        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }

    static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        openSettings("com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openSettings("com.apple.preference.security?Privacy_Accessibility")
    }

    static func openKeyboardShortcuts() {
        openSettings("com.apple.Keyboard-Settings.extension")
    }

    private static func openSettings(_ path: String) {
        if let url = URL(string: "x-apple.systempreferences:\(path)") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class OnboardingWindow: NSWindow, NSWindowDelegate {
    var onClosed: (() -> Void)?
    private var rows: [PermissionRow] = []
    private var refreshTimer: Timer?

    init() {
        let w: CGFloat = 480, h: CGFloat = 470
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "Welcome to ShotClip"
        isReleasedWhenClosed = false
        level = .floating
        delegate = self
        build()
        startAutoRefresh()
    }

    override var canBecomeKey: Bool { true }

    private func build() {
        let content = NSView(frame: contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            let iv = NSImageView(image: icon)
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 56).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 56).isActive = true
            stack.addArrangedSubview(iv)
        }

        let title = NSTextField(labelWithString: "ShotClip")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Hotkey-summoned screenshots + clipboard history.\n⌘⇧4 to capture & annotate · ⌘⇧Space for the card wall.\n\nGrant these once so everything works:")
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 432
        stack.addArrangedSubview(subtitle)

        let screen = PermissionRow(
            title: "Screen Recording",
            detail: "Required to capture the screen.",
            check: { Onboarding.hasScreenRecording() },
            action: { Onboarding.requestScreenRecording() })
        let ax = PermissionRow(
            title: "Accessibility",
            detail: "Lets ShotClip auto-paste into other apps. If the toggle in System Settings is ON but this row still shows ⚠︎ (stale grant from an older version), use Repair.",
            check: { Onboarding.hasAccessibility() },
            action: { Onboarding.requestAccessibility() },
            repair: { Onboarding.repairAccessibility() })
        let keys = PermissionRow(
            title: "Free up ⌘⇧4",
            detail: "Open Keyboard settings → click \"Keyboard Shortcuts…\" → Screenshots, then uncheck the ⌘⇧4 items.",
            check: { false },
            action: { Onboarding.openKeyboardShortcuts() },
            optional: true)
        // Screen Recording goes last: it's the one that needs a quit-and-reopen.
        rows = [keys, ax, screen]
        for r in rows {
            r.view.translatesAutoresizingMaskIntoConstraints = false
            r.view.widthAnchor.constraint(equalToConstant: 432).isActive = true
            stack.addArrangedSubview(r.view)
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(spacer)

        let note = NSTextField(wrappingLabelWithString:
            "After granting Screen Recording or Accessibility, quit and reopen ShotClip so macOS applies it.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = 432
        stack.addArrangedSubview(note)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let grantAll = NSButton(title: "Grant All…", target: self, action: #selector(grantAllTapped))
        grantAll.bezelStyle = .rounded
        grantAll.keyEquivalent = "\r"
        let relaunch = NSButton(title: "Relaunch ShotClip", target: self, action: #selector(relaunchTapped))
        relaunch.bezelStyle = .rounded
        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        done.bezelStyle = .rounded
        buttons.addArrangedSubview(grantAll)
        buttons.addArrangedSubview(relaunch)
        buttons.addArrangedSubview(done)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttons)

        refreshRows()
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshRows()
        }
    }

    private func refreshRows() {
        for r in rows { r.refresh() }
    }

    @objc private func closeWindow() { close() }
    @objc private func grantAllTapped() { Onboarding.grantAll() }
    @objc private func relaunchTapped() { Onboarding.relaunch() }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        onClosed?()
    }
}

final class PermissionRow {
    let view = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let check: () -> Bool
    private let action: () -> Void
    private let optional: Bool
    private var repair: (() -> Void)?
    private var repairButton: NSButton?

    init(title: String, detail: String, check: @escaping () -> Bool,
         action: @escaping () -> Void, optional: Bool = false,
         repair: (() -> Void)? = nil) {
        self.check = check
        self.action = action
        self.optional = optional
        self.repair = repair

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.08).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.cornerCurve = .continuous

        let status = statusLabel
        status.font = .systemFont(ofSize: 18)
        status.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.preferredMaxLayoutWidth = 280

        let button = NSButton(title: optional ? "Open" : "Grant", target: self, action: #selector(tapped))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(status)
        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        view.addSubview(button)

        if repair != nil {
            let rb = NSButton(title: "Repair…", target: self, action: #selector(repairTapped))
            rb.bezelStyle = .rounded
            rb.font = .systemFont(ofSize: 11)
            rb.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(rb)
            NSLayoutConstraint.activate([
                rb.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
                rb.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 4),
            ])
            repairButton = rb
        }

        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.widthAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
            detailLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            repair == nil
                ? button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
                : button.bottomAnchor.constraint(equalTo: view.centerYAnchor, constant: -2),
        ])
    }

    @objc private func tapped() { action() }
    @objc private func repairTapped() { repair?() }

    func refresh() {
        repairButton?.isHidden = check()
        if optional {
            statusLabel.stringValue = "•"
            statusLabel.textColor = .tertiaryLabelColor
        } else if check() {
            statusLabel.stringValue = "✓"
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "⚠︎"
            statusLabel.textColor = .systemOrange
        }
    }
}
