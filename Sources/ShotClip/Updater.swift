import AppKit

// Presents an NSAlert WITHOUT blocking the main run loop (so global hotkeys keep working).
// A tiny transparent host window is created just to hang the sheet on; it's torn down on dismiss.
enum NonBlockingAlert {
    private static var hosts: [NSWindow] = []

    static func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.alphaValue = 0
        host.level = .floating
        if let screen = NSScreen.main {
            host.setFrameOrigin(NSPoint(x: screen.frame.midX, y: screen.frame.midY))
        }
        host.orderFrontRegardless()
        hosts.append(host)
        NSApp.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: host) { resp in
            completion?(resp)
            host.orderOut(nil)
            hosts.removeAll { $0 === host }
        }
    }
}

enum Updater {
    static let repo = "Ivanwuyifan/ShotClip"
    private static let apiURL = "https://api.github.com/repos/\(repo)/releases/latest"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    static func checkInBackground(manual: Bool = false) {
        guard let url = URL(string: apiURL) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if manual { DispatchQueue.main.async { showError("Couldn't check for updates. Please try again later.") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isNewer(latest, than: currentVersion) else {
                if manual {
                    DispatchQueue.main.async {
                        let a = NSAlert()
                        a.messageText = "You're up to date"
                        a.informativeText = "ShotClip \(currentVersion) is the latest version."
                        NonBlockingAlert.present(a)
                    }
                }
                return
            }

            let assets = (json["assets"] as? [[String: Any]]) ?? []
            let zipURL = assets.compactMap { $0["browser_download_url"] as? String }
                .first { $0.hasSuffix(".zip") }
            let notes = (json["body"] as? String) ?? ""

            DispatchQueue.main.async {
                promptUpdate(version: latest, notes: notes, zipURLString: zipURL)
            }
        }.resume()
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").map { Int($0) ?? 0 }
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }

    private static func promptUpdate(version: String, notes: String, zipURLString: String?) {
        let alert = NSAlert()
        alert.messageText = "ShotClip \(version) is available"
        alert.informativeText = "Current version \(currentVersion).\n\n\(notes.prefix(300))"
        alert.addButton(withTitle: "Update & Restart")
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        NonBlockingAlert.present(alert) { resp in
            switch resp {
            case .alertFirstButtonReturn:
                if let z = zipURLString, let url = URL(string: z) {
                    downloadAndInstall(url)
                } else {
                    openReleasePage()
                }
            case .alertSecondButtonReturn:
                openReleasePage()
            default:
                break
            }
        }
    }

    private static func openReleasePage() {
        if let url = URL(string: "https://github.com/\(repo)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func downloadAndInstall(_ url: URL) {
        let task = URLSession.shared.downloadTask(with: url) { tmp, _, err in
            guard let tmp = tmp, err == nil else {
                DispatchQueue.main.async { showError("Download failed: \(err?.localizedDescription ?? "unknown error")") }
                return
            }
            do {
                try install(zipAt: tmp)
            } catch {
                DispatchQueue.main.async { showError("Install failed: \(error.localizedDescription)") }
            }
        }
        task.resume()
    }

    private static func install(zipAt tmpZip: URL) throws {
        let fm = FileManager.default
        let appPath = Bundle.main.bundlePath                       // /path/ShotClip.app
        let appURL = URL(fileURLWithPath: appPath)
        let parent = appURL.deletingLastPathComponent()
        let work = fm.temporaryDirectory.appendingPathComponent("ShotClipUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", tmpZip.path, work.path]
        try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.unzipFailed }

        guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.appNotFound }

        // The apply script must live OUTSIDE `work`, otherwise it deletes itself
        // mid-run when it removes `work`, leaving the update half-applied.
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("ShotClipApply-\(UUID().uuidString).sh")
        let logURL = fm.temporaryDirectory.appendingPathComponent("shotclip-update.log")
        // Replace atomically: stage next to the target, swap, only then remove the old copy.
        // If ditto fails, the original app is left untouched.
        let script = """
        #!/bin/bash
        exec > "\(logURL.path)" 2>&1
        set -x
        sleep 1
        STAGE="\(appPath).new"
        rm -rf "$STAGE"
        if ! ditto "\(newApp.path)" "$STAGE"; then
            echo "ditto to stage failed"; exit 1
        fi
        rm -rf "\(appPath)"
        mv "$STAGE" "\(appPath)"
        xattr -dr com.apple.quarantine "\(appPath)" 2>/dev/null || true
        rm -rf "\(work.path)"
        open "\(appPath)"
        rm -f "\(scriptURL.path)"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let applier = Process()
        applier.executableURL = URL(fileURLWithPath: "/bin/bash")
        applier.arguments = [scriptURL.path]
        try applier.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        _ = parent
    }

    private static func showError(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Update error"
        a.informativeText = msg + "\n\nYou can download manually from the release page."
        a.addButton(withTitle: "Open Release Page")
        a.addButton(withTitle: "OK")
        NonBlockingAlert.present(a) { resp in
            if resp == .alertFirstButtonReturn { openReleasePage() }
        }
    }

    enum UpdateError: LocalizedError {
        case unzipFailed, appNotFound
        var errorDescription: String? {
            switch self {
            case .unzipFailed: return "Failed to unzip the update"
            case .appNotFound: return "ShotClip.app not found in the update package"
            }
        }
    }
}
