import AppKit

final class OverlayWindow: NSPanel, DragCompletionDelegate {
    private var hideTimer: Timer?
    private let row = NSStackView()
    private let scroll = NSScrollView()

    init() {
        let w: CGFloat = 980
        let h: CGFloat = 262
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.autoresizingMask = [.width, .height]
        contentView = container

        setupRow(in: container)
    }

    private func setupRow(in container: NSView) {
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = row
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
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
            l.textColor = .tertiaryLabelColor
            row.addArrangedSubview(l)
            return
        }

        for item in items {
            let card = CardView(item: item)
            card.completion = self
            card.onClick = { [weak self] in self?.recopy(item) }
            card.widthAnchor.constraint(equalToConstant: CardView.cardWidth).isActive = true
            card.heightAnchor.constraint(equalToConstant: CardView.cardHeight).isActive = true
            row.addArrangedSubview(card)
        }
    }

    private func recopy(_ item: TimelineItem) {
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
        flash()
    }

    private func flash() {
        contentView?.layer?.borderWidth = 2.5
        contentView?.layer?.borderColor = NSColor.controlAccentColor.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.contentView?.layer?.borderWidth = 0
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
