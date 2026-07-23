import AppKit

/// After an update (self-update or reinstall), the next launch shows a
/// highlighted "What's new" panel with the release notes for the new version.
enum WhatsNew {
    private static let lastRunKey = "ShotClip.lastRunVersion"
    private static var window: WhatsNewWindow?

    static func showIfUpdated() {
        let current = Updater.currentVersion
        let last = UserDefaults.standard.string(forKey: lastRunKey)
        UserDefaults.standard.set(current, forKey: lastRunKey)
        // First launch ever (no recorded version) — not an update, stay quiet.
        guard let last = last, last != current else { return }

        fetchNotes(for: current) { notes in
            DispatchQueue.main.async {
                present(version: current, previous: last,
                        notes: notes ?? "You're now on version \(current). See the release page for details.")
            }
        }
    }

    private static func fetchNotes(for version: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/tags/v\(version)") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let body = json["body"] as? String, !body.isEmpty else {
                completion(nil); return
            }
            completion(body)
        }.resume()
    }

    private static func present(version: String, previous: String, notes: String) {
        let win = WhatsNewWindow(version: version, previous: previous, notes: notes)
        window = win
        win.onClosed = { window = nil }
        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }
}

final class WhatsNewWindow: NSWindow, NSWindowDelegate {
    var onClosed: (() -> Void)?

    init(version: String, previous: String, notes: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "What's New"
        isReleasedWhenClosed = false
        level = .floating
        delegate = self
        build(version: version, previous: previous, notes: notes)
    }

    override var canBecomeKey: Bool { true }

    private func build(version: String, previous: String, notes: String) {
        let content = NSView(frame: contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        contentView = content

        // Highlighted banner
        let banner = NSView()
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        banner.layer?.cornerRadius = 10
        banner.layer?.cornerCurve = .continuous
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        banner.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(banner)

        let headline = NSTextField(labelWithString: "✨ ShotClip updated: \(previous) → \(version)")
        headline.font = .systemFont(ofSize: 15, weight: .bold)
        headline.textColor = .controlAccentColor
        headline.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(headline)

        let sub = NSTextField(labelWithString: "Here's what's new in this version:")
        sub.font = .systemFont(ofSize: 11.5)
        sub.textColor = .secondaryLabelColor
        sub.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(sub)

        // Notes body
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let tv = NSTextView()
        tv.isEditable = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 12.5)
        tv.string = notes
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        content.addSubview(scroll)

        let ok = NSButton(title: "Nice!", target: self, action: #selector(closeWindow))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        ok.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(ok)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            banner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            banner.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            headline.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            headline.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            headline.trailingAnchor.constraint(lessThanOrEqualTo: banner.trailingAnchor, constant: -14),
            sub.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 3),
            sub.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            sub.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            ok.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            ok.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            ok.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    @objc private func closeWindow() { close() }

    func windowWillClose(_ notification: Notification) { onClosed?() }
}
