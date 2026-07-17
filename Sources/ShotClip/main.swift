import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayWindow()
    private var trackingTimer: Timer?
    private var sendPanel: SendPanel?
    private weak var launchItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        LaunchAtLogin.enableOnFirstRun()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: iconURL) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "✂️"
            }
        }
        let menu = NSMenu()
        addMenuItem(to: menu, title: "Show bar (⌘⇧Space)", symbol: "rectangle.bottomthird.inset.filled", action: #selector(showOverlay))
        addMenuItem(to: menu, title: "Capture region (⌘⇧4)", symbol: "camera.viewfinder", action: #selector(capture))
        menu.addItem(.separator())
        let loginItem = addMenuItem(to: menu, title: "Open at Startup", symbol: "power", action: #selector(toggleLaunchAtLogin))
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        launchItem = loginItem
        addMenuItem(to: menu, title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath", action: #selector(checkUpdates))
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "Uninstall ShotClip…", symbol: "trash", action: #selector(uninstall))
        addMenuItem(to: menu, title: "Quit ShotClip", symbol: "xmark.circle", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        Store.shared.onChange = { [weak self] in
            DispatchQueue.main.async {
                if self?.overlay.isVisible == true { self?.overlay.reload() }
            }
        }

        ClipboardMonitor.shared.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Updater.checkInBackground()
        }

        Capture.onCaptured = { [weak self] url in
            ClipboardMonitor.shared.suppressNext()
            Sender.copyImage(url)

            let panel = SendPanel(imageURL: url)
            self?.sendPanel = panel
            panel.present()
        }

        HotkeyManager.shared.start()
        // ⌘⇧Space -> show bar. keycode 49 = space
        HotkeyManager.shared.register(id: 1, keyCode: 49,
            modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            shotLog("ShotClip: hotkey FIRED id=1 (show bar)")
            DispatchQueue.main.async { self?.overlay.toggle() }
        }
        // ⌘⇧4 -> capture region. keycode 21 = '4'
        HotkeyManager.shared.register(id: 2, keyCode: 21,
            modifiers: UInt32(cmdKey | shiftKey)) {
            shotLog("ShotClip: hotkey FIRED id=2 (capture)")
            DispatchQueue.main.async { Capture.interactiveRegion() }
        }

        startHoverTracking()
    }

    @discardableResult
    private func addMenuItem(to menu: NSMenu, title: String, symbol: String,
                            action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            img.isTemplate = true
            item.image = img
        }
        menu.addItem(item)
        return item
    }

    @objc private func showOverlay() { overlay.toggle() }
    @objc private func capture() { Capture.interactiveRegion() }
    @objc private func checkUpdates() { Updater.checkInBackground(manual: true) }
    @objc private func uninstall() { Uninstaller.confirmAndUninstall() }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
        launchItem?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func startHoverTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.overlay.isVisible, self.overlay.alphaValue > 0.5 else { return }
            let mouse = NSEvent.mouseLocation
            if self.overlay.frame.insetBy(dx: -20, dy: -20).contains(mouse) {
                self.overlay.scheduleHide()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
