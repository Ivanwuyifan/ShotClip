import Foundation
import AppKit

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()
    private var lastChangeCount: Int
    private var timer: Timer?
    private var suppressUntilChangeCount: Int?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func suppressNext() {
        suppressUntilChangeCount = NSPasteboard.general.changeCount + 1
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let target = suppressUntilChangeCount, pb.changeCount <= target {
            suppressUntilChangeCount = nil
            return
        }

        if let str = pb.string(forType: .string),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Store.shared.addClipText(str)
        } else if let img = NSImage(pasteboard: pb) {
            Store.shared.addClipImage(img)
        }
    }
}
