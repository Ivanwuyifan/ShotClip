import AppKit

protocol DragCompletionDelegate: AnyObject {
    func dragDidFinish()
}

final class CardView: NSView, NSDraggingSource {
    let item: TimelineItem
    weak var completion: DragCompletionDelegate?
    var onClick: (() -> Void)?

    static let cardWidth: CGFloat = 190
    static let cardHeight: CGFloat = 210
    private let headerHeight: CGFloat = 40

    private var mouseDownAt: NSPoint = .zero

    init(item: TimelineItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: Self.cardWidth, height: Self.cardHeight))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0, alpha: 0.08).cgColor

        buildHeader()
        buildBody()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildHeader() {
        let type = item.type
        let header = NSView(frame: NSRect(x: 0, y: bounds.height - headerHeight,
                                          width: bounds.width, height: headerHeight))
        header.autoresizingMask = [.width, .minYMargin]
        header.wantsLayer = true
        header.layer?.backgroundColor = type.headerColor.cgColor

        let title = NSTextField(labelWithString: type.label)
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = .white
        title.frame = NSRect(x: 12, y: header.bounds.height - 22, width: bounds.width - 24, height: 16)
        title.autoresizingMask = [.width]
        header.addSubview(title)

        let time = NSTextField(labelWithString: Store.relativeTime(item.createdAt))
        time.font = .systemFont(ofSize: 10, weight: .medium)
        time.textColor = NSColor(white: 1, alpha: 0.85)
        time.frame = NSRect(x: 12, y: 5, width: bounds.width - 24, height: 12)
        time.autoresizingMask = [.width]
        header.addSubview(time)

        addSubview(header)
    }

    private func buildBody() {
        let bodyRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - headerHeight)

        switch item {
        case .shot(let s):
            addImageBody(s.thumbnail, in: bodyRect)
            toolTip = s.url.lastPathComponent
        case .clip(let c):
            switch c.kind {
            case .image(let url):
                addImageBody(NSImage(contentsOf: url), in: bodyRect)
            case .text(let full):
                addTextBody(full, in: bodyRect)
                toolTip = full
            }
        }
    }

    private func addImageBody(_ image: NSImage?, in rect: NSRect) {
        let iv = NSImageView(frame: rect.insetBy(dx: 8, dy: 8))
        iv.autoresizingMask = [.width, .height]
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = image
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        addSubview(iv)
    }

    private func addTextBody(_ text: String, in rect: NSRect) {
        let tf = NSTextField(wrappingLabelWithString: text)
        tf.font = .systemFont(ofSize: 12)
        tf.textColor = NSColor(white: 0.15, alpha: 1)
        tf.maximumNumberOfLines = 8
        tf.lineBreakMode = .byTruncatingTail
        tf.isEditable = false
        tf.isSelectable = false
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.frame = rect.insetBy(dx: 12, dy: 10)
        tf.autoresizingMask = [.width, .height]
        addSubview(tf)
    }

    // MARK: - Interaction

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
