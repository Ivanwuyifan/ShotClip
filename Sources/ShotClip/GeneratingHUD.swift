import AppKit

/// Tiny non-activating HUD shown while an AI generation runs — gives feedback
/// without stealing focus from the input field the result will be pasted into.
final class GeneratingHUD: NSPanel {
    private static var active: [GeneratingHUD] = []
    private let label = NSTextField(labelWithString: "")

    static func show(text: String) -> GeneratingHUD {
        let hud = GeneratingHUD(text: text)
        active.append(hud)
        hud.orderFrontRegardless()
        return hud
    }

    private init(text: String) {
        let w: CGFloat = 240, h: CGFloat = 44
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        contentView = container

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        label.stringValue = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        // Top-center of the screen with the mouse (near where the user is typing).
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: vf.midX - w / 2, y: vf.maxY - h - 24))
        }
    }

    override var canBecomeKey: Bool { false }

    func dismiss(failed: Bool = false) {
        if failed {
            label.stringValue = "Generation failed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.reallyClose() }
        } else {
            reallyClose()
        }
    }

    private func reallyClose() {
        orderOut(nil)
        Self.active.removeAll { $0 === self }
    }
}
