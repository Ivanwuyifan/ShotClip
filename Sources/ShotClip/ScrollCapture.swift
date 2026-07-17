import AppKit
import CoreGraphics

final class RegionSelectWindow: NSWindow {
    private var startPoint: CGPoint?
    private var currentRect = CGRect.zero
    private let selectionLayer = CAShapeLayer()
    var onSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = NSColor(white: 0, alpha: 0.28)
        isOpaque = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        selectionLayer.fillColor = NSColor(white: 1, alpha: 0.12).cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.lineWidth = 2
        view.layer?.addSublayer(selectionLayer)
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = event.locationInWindow
        currentRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y),
                             width: abs(p.x - s.x), height: abs(p.y - s.y))
        selectionLayer.path = CGPath(rect: currentRect, transform: nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard currentRect.width > 20, currentRect.height > 20 else {
            onCancel?()
            return
        }
        onSelected?(currentRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }
}

enum ScrollCapture {
    private static var window: RegionSelectWindow?

    static func begin(completion: @escaping (NSImage?) -> Void) {
        guard let screen = NSScreen.main else { completion(nil); return }
        let win = RegionSelectWindow(screen: screen)
        window = win
        win.onCancel = {
            win.orderOut(nil)
            window = nil
            completion(nil)
        }
        win.onSelected = { rectInWindow in
            win.orderOut(nil)
            window = nil
            let screenRect = CGRect(x: screen.frame.minX + rectInWindow.minX,
                                    y: screen.frame.minY + rectInWindow.minY,
                                    width: rectInWindow.width, height: rectInWindow.height)
            runScrollAndStitch(screenRect: screenRect, screen: screen, completion: completion)
        }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private static func runScrollAndStitch(screenRect: CGRect, screen: NSScreen,
                                           completion: @escaping (NSImage?) -> Void) {
        let cgRect = flipToCG(screenRect, screen: screen)
        DispatchQueue.global(qos: .userInitiated).async {
            var frames: [CGImage] = []
            let maxSteps = 40
            let scrollAmount: Int32 = -Int32(cgRect.height * 0.75)
            var previous: CGImage?
            var duplicateStreak = 0

            for _ in 0..<maxSteps {
                guard let frame = grab(cgRect) else { break }
                if let prev = previous, imagesEqual(prev, frame) {
                    duplicateStreak += 1
                    if duplicateStreak >= 2 { break }
                } else {
                    duplicateStreak = 0
                    frames.append(frame)
                    previous = frame
                }
                scroll(by: scrollAmount, at: CGPoint(x: cgRect.midX, y: cgRect.midY))
                Thread.sleep(forTimeInterval: 0.45)
            }

            let stitched = stitch(frames)
            DispatchQueue.main.async { completion(stitched) }
        }
    }

    private static func flipToCG(_ rect: CGRect, screen: NSScreen) -> CGRect {
        let screenHeight = screen.frame.height
        let flippedY = screenHeight - rect.maxY + screen.frame.minY
        return CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
    }

    private static func grab(_ cgRect: CGRect) -> CGImage? {
        CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }

    private static func scroll(by amount: Int32, at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: amount, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    private static func imagesEqual(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        guard let da = pixels(a), let db = pixels(b) else { return false }
        return da == db
    }

    private static func pixels(_ image: CGImage) -> Data? {
        let w = image.width, h = image.height
        let bytesPerRow = w * 4
        var data = Data(count: bytesPerRow * h)
        let space = CGColorSpaceCreateDeviceRGB()
        let ok = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? data : nil
    }

    private static func stitch(_ frames: [CGImage]) -> NSImage? {
        guard let first = frames.first else { return nil }
        if frames.count == 1 {
            return NSImage(cgImage: first, size: CGSize(width: first.width, height: first.height))
        }
        let width = first.width
        var segments: [(image: CGImage, top: Int)] = [(first, 0)]
        for i in 1..<frames.count {
            let overlap = findOverlap(top: frames[i - 1], bottom: frames[i])
            segments.append((frames[i], overlap))
        }

        var totalHeight = first.height
        for i in 1..<segments.count {
            totalHeight += frames[i].height - segments[i].top
        }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        var yOffset = 0
        for (idx, seg) in segments.enumerated() {
            let drawnHeight = idx == 0 ? seg.image.height : seg.image.height - seg.top
            let srcHeight = drawnHeight
            let destY = totalHeight - yOffset - srcHeight
            let cropped = idx == 0
                ? seg.image
                : seg.image.cropping(to: CGRect(x: 0, y: 0, width: width, height: srcHeight)) ?? seg.image
            ctx.draw(cropped, in: CGRect(x: 0, y: destY, width: width, height: srcHeight))
            yOffset += srcHeight
        }

        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: CGSize(width: width, height: totalHeight))
    }

    private static func findOverlap(top: CGImage, bottom: CGImage) -> Int {
        guard let topData = pixels(top), let bottomData = pixels(bottom) else { return 0 }
        let w = top.width, h = top.height
        let bytesPerRow = w * 4
        let sampleRows = min(60, h / 4)
        var bestOffset = 0
        var bestScore = Int.max

        let maxSearch = min(h - sampleRows, h * 3 / 4)
        var offset = 0
        while offset < maxSearch {
            var score = 0
            let step = max(1, bytesPerRow / 64)
            for row in 0..<sampleRows {
                let topRow = (h - sampleRows + row) * bytesPerRow
                let bottomRow = (offset + row) * bytesPerRow
                var col = 0
                while col < bytesPerRow {
                    let d = Int(topData[topRow + col]) - Int(bottomData[bottomRow + col])
                    score += d * d
                    col += step
                }
                if score > bestScore { break }
            }
            if score < bestScore {
                bestScore = score
                bestOffset = offset + sampleRows
            }
            offset += 1
        }
        return bestOffset
    }
}
