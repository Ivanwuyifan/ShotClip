import AppKit

/// Keeps exactly one canonical copy of the app at /Applications/ShotClip.app.
/// Running from anywhere else (build dir, Downloads, an unzipped release)
/// offers a one-click install that overwrites any older version and relaunches.
/// A fixed path + the stable self-signed cert means macOS keeps the TCC grants.
enum Installer {
    private static let skipKey = "ShotClip.skipInstallPrompt"
    static let canonicalPath = "/Applications/ShotClip.app"

    /// Returns true when launch should stop here (the app is quitting either
    /// to overwrite-install or to defer to the installed copy) — callers must
    /// then skip the rest of startup (permission prompts etc.).
    @discardableResult
    static func offerMoveIfNeeded() -> Bool {
        let current = Bundle.main.bundlePath
        guard !current.hasPrefix("/Applications/") else { return false }

        let installedExists = FileManager.default.fileExists(atPath: canonicalPath)

        if installedExists {
            // Hard block: two copies with the same bundle id fight over TCC
            // grants, so running this copy alongside the installed one is not
            // allowed. Overwrite-install (recommended) or defer to it.
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "ShotClip is already installed in Applications"
            alert.informativeText = "Running two copies at the same time causes permission conflicts (Screen Recording / Accessibility grants follow one copy and silently break the other).\n\nOverwrite the installed copy with this version (recommended), or quit this copy and keep using the installed one."
            alert.addButton(withTitle: "Overwrite & Relaunch")
            alert.addButton(withTitle: "Use Installed Copy")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                installAndRelaunch(from: current)
            default:
                NSWorkspace.shared.open(URL(fileURLWithPath: canonicalPath))
                NSApp.terminate(nil)
            }
            return true
        }

        guard !UserDefaults.standard.bool(forKey: skipKey) else { return false }
        let alert = NSAlert()
        alert.messageText = "Install ShotClip to Applications?"
        alert.informativeText = "Keeping one copy at a fixed location lets macOS remember the permissions you grant (Screen Recording, Accessibility) across updates."
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            installAndRelaunch(from: current)
            return true
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: skipKey)
        default:
            break
        }
        return false
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
