import AppKit

/// Keeps exactly one canonical copy of the app at /Applications/ShotClip.app.
/// Running from anywhere else (build dir, Downloads, an unzipped release)
/// offers a one-click install that overwrites any older version and relaunches.
/// A fixed path + the stable self-signed cert means macOS keeps the TCC grants.
enum Installer {
    private static let skipKey = "ShotClip.skipInstallPrompt"
    static let canonicalPath = "/Applications/ShotClip.app"

    static func offerMoveIfNeeded() {
        let current = Bundle.main.bundlePath
        guard !current.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: skipKey) else { return }

        let alert = NSAlert()
        let replacing = FileManager.default.fileExists(atPath: canonicalPath)
        alert.messageText = replacing
            ? "Replace the ShotClip in Applications with this version?"
            : "Install ShotClip to Applications?"
        alert.informativeText = "Keeping one copy at a fixed location lets macOS remember the permissions you grant (Screen Recording, Accessibility) across updates."
        alert.addButton(withTitle: replacing ? "Replace & Relaunch" : "Install & Relaunch")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            installAndRelaunch(from: current)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: skipKey)
        default:
            break
        }
    }

    private static func installAndRelaunch(from source: String) {
        // Quit any other running copy (e.g. the old version in /Applications).
        let myPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.shotclip")
        where app.processIdentifier != myPID {
            app.terminate()
        }

        // Copy after this process exits, then relaunch the installed copy.
        let script = """
        sleep 0.5
        rm -rf "\(canonicalPath)"
        /usr/bin/ditto "\(source)" "\(canonicalPath)"
        /usr/bin/xattr -dr com.apple.quarantine "\(canonicalPath)" 2>/dev/null
        /usr/bin/open "\(canonicalPath)"
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script]
        do {
            try proc.run()
            NSApp.terminate(nil)
        } catch {
            let fail = NSAlert()
            fail.messageText = "Install failed"
            fail.informativeText = error.localizedDescription
            fail.runModal()
        }
    }
}
