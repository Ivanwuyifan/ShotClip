import AppKit
import ScreenCaptureKit

// Grabs a rectangular region of a screen as a full-resolution CGImage.
// macOS 14+: ScreenCaptureKit (SCScreenshotManager). macOS 13: CGWindowListCreateImage.
final class ScreenGrabber {
    let screen: NSScreen
    // Region to grab, in AppKit global coordinates (bottom-left origin).
    let regionGlobal: CGRect

    private var scDisplay: Any?          // SCDisplay, lazily resolved (14+)
    private var scFilter: Any?           // SCContentFilter (14+)

    init(screen: NSScreen, regionGlobal: CGRect) {
        self.screen = screen
        self.regionGlobal = regionGlobal
    }

    // The region in this screen's local, top-left-origin coordinates (points).
    private var regionInScreenTopLeft: CGRect {
        let sf = screen.frame
        // x is same origin; flip y within this screen
        let localX = regionGlobal.minX - sf.minX
        let localYTop = sf.maxY - regionGlobal.maxY
        return CGRect(x: localX, y: localYTop, width: regionGlobal.width, height: regionGlobal.height)
    }

    var pixelScale: CGFloat { screen.backingScaleFactor }

    // Synchronous grab (called off the main thread). Returns full-res CGImage.
    func grab() -> CGImage? {
        if #available(macOS 14.0, *) {
            return grabSCK()
        } else {
            return grabLegacy()
        }
    }

    // MARK: legacy (13)

    private func grabLegacy() -> CGImage? {
        // CGWindowListCreateImage takes a rect in global display space, top-left origin.
        let global = globalTopLeftRect()
        // Symbol still links under SwiftPM; guarded to <14 at call site.
        return CGWindowListCreateImage(global, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }

    // Region in global top-left coordinate space (used by CGWindowList).
    private func globalTopLeftRect() -> CGRect {
        // Height of the primary screen defines the global flip.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let y = primaryHeight - regionGlobal.maxY
        return CGRect(x: regionGlobal.minX, y: y, width: regionGlobal.width, height: regionGlobal.height)
    }

    // MARK: ScreenCaptureKit (14+)

    @available(macOS 14.0, *)
    private func resolveFilter() -> (SCContentFilter, SCDisplay)? {
        if let f = scFilter as? SCContentFilter, let d = scDisplay as? SCDisplay {
            return (f, d)
        }
        let sem = DispatchSemaphore(value: 0)
        var result: (SCContentFilter, SCDisplay)?
        let targetDisplayID = screen.displayID
        SCShareableContent.getWithCompletionHandler { content, _ in
            defer { sem.signal() }
            guard let content = content else { return }
            let display = content.displays.first { $0.displayID == targetDisplayID } ?? content.displays.first
            guard let display = display else { return }
            // Exclude ShotClip's own windows (the overlay) from the capture.
            let ownWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            result = (filter, display)
        }
        sem.wait()
        scFilter = result?.0
        scDisplay = result?.1
        return result
    }

    @available(macOS 14.0, *)
    private func grabSCK() -> CGImage? {
        guard let (filter, _) = resolveFilter() else { return nil }
        let config = SCStreamConfiguration()
        let region = regionInScreenTopLeft
        config.sourceRect = region
        // Full Retina resolution: point size × pixel scale.
        config.width = Int(region.width * pixelScale)
        config.height = Int(region.height * pixelScale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        let sem = DispatchSemaphore(value: 0)
        var image: CGImage?
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { cg, _ in
            image = cg
            sem.signal()
        }
        sem.wait()
        return image
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }
}
