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

    // Self-update can only overwrite the app in place if the bundle lives on a
    // writable path. When ShotClip is run straight from a downloaded zip, macOS
    // App Translocation mounts it read-only under .../AppTranslocation/…, so any
    // in-place replace fails. Detect that so we can guide the user instead.
    static func canSelfUpdate() -> Bool {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") { return false }
        // the app bundle must sit in a writable parent directory
        let parent = (path as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
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
        // If the app is running from a read-only / translocated location, it can't
        // replace itself. Guide the user to move it to Applications first.
        guard canSelfUpdate() else {
            promptMoveToApplications(version: version)
            return
        }
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

    private static func promptMoveToApplications(version: String) {
        let alert = NSAlert()
        alert.messageText = "Move ShotClip to Applications to update"
        alert.informativeText = "ShotClip \(version) is available, but it's running from a read-only location (macOS App Translocation), so it can't update itself.\n\nQuit ShotClip, drag it into your Applications folder, then reopen it — after that, updates install automatically.\n\nCurrent version \(currentVersion)."
        alert.addButton(withTitle: "Open Applications Folder")
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        NonBlockingAlert.present(alert) { resp in
            switch resp {
            case .alertFirstButtonReturn:
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
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

        // The release zip may contain ShotClip.app at the root or nested one level
        // down (e.g. inside a "ShotClip/" folder next to install.command), so look
        // in the root first, then one level into any subdirectories.
        func findApp(in dir: URL) -> URL? {
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            if let app = entries.first(where: { $0.pathExtension == "app" }) { return app }
            for sub in entries where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if let nested = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil))?
                    .first(where: { $0.pathExtension == "app" }) {
                    return nested
                }
            }
            return nil
        }
        guard let newApp = findApp(in: work) else { throw UpdateError.appNotFound }

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
        # If the new build's signature differs from the installed one, the old
        # TCC grants are stale (shown ON but not applied) — reset so the new
        # app prompts cleanly. Same-signature updates skip this.
        OLD_REQ=$(codesign -d -r- "\(appPath)" 2>&1 | grep "^designated" || true)
        NEW_REQ=$(codesign -d -r- "$STAGE" 2>&1 | grep "^designated" || true)
        if [ "$OLD_REQ" != "$NEW_REQ" ]; then
            tccutil reset ScreenCapture "\(Bundle.main.bundleIdentifier ?? "com.local.shotclip")" 2>/dev/null || true
            tccutil reset Accessibility "\(Bundle.main.bundleIdentifier ?? "com.local.shotclip")" 2>/dev/null || true
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
