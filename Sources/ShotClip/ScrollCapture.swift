import AppKit

// Scrolling capture, method B: select a region, then the USER scrolls manually
// while ShotClip grabs frames and stitches them live. No synthetic scroll events,
// so only Screen Recording permission is needed (no Accessibility).

enum ScrollCapture {
    private static var controller: ScrollCaptureController?

    static func begin(completion: @escaping (NSImage?) -> Void) {
        guard let screen = NSScreen.main else { completion(nil); return }
        let c = ScrollCaptureController(screen: screen) { image in
            controller = nil
            completion(image)
        }
        controller = c
        c.start()
    }
}

private final class ScrollCaptureController {
    private let screen: NSScreen
    private let completion: (NSImage?) -> Void
    private let selectWindow: ScrollRegionSelectWindow
    private var captureWindow: ScrollCaptureWindow?
    private var borderWindow: SelectionBorderWindow?

    init(screen: NSScreen, completion: @escaping (NSImage?) -> Void) {
        self.screen = screen
        self.completion = completion
        self.selectWindow = ScrollRegionSelectWindow(targetScreen: screen)
    }

    func start() {
        selectWindow.onCancel = { [weak self] in
            self?.selectWindow.orderOut(nil)
            self?.completion(nil)
        }
        selectWindow.onSelected = { [weak self] regionGlobal in
            guard let self = self else { return }
            self.selectWindow.orderOut(nil)
            self.beginCapture(regionGlobal: regionGlobal)
        }
        NSApp.activate(ignoringOtherApps: true)
        selectWindow.makeKeyAndOrderFront(nil)
    }

    private func beginCapture(regionGlobal: CGRect) {
        let grabber = ScreenGrabber(screen: screen, regionGlobal: regionGlobal)
        // Border overlay marks the region being captured; it ignores mouse so the
        // user can still scroll the content underneath.
        let border = SelectionBorderWindow(regionGlobal: regionGlobal)
        borderWindow = border
        border.orderFrontRegardless()

        let win = ScrollCaptureWindow(targetScreen: screen, regionGlobal: regionGlobal, grabber: grabber)
        captureWindow = win
        let teardown: (NSImage?) -> Void = { [weak self] image in
            self?.captureWindow?.orderOut(nil)
            self?.captureWindow = nil
            self?.borderWindow?.orderOut(nil)
            self?.borderWindow = nil
            self?.completion(image)
        }
        win.onDone = { image in teardown(image) }
        win.onCancel = { teardown(nil) }
        win.makeKeyAndOrderFront(nil)
        win.startGrabbing()
    }
}

// Draws just a border around the capture region. Transparent center, click-through.
final class SelectionBorderWindow: NSWindow {
    init(regionGlobal: CGRect) {
        let inset: CGFloat = 3
        let frame = regionGlobal.insetBy(dx: -inset, dy: -inset)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let v = NSView(frame: CGRect(origin: .zero, size: frame.size))
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.controlAccentColor.cgColor
        v.layer?.borderWidth = inset
        v.layer?.cornerRadius = 2
        contentView = v
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - Region selection (single targetScreen, correct coordinates)

final class ScrollRegionSelectWindow: NSWindow {
    private var startPoint: CGPoint?
    private var currentRect = CGRect.zero
    private let selectionLayer = CAShapeLayer()
    private let dimLayer = CAShapeLayer()
    private let hintLabel = NSTextField(labelWithString: "Drag to select the scroll area, then scroll manually")
    var onSelected: ((CGRect) -> Void)?     // region in AppKit global coords
    var onCancel: (() -> Void)?

    private let targetScreen: NSScreen

    init(targetScreen: NSScreen) {
        self.targetScreen = targetScreen
        super.init(contentRect: targetScreen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = NSColor(white: 0, alpha: 0.28)
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = NSView(frame: CGRect(origin: .zero, size: targetScreen.frame.size))
        view.wantsLayer = true
        selectionLayer.fillColor = NSColor(white: 1, alpha: 0.10).cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.lineWidth = 2
        view.layer?.addSublayer(selectionLayer)

        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = .white
        hintLabel.drawsBackground = true
        hintLabel.backgroundColor = NSColor(white: 0, alpha: 0.5)
        hintLabel.isBezeled = false
        hintLabel.isEditable = false
        hintLabel.sizeToFit()
        hintLabel.frame.origin = CGPoint(x: targetScreen.frame.width/2 - hintLabel.frame.width/2,
                                         y: targetScreen.frame.height - 80)
        view.addSubview(hintLabel)
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        hintLabel.isHidden = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = event.locationInWindow
        currentRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y),
                             width: abs(p.x - s.x), height: abs(p.y - s.y))
        selectionLayer.path = CGPath(rect: currentRect, transform: nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard currentRect.width > 40, currentRect.height > 40 else { onCancel?(); return }
        // window is at targetScreen.frame; window coords == targetScreen-local. Convert to global.
        let global = CGRect(x: targetScreen.frame.minX + currentRect.minX,
                            y: targetScreen.frame.minY + currentRect.minY,
                            width: currentRect.width, height: currentRect.height)
        onSelected?(global)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }
}

// MARK: - Capture window: shows a control bar, grabs frames, stitches live

final class ScrollCaptureWindow: NSWindow {
    private let targetScreen: NSScreen
    private let regionGlobal: CGRect
    private let grabber: ScreenGrabber
    private let stitcher = Stitcher()
    private var timer: Timer?
    private var grabbing = false
    private let statusLabel = NSTextField(labelWithString: "0 frames")

    var onDone: ((NSImage?) -> Void)?
    var onCancel: (() -> Void)?

    init(targetScreen: NSScreen, regionGlobal: CGRect, grabber: ScreenGrabber) {
        self.targetScreen = targetScreen
        self.regionGlobal = regionGlobal
        self.grabber = grabber
        // Control bar window, placed just below the selected region (or above if no room).
        let barW: CGFloat = 300, barH: CGFloat = 52
        var x = regionGlobal.midX - barW / 2
        x = min(max(x, targetScreen.frame.minX + 8), targetScreen.frame.maxX - barW - 8)
        var y = regionGlobal.minY - barH - 12
        if y < targetScreen.frame.minY + 8 { y = regionGlobal.maxY + 12 }
        super.init(contentRect: CGRect(x: x, y: y, width: barW, height: barH),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildBar(width: barW, height: barH)
    }

    override var canBecomeKey: Bool { true }

    private func buildBar(width: CGFloat, height: CGFloat) {
        let bg = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.cornerCurve = .continuous
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(statusLabel)

        let cancel = makeButton("xmark", "Cancel", #selector(cancelTapped), tint: .systemRed)
        let done = makeButton("checkmark", "Done", #selector(doneTapped), tint: .systemGreen)
        let stack = NSStackView(views: [cancel, done])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 14),
            statusLabel.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
    }

    private func makeButton(_ symbol: String, _ help: String, _ action: Selector, tint: NSColor) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?.withSymbolConfiguration(cfg)
        b.contentTintColor = tint
        b.target = self
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return b
    }

    func startGrabbing() {
        grabbing = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.grabOnce()
        }
        grabOnce()
    }

    private func grabOnce() {
        guard grabbing else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let frame = self.grabber.grab() else { return }
            let added = self.stitcher.addFrame(frame)
            DispatchQueue.main.async {
                if added {
                    self.statusLabel.stringValue = "\(self.stitcher.frameCount) frames · \(self.stitcher.stitchedHeightPx)px"
                }
            }
        }
    }

    @objc private func doneTapped() {
        finish(cancelled: false)
    }

    @objc private func cancelTapped() {
        finish(cancelled: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(cancelled: true) }        // esc
        else if event.keyCode == 36 { finish(cancelled: false) }  // return
    }

    private func finish(cancelled: Bool) {
        grabbing = false
        timer?.invalidate()
        timer = nil
        if cancelled {
            onCancel?()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = self?.stitcher.result()
            DispatchQueue.main.async { self?.onDone?(image) }
        }
    }
}
