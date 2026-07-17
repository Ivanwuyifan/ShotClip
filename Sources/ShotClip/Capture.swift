import Foundation
import AppKit

enum Capture {
    static var onCaptured: ((URL) -> Void)?

    static func interactiveRegion() {
        let url = Store.shared.baseDir
            .appendingPathComponent("shot-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", "-o", url.path]
        proc.terminationHandler = { _ in
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: url.path) {
                    onCaptured?(url)
                }
            }
        }
        do {
            try proc.run()
        } catch {
            NSLog("ShotClip: screencapture failed: \(error)")
        }
    }
}
