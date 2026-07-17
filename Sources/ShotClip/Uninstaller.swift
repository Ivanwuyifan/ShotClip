import AppKit

enum Uninstaller {
    static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall ShotClip?"
        alert.informativeText = "This removes ShotClip, turns off Open at Startup, and clears its data. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NonBlockingAlert.present(alert) { resp in
            guard resp == .alertFirstButtonReturn else { return }
            perform()
        }
    }

    private static func perform() {
        LaunchAtLogin.set(false)

        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.shotclip"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)

        try? FileManager.default.removeItem(at: Store.shared.baseDir)

        let appPath = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(appPath)"
        tccutil reset ScreenCapture \(bundleID) 2>/dev/null || true
        tccutil reset Accessibility \(bundleID) 2>/dev/null || true
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotclip-uninstall-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [scriptURL.path]
            try p.run()
        } catch {
            NSLog("ShotClip: uninstall script failed: \(error)")
        }

        NSApp.terminate(nil)
    }
}
