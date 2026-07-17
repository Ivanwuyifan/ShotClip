import AppKit

protocol DragCompletionDelegate: AnyObject {
    func dragDidFinish()
}

final class CardView: NSView, NSDraggingSource {
    let item: TimelineItem
    weak var completion: DragCompletionDelegate?
    var onClick: (() -> Void)?

    static let cardWidth: CGFloat = 176
    static let cardHeight: CGFloat = 196
    private let topBar: CGFloat = 34
    private let bottomBar: CGFloat = 24
    private let pad: CGFloat = 12

    private var mouseDownAt: NSPoint = .zero
    private var trackingArea: NSTrackingArea?
    private var contentBox: NSView!

    init(item: TimelineItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: Self.cardWidth, height: Self.cardHeight))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor

        buildTopBar()
        buildContent()
        buildBottomBar()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var typeAccent: NSColor {
        switch item.type {
        case .screenshot: return NSColor(red: 0.40, green: 0.82, blue: 0.72, alpha: 1)
        case .image:      return NSColor(red: 0.48, green: 0.72, blue: 1.00, alpha: 1)
        case .link:       return NSColor(red: 0.72, green: 0.62, blue: 1.00, alpha: 1)
        case .text:       return NSColor(red: 0.98, green: 0.80, blue: 0.42, alpha: 1)
        }
    }

    private func buildTopBar() {
        let bar = NSView(frame: NSRect(x: 0, y: bounds.height - topBar, width: bounds.width, height: topBar))
        bar.autoresizingMask = [.width, .minYMargin]

        let dot = NSView(frame: NSRect(x: pad, y: topBar/2 - 4, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = typeAccent.cgColor
        // subtle glow
        dot.layer?.shadowColor = typeAccent.cgColor
        dot.layer?.shadowOpacity = 0.6
        dot.layer?.shadowRadius = 3
        dot.layer?.shadowOffset = .zero
        bar.addSubview(dot)

        let title = NSTextField(labelWithString: item.type.label)
        title.font = .systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = NSColor(white: 1, alpha: 0.92)
        title.sizeToFit()
        title.frame = NSRect(x: pad + 15, y: topBar/2 - title.frame.height/2 - 0.5,
                             width: bounds.width - pad*2 - 15, height: title.frame.height)
        title.autoresizingMask = [.width]
        bar.addSubview(title)

        addSubview(bar)
    }

    private func buildContent() {
        let h = bounds.height - topBar - bottomBar
        contentBox = NSView(frame: NSRect(x: 0, y: bottomBar, width: bounds.width, height: h))
        contentBox.autoresizingMask = [.width, .height]
        addSubview(contentBox)

        switch item {
        case .shot(let s):
            addImage(s.thumbnail)
            toolTip = s.url.lastPathComponent
        case .clip(let c):
            switch c.kind {
            case .image(let url):
                addImage(NSImage(contentsOf: url))
            case .text(let full):
                addText(full)
                toolTip = full
            }
        }
    }

    private func addImage(_ image: NSImage?) {
        let inset: CGFloat = 12
        let iv = NSImageView(frame: contentBox.bounds.insetBy(dx: inset, dy: 6))
        iv.autoresizingMask = [.width, .height]
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = image
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 8
        iv.layer?.cornerCurve = .continuous
        iv.layer?.masksToBounds = true
        iv.layer?.backgroundColor = NSColor(white: 0, alpha: 0.18).cgColor
        iv.layer?.borderWidth = 1
        iv.layer?.borderColor = NSColor(white: 1, alpha: 0.06).cgColor
        contentBox.addSubview(iv)
    }

    private func addText(_ text: String) {
        let tf = NSTextField(wrappingLabelWithString: text.trimmingCharacters(in: .whitespacesAndNewlines))
        tf.font = .systemFont(ofSize: 12.5, weight: .regular)
        tf.textColor = NSColor(white: 1, alpha: 0.82)
        tf.maximumNumberOfLines = 6
        tf.lineBreakMode = .byTruncatingTail
        tf.isEditable = false
        tf.isSelectable = false
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.frame = contentBox.bounds.insetBy(dx: pad, dy: 8)
        tf.autoresizingMask = [.width, .height]
        contentBox.addSubview(tf)
    }

    private func buildBottomBar() {
        let time = NSTextField(labelWithString: Store.relativeTime(item.createdAt))
        time.font = .systemFont(ofSize: 10, weight: .medium)
        time.textColor = NSColor(white: 1, alpha: 0.38)
        time.frame = NSRect(x: pad, y: 7, width: bounds.width - pad*2, height: 12)
        time.autoresizingMask = [.width]
        addSubview(time)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
            layer?.borderColor = typeAccent.withAlphaComponent(0.55).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
            layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        }
    }

    // MARK: - Interaction

    // 让整张卡接管点击：子视图（NSImageView/NSTextField）不拦截，
    // 否则图片卡的 NSImageView 会吃掉第一次点击，导致要双击。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return bounds.contains(p) ? self : nil
    }

    func flashCopied() {
        guard let layer = layer else { return }
        layer.removeAllAnimations()

        // 1) 明显的类型色发光边框 + 背景染色
        layer.borderColor = typeAccent.cgColor
        layer.borderWidth = 3
        layer.backgroundColor = typeAccent.withAlphaComponent(0.30).cgColor
        layer.shadowColor = typeAccent.cgColor
        layer.shadowOpacity = 0.9
        layer.shadowRadius = 16
        layer.shadowOffset = .zero
        layer.masksToBounds = false

        // 2) 缩放脉冲
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.05
        pulse.autoreverses = true
        pulse.duration = 0.16
        layer.add(pulse, forKey: "pulse")

        // 3) 中央 "✓ Copied" 浮层
        showCopiedBadge()

        // 4) 恢复
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.7
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
            layer.borderWidth = 1
            layer.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
            layer.shadowOpacity = 0
        } completionHandler: { [weak self] in
            self?.layer?.masksToBounds = true
        }
    }

    private func showCopiedBadge() {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = typeAccent.cgColor
        badge.layer?.cornerRadius = 13
        badge.layer?.cornerCurve = .continuous
        badge.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "✓ Copied")
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = NSColor(white: 0.08, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)

        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 26),
            label.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badge.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 22),
        ])

        badge.alphaValue = 0
        badge.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.8, y: 0.8))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            badge.animator().alphaValue = 1
            badge.layer?.setAffineTransform(.identity)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                badge.animator().alphaValue = 0
            } completionHandler: { badge.removeFromSuperview() }
        }
    }

    // 面板是 nonactivatingPanel，不接管首点会导致第一次点击被吞、需点两下。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        let dx = abs(event.locationInWindow.x - mouseDownAt.x)
        let dy = abs(event.locationInWindow.y - mouseDownAt.y)
        if dx < 3 && dy < 3 { onClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        let dx = abs(event.locationInWindow.x - mouseDownAt.x)
        let dy = abs(event.locationInWindow.y - mouseDownAt.y)
        guard dx > 3 || dy > 3 else { return }

        let writer: NSPasteboardWriting
        switch item {
        case .shot(let s):
            writer = s.url as NSURL
        case .clip(let c):
            switch c.kind {
            case .text(let str): writer = str as NSString
            case .image(let url): writer = url as NSURL
            }
        }

        let dragItem = NSDraggingItem(pasteboardWriter: writer)
        dragItem.setDraggingFrame(bounds, contents: snapshotImage())
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        img.unlockFocus()
        return img
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy]
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        completion?.dragDidFinish()
    }
}
