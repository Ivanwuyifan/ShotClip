import AppKit
import Vision

enum AnnotTool {
    case select
    case rect
    case ellipse
    case arrow
    case pen
    case text
    case mosaic
}

struct AnnotStyle {
    var color: NSColor
    var lineWidth: CGFloat
}

protocol Annotation: AnyObject {
    func draw(in ctx: CGContext)
    func hit(_ point: CGPoint) -> Bool
}

final class ShapeAnnotation: Annotation {
    enum Shape { case rect, ellipse, arrow }
    let shape: Shape
    var start: CGPoint
    var end: CGPoint
    let style: AnnotStyle

    init(shape: Shape, start: CGPoint, end: CGPoint, style: AnnotStyle) {
        self.shape = shape
        self.start = start
        self.end = end
        self.style = style
    }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    func draw(in ctx: CGContext) {
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        switch shape {
        case .rect:
            ctx.stroke(rect)
        case .ellipse:
            ctx.strokeEllipse(in: rect)
        case .arrow:
            drawArrow(in: ctx)
        }
    }

    private func drawArrow(in ctx: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = max(1, hypot(dx, dy))
        let head = min(len * 0.35, 18 + style.lineWidth * 2)
        let angle = atan2(dy, dx)
        let wing = CGFloat.pi / 7
        ctx.setFillColor(style.color.cgColor)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        let p1 = CGPoint(x: end.x - head * cos(angle - wing), y: end.y - head * sin(angle - wing))
        let p2 = CGPoint(x: end.x - head * cos(angle + wing), y: end.y - head * sin(angle + wing))
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    func hit(_ point: CGPoint) -> Bool { rect.insetBy(dx: -8, dy: -8).contains(point) }
}

final class PenAnnotation: Annotation {
    var points: [CGPoint]
    let style: AnnotStyle

    init(points: [CGPoint], style: AnnotStyle) {
        self.points = points
        self.style = style
    }

    func draw(in ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.move(to: first)
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    func hit(_ point: CGPoint) -> Bool {
        points.contains { hypot($0.x - point.x, $0.y - point.y) < 10 }
    }
}

final class TextAnnotation: Annotation {
    var origin: CGPoint
    var string: String
    let style: AnnotStyle

    init(origin: CGPoint, string: String, style: AnnotStyle) {
        self.origin = origin
        self.string = string
        self.style = style
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let size = max(14, style.lineWidth * 6)
        return [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: style.color,
        ]
    }

    var size: CGSize {
        (string as NSString).size(withAttributes: attributes)
    }

    func draw(in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = g
        (string as NSString).draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    func hit(_ point: CGPoint) -> Bool {
        CGRect(origin: origin, size: size).insetBy(dx: -8, dy: -8).contains(point)
    }
}

final class MosaicAnnotation: Annotation {
    var points: [CGPoint]
    let brushWidth: CGFloat
    let base: NSImage
    let viewScale: CGFloat
    private static var pixellatedCache: [ObjectIdentifier: CGImage] = [:]

    init(points: [CGPoint], brushWidth: CGFloat, base: NSImage, viewScale: CGFloat = 1) {
        self.points = points
        self.brushWidth = brushWidth
        self.base = base
        self.viewScale = viewScale
    }

    func draw(in ctx: CGContext) {
        guard points.count > 0, let pix = pixellatedFull() else { return }
        ctx.saveGState()
        let path = CGMutablePath()
        if points.count == 1 {
            let p = points[0]
            path.addEllipse(in: CGRect(x: p.x - brushWidth/2, y: p.y - brushWidth/2,
                                       width: brushWidth, height: brushWidth))
        } else {
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
        }
        ctx.addPath(path)
        ctx.setLineWidth(brushWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        // draw the fully-pixellated base over the whole view; only the stroke shows through
        let viewSize = CGSize(width: base.size.width / viewScale, height: base.size.height / viewScale)
        ctx.draw(pix, in: CGRect(origin: .zero, size: viewSize))
        ctx.restoreGState()
    }

    private func pixellatedFull() -> CGImage? {
        let key = ObjectIdentifier(base)
        if let cached = Self.pixellatedCache[key] { return cached }
        guard let tiff = base.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let full = CIImage(bitmapImageRep: bitmap) else { return nil }
        let block = max(10, full.extent.width / 90)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(full, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: full.extent.midX, y: full.extent.midY), forKey: kCIInputCenterKey)
        filter.setValue(block, forKey: kCIInputScaleKey)
        guard let out = filter.outputImage?.cropped(to: full.extent) else { return nil }
        let cictx = CIContext()
        guard let cg = cictx.createCGImage(out, from: full.extent) else { return nil }
        Self.pixellatedCache[key] = cg
        return cg
    }

    func hit(_ point: CGPoint) -> Bool {
        points.contains { hypot($0.x - point.x, $0.y - point.y) < brushWidth }
    }
}

final class CanvasView: NSView {
    let baseImage: NSImage
    var imageDrawSize: CGSize = .zero
    var tool: AnnotTool = .rect
    var style = AnnotStyle(color: .systemRed, lineWidth: 3)
    private(set) var annotations: [Annotation] = []
    private var pending: Annotation?
    private var penPoints: [CGPoint] = []
    private var activeTextField: NSTextField?

    init(image: NSImage) {
        self.baseImage = image
        self.imageDrawSize = image.size
        super.init(frame: CGRect(origin: .zero, size: image.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // image is centered in the canvas; extra area is black letterbox
    var imageRect: CGRect {
        let x = (bounds.width - imageDrawSize.width) / 2
        let y = (bounds.height - imageDrawSize.height) / 2
        return CGRect(x: x, y: y, width: imageDrawSize.width, height: imageDrawSize.height)
    }

    // convert a view-space point into image-space (origin at image bottom-left, in imageDrawSize coords)
    private func toImageSpace(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - imageRect.minX, y: p.y - imageRect.minY)
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    func clearAll() {
        annotations.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: CGRect) {
        NSColor.black.setFill()
        bounds.fill()
        let r = imageRect
        baseImage.draw(in: r)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY)
        for a in annotations { a.draw(in: ctx) }
        pending?.draw(in: ctx)
        ctx.restoreGState()
    }

    func render() -> NSImage {
        let img = NSImage(size: baseImage.size)
        img.lockFocus()
        baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
        if let ctx = NSGraphicsContext.current?.cgContext {
            // annotations are stored in imageDrawSize space; scale up to full-res baseImage space
            let sx = baseImage.size.width / max(1, imageDrawSize.width)
            let sy = baseImage.size.height / max(1, imageDrawSize.height)
            ctx.saveGState()
            ctx.scaleBy(x: sx, y: sy)
            for a in annotations { a.draw(in: ctx) }
            ctx.restoreGState()
        }
        img.unlockFocus()
        return img
    }

    override func mouseDown(with event: NSEvent) {
        commitActiveText()
        let raw = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(raw) || tool == .text else { return }
        let p = toImageSpace(raw)
        switch tool {
        case .select:
            break
        case .rect:
            pending = ShapeAnnotation(shape: .rect, start: p, end: p, style: style)
        case .ellipse:
            pending = ShapeAnnotation(shape: .ellipse, start: p, end: p, style: style)
        case .arrow:
            pending = ShapeAnnotation(shape: .arrow, start: p, end: p, style: style)
        case .pen:
            penPoints = [p]
            pending = PenAnnotation(points: penPoints, style: style)
        case .mosaic:
            penPoints = [p]
            let vs = baseImage.size.width / max(1, imageDrawSize.width)
            pending = MosaicAnnotation(points: penPoints, brushWidth: max(20, style.lineWidth * 7), base: baseImage, viewScale: vs)
        case .text:
            beginTextEditing(at: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImageSpace(convert(event.locationInWindow, from: nil))
        switch pending {
        case let s as ShapeAnnotation: s.end = p
        case let m as MosaicAnnotation:
            penPoints.append(p)
            m.points = penPoints
        case let pen as PenAnnotation:
            penPoints.append(p)
            pen.points = penPoints
        default: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let p = pending {
            let valid: Bool
            switch p {
            case let s as ShapeAnnotation: valid = s.rect.width > 3 || s.rect.height > 3
            case is MosaicAnnotation: valid = true
            case let pen as PenAnnotation: valid = pen.points.count > 1
            default: valid = true
            }
            if valid { annotations.append(p) }
        }
        pending = nil
        penPoints = []
        needsDisplay = true
    }

    private func beginTextEditing(at imagePoint: CGPoint) {
        // field lives in view space; imagePoint is image space
        let viewPoint = CGPoint(x: imagePoint.x + imageRect.minX, y: imagePoint.y + imageRect.minY)
        let field = NSTextField(frame: CGRect(x: viewPoint.x, y: viewPoint.y - 12, width: 200, height: 28))
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(white: 0, alpha: 0.35)
        field.textColor = style.color
        field.font = .systemFont(ofSize: max(14, style.lineWidth * 6), weight: .semibold)
        field.focusRingType = .none
        field.placeholderString = "Text…"
        field.target = self
        field.action = #selector(textFieldCommitted)
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    @objc private func textFieldCommitted() {
        commitActiveText()
    }

    func setColor(_ color: NSColor) {
        style.color = color
        if let field = activeTextField {
            field.textColor = color
            if let editor = field.currentEditor() as? NSTextView {
                editor.textColor = color
                editor.insertionPointColor = color
            }
        }
    }

    func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // field frame is view space; store origin in image space
        let origin = CGPoint(x: field.frame.minX - imageRect.minX, y: field.frame.minY + 4 - imageRect.minY)
        field.removeFromSuperview()
        activeTextField = nil
        if !text.isEmpty {
            annotations.append(TextAnnotation(origin: origin, string: text, style: style))
            needsDisplay = true
        }
    }
}

final class AnnotatorWindow: NSWindow, NSWindowDelegate {
    private let sourceURL: URL
    private let canvas: CanvasView
    private var toolButtons: [AnnotTool: NSButton] = [:]
    private var colorSwatches: [ColorSwatchView] = []
    var onDone: ((URL) -> Void)?
    var onScrollCapture: ((@escaping (NSImage?) -> Void) -> Void)?
    var onClosed: (() -> Void)?

    private let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, NSColor.white, NSColor.black,
    ]

    init?(imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return nil }
        self.sourceURL = imageURL
        self.canvas = CanvasView(image: image)

        let toolbarH: CGFloat = 56
        let minContentW: CGFloat = 640
        let minContentH: CGFloat = 360
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1400, height: 900)
        let maxW = visible.width * 0.9
        let maxH = visible.height * 0.85 - toolbarH

        // image drawn at its own (fit-to-screen) size, never stretched
        let fit = min(1, min(maxW / image.size.width, maxH / image.size.height))
        let imageDrawSize = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        // canvas has a comfortable minimum size; image is centered, extra space is black letterbox
        let canvasSize = CGSize(width: max(imageDrawSize.width, min(minContentW, maxW)),
                                height: max(imageDrawSize.height, min(minContentH, maxH)))
        canvas.imageDrawSize = imageDrawSize

        let contentRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height + toolbarH)
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "Annotate"
        isMovableByWindowBackground = false
        isMovable = true
        level = .floating
        isReleasedWhenClosed = false
        backgroundColor = NSColor(white: 0.12, alpha: 1)
        delegate = self

        let root = NSView(frame: contentRect)
        contentView = root

        canvas.frame = CGRect(x: 0, y: toolbarH, width: canvasSize.width, height: canvasSize.height)
        canvas.autoresizingMask = [.width, .height]
        root.addSubview(canvas)

        let toolbar = buildToolbar(width: canvasSize.width, y: 0, height: toolbarH)
        toolbar.autoresizingMask = [.width, .maxYMargin]
        root.addSubview(toolbar)

        selectTool(.rect)
        highlightColor(canvas.style.color)
    }

    private func buildToolbar(width: CGFloat, y: CGFloat, height: CGFloat) -> NSView {
        let bar = NSVisualEffectView(frame: CGRect(x: 0, y: y, width: width, height: height))
        bar.material = .hudWindow
        bar.blendingMode = .behindWindow
        bar.state = .active

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -12),
        ])

        let tools: [(AnnotTool, String, String)] = [
            (.rect, "rectangle", "Rectangle"),
            (.ellipse, "circle", "Ellipse"),
            (.arrow, "arrow.up.right", "Arrow"),
            (.pen, "pencil.tip", "Pen"),
            (.text, "textformat", "Text"),
            (.mosaic, "squareshape.split.3x3", "Mosaic"),
        ]
        for (tool, symbol, help) in tools {
            let b = toolButton(symbol: symbol, help: help)
            b.target = self
            b.action = #selector(toolPicked(_:))
            b.tag = toolTag(tool)
            toolButtons[tool] = b
            stack.addArrangedSubview(b)
        }

        stack.addArrangedSubview(separator())

        for color in palette {
            stack.addArrangedSubview(colorSwatch(color))
        }

        stack.addArrangedSubview(separator())

        let ocr = toolButton(symbol: "text.viewfinder", help: "OCR — recognise text")
        ocr.target = self
        ocr.action = #selector(runOCR)
        stack.addArrangedSubview(ocr)

        stack.addArrangedSubview(separator())

        let undo = toolButton(symbol: "arrow.uturn.backward", help: "Undo")
        undo.target = self
        undo.action = #selector(undoLast)
        stack.addArrangedSubview(undo)

        let save = toolButton(symbol: "square.and.arrow.down", help: "Save to file")
        save.target = self
        save.action = #selector(saveToFile)
        stack.addArrangedSubview(save)

        let cancel = toolButton(symbol: "xmark", help: "Cancel")
        cancel.target = self
        cancel.action = #selector(cancelEditing)
        cancel.contentTintColor = .systemRed
        stack.addArrangedSubview(cancel)

        let done = toolButton(symbol: "checkmark", help: "Done — copy & send")
        done.target = self
        done.action = #selector(finish)
        done.contentTintColor = .systemGreen
        stack.addArrangedSubview(done)

        return bar
    }

    private func toolButton(symbol: String, help: String) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(cfg) {
            b.image = img
        } else {
            b.title = String(help.prefix(1))
            b.font = .systemFont(ofSize: 15, weight: .semibold)
        }
        b.toolTip = help
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        b.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return b
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    private func colorSwatch(_ color: NSColor) -> NSView {
        let swatch = ColorSwatchView(color: color) { [weak self] in
            self?.canvas.setColor(color)
            self?.highlightColor(color)
        }
        colorSwatches.append(swatch)
        return swatch
    }

    private func highlightColor(_ color: NSColor) {
        for s in colorSwatches { s.setSelected(s.color == color) }
    }

    private func toolTag(_ tool: AnnotTool) -> Int {
        switch tool {
        case .select: return 0
        case .rect: return 1
        case .ellipse: return 2
        case .arrow: return 3
        case .pen: return 4
        case .text: return 5
        case .mosaic: return 6
        }
    }

    private func tool(fromTag tag: Int) -> AnnotTool {
        switch tag {
        case 1: return .rect
        case 2: return .ellipse
        case 3: return .arrow
        case 4: return .pen
        case 5: return .text
        case 6: return .mosaic
        default: return .select
        }
    }

    @objc private func toolPicked(_ sender: NSButton) {
        selectTool(tool(fromTag: sender.tag))
    }

    private func selectTool(_ tool: AnnotTool) {
        canvas.tool = tool
        for (t, b) in toolButtons {
            b.layer?.backgroundColor = (t == tool)
                ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func undoLast() { canvas.undo() }

    @objc private func runOCR() {
        canvas.commitActiveText()
        OCR.recognise(in: canvas.baseImage) { [weak self] text in
            DispatchQueue.main.async { self?.presentOCRResult(text) }
        }
    }

    private func presentOCRResult(_ text: String?) {
        let alert = NSAlert()
        if let text = text, !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            alert.messageText = "Text copied to clipboard"
            alert.informativeText = text.count > 400 ? String(text.prefix(400)) + "…" : text
        } else {
            alert.messageText = "No text found"
            alert.informativeText = "Vision couldn't detect any text in this screenshot."
        }
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self, completionHandler: nil)
    }

    @objc private func startScrollCapture() {
        onScrollCapture?({ [weak self] stitched in
            guard let self = self, let img = stitched else { return }
            let out = self.exportImage(img)
            self.close()
            self.onDone?(out)
        })
    }

    @objc private func saveToFile() {
        canvas.commitActiveText()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ShotClip-\(Int(Date().timeIntervalSince1970)).png"
        panel.beginSheetModal(for: self) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self = self else { return }
            if let data = self.canvas.render().pngData() {
                try? data.write(to: url)
            }
        }
    }

    @objc private func cancelEditing() {
        close()
    }

    @objc private func finish() {
        canvas.commitActiveText()
        let out = exportImage(canvas.render())
        close()
        onDone?(out)
    }

    private func exportImage(_ image: NSImage) -> URL {
        if let data = image.pngData() {
            try? data.write(to: sourceURL)
        }
        return sourceURL
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            canvas.undo()
        } else if event.keyCode == 53 {
            cancelEditing()
        } else if event.keyCode == 36 {
            finish()
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}

final class ColorSwatchView: NSView {
    let color: NSColor
    private let action: () -> Void
    private var selected = false

    init(color: NSColor, action: @escaping () -> Void) {
        self.color = color
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ value: Bool) {
        selected = value
        refresh()
    }

    private func refresh() {
        let inset: CGFloat = selected ? 2 : 3
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        let dot = CALayer()
        dot.frame = bounds.insetBy(dx: inset, dy: inset)
        dot.backgroundColor = color.cgColor
        dot.cornerRadius = dot.frame.width / 2
        dot.borderWidth = selected ? 2 : 1
        dot.borderColor = (selected ? NSColor.white : NSColor(white: 1, alpha: 0.3)).cgColor
        layer?.addSublayer(dot)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            action()
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
