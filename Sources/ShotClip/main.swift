import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayWindow()
    private let historyPanel = HistoryPanel()
    private var trackingTimer: Timer?
    private var sendPanel: SendPanel?
    private var annotator: AnnotatorWindow?
    private weak var launchItem: NSMenuItem?
    private weak var editModeItem: NSMenuItem?

    static var editModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ShotClip.editMode") }
        set { UserDefaults.standard.set(newValue, forKey: "ShotClip.editMode") }
    }

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
        addMenuItem(to: menu, title: "Scrolling Capture…", symbol: "arrow.up.and.down.square", action: #selector(scrollingCapture))
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "Extract Text from Screen (⌘⇧E)", symbol: "text.viewfinder", action: #selector(extractText))
        addMenuItem(to: menu, title: "Translate Screenshot (⌘⇧T)", symbol: "character.bubble", action: #selector(translateShot))
        addMenuItem(to: menu, title: "Translate Selection (⌘⇧L)", symbol: "globe", action: #selector(translateSelection))
        addMenuItem(to: menu, title: "Clipboard History (⌘⇧V)", symbol: "list.clipboard", action: #selector(showHistory))
        addMenuItem(to: menu, title: "AI Settings…", symbol: "brain", action: #selector(showAISettings))
        menu.addItem(.separator())
        let editItem = addMenuItem(to: menu, title: "Edit mode (annotate after capture)", symbol: "pencil.and.outline", action: #selector(toggleEditMode))
        editItem.state = Self.editModeEnabled ? .on : .off
        editModeItem = editItem
        menu.addItem(.separator())
        let loginItem = addMenuItem(to: menu, title: "Open at Startup", symbol: "power", action: #selector(toggleLaunchAtLogin))
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        launchItem = loginItem
        addMenuItem(to: menu, title: "Permissions & Setup…", symbol: "checkmark.shield", action: #selector(showOnboarding))
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

        Installer.offerMoveIfNeeded()
        Onboarding.showIfNeeded()

        Capture.onCaptured = { [weak self] url in
            if Self.editModeEnabled {
                self?.openAnnotator(url)
            } else {
                self?.finalize(url)
            }
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
        // ⌘⇧E -> extract text from a screen region. keycode 14 = 'e'
        HotkeyManager.shared.register(id: 3, keyCode: 14,
            modifiers: UInt32(cmdKey | shiftKey)) {
            shotLog("ShotClip: hotkey FIRED id=3 (extract text)")
            DispatchQueue.main.async { TextActions.extractTextFromRegion() }
        }
        // ⌘⇧T -> capture a region and translate its text. keycode 17 = 't'
        HotkeyManager.shared.register(id: 4, keyCode: 17,
            modifiers: UInt32(cmdKey | shiftKey)) {
            shotLog("ShotClip: hotkey FIRED id=4 (translate shot)")
            DispatchQueue.main.async { TextActions.translateRegion() }
        }
        // ⌘⇧L -> translate the current selection. keycode 37 = 'l'
        HotkeyManager.shared.register(id: 5, keyCode: 37,
            modifiers: UInt32(cmdKey | shiftKey)) {
            shotLog("ShotClip: hotkey FIRED id=5 (translate selection)")
            DispatchQueue.main.async { TextActions.translateSelection() }
        }
        // ⌘⇧V -> clipboard history panel. keycode 9 = 'v'
        HotkeyManager.shared.register(id: 6, keyCode: 9,
            modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            shotLog("ShotClip: hotkey FIRED id=6 (history)")
            DispatchQueue.main.async { self?.historyPanel.toggle() }
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

    private func openAnnotator(_ url: URL) {
        guard let window = AnnotatorWindow(imageURL: url) else {
            finalize(url)
            return
        }
        window.onDone = { [weak self] finalURL in
            self?.annotator = nil
            self?.finalize(finalURL)
        }
        window.onScrollCapture = { done in
            ScrollCapture.begin(completion: done)
        }
        window.onClosed = { [weak self] in
            self?.annotator = nil
        }
        annotator = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func finalize(_ url: URL) {
        Store.shared.addShot(url)
        ClipboardMonitor.shared.suppressNext()
        Sender.copyImage(url)
        let panel = SendPanel(imageURL: url)
        sendPanel = panel
        panel.present()
    }

    @objc private func showOverlay() { overlay.toggle() }
    @objc private func capture() { Capture.interactiveRegion() }
    @objc private func extractText() { TextActions.extractTextFromRegion() }
    @objc private func translateShot() { TextActions.translateRegion() }
    @objc private func translateSelection() { TextActions.translateSelection() }
    @objc private func showHistory() { historyPanel.toggle() }
    @objc private func showAISettings() { AISettingsWindow.present() }

    @objc private func scrollingCapture() {
        ScrollCapture.begin { [weak self] image in
            guard let self = self, let image = image, let data = image.pngData() else { return }
            let url = Store.shared.baseDir
                .appendingPathComponent("shot-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).png")
            try? data.write(to: url)
            if Self.editModeEnabled {
                self.openAnnotator(url)
            } else {
                self.finalize(url)
            }
        }
    }
    @objc private func checkUpdates() { Updater.checkInBackground(manual: true) }
    @objc private func showOnboarding() { Onboarding.present() }
    @objc private func uninstall() { Uninstaller.confirmAndUninstall() }

    @objc private func toggleEditMode() {
        Self.editModeEnabled.toggle()
        editModeItem?.state = Self.editModeEnabled ? .on : .off
    }

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
