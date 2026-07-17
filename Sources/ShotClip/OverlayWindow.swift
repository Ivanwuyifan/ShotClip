import AppKit

final class OverlayWindow: NSPanel, DragCompletionDelegate {
    private var hideTimer: Timer?
    private let row = NSStackView()
    private let scroll = NSScrollView()
    private var outsideClickMonitor: Any?

    init() {
        let w: CGFloat = 940
        let h: CGFloat = 268
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .vibrantDark)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        container.autoresizingMask = [.width, .height]
        contentView = container

        setupRow(in: container)
    }

    private func setupRow(in container: NSView) {
        let titleLabel = NSTextField(labelWithString: "ShotClip")
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.55)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let hint = NSTextField(labelWithString: "drag out · click to copy · click away to close")
        hint.font = .systemFont(ofSize: 10.5, weight: .medium)
        hint.textColor = NSColor(white: 1, alpha: 0.30)
        hint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hint)

        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)

        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = row
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            hint.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            row.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }

    func reload() {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let items = Store.shared.timeline()
        if items.isEmpty {
            let l = NSTextField(labelWithString: "Nothing yet — press ⌘⇧4 to capture, or copy something")
            l.font = .systemFont(ofSize: 13)
            l.textColor = NSColor(white: 1, alpha: 0.4)
            row.addArrangedSubview(l)
            return
        }

        for item in items {
            let card = CardView(item: item)
            card.completion = self
            card.onClick = { [weak self, weak card] in
                guard let card = card else { return }
                self?.recopy(item, card: card)
            }
            card.widthAnchor.constraint(equalToConstant: CardView.cardWidth).isActive = true
            card.heightAnchor.constraint(equalToConstant: CardView.cardHeight).isActive = true
            row.addArrangedSubview(card)
        }
    }

    private func recopy(_ item: TimelineItem, card: CardView) {
        ClipboardMonitor.shared.suppressNext()
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item {
        case .shot(let s):
            if let img = NSImage(contentsOf: s.url) { pb.writeObjects([img]) }
        case .clip(let c):
            switch c.kind {
            case .text(let str): pb.setString(str, forType: .string)
            case .image(let url):
                if let img = NSImage(contentsOf: url) { pb.writeObjects([img]) }
            }
        }
        card.flashCopied()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.hide()
        }
    }

    func show() {
        Store.shared.rescanShots()
        Store.shared.purge()
        reload()
        positionAtBottom()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
        scheduleHide()
        installOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        // Clicks in other apps come through the global monitor. If the click is
        // outside the bar's frame, dismiss it. (Clicks inside the bar are handled
        // by the cards directly and never reach a global monitor.)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self = self else { return }
            let mouse = NSEvent.mouseLocation
            if !self.frame.contains(mouse) {
                DispatchQueue.main.async { self.hide() }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    func toggle() {
        if isVisible && alphaValue > 0.5 {
            hide()
        } else {
            show()
        }
    }

    private func positionAtBottom() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = frame.size
        let x = vf.midX - size.width / 2
        let y = vf.minY + 24
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        hideTimer?.invalidate()
        removeOutsideClickMonitor()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
        }
    }

    func dragDidFinish() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.hide()
        }
    }
}
