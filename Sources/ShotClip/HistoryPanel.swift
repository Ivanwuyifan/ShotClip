import AppKit

/// Vertical clipboard-history panel (⌘⇧V): every stored text / link / image /
/// screenshot in a searchable list. Click a row (or press its number) to copy.
final class HistoryPanel: NSPanel, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let listStack = NSStackView()
    private let scroll = NSScrollView()
    private var items: [TimelineItem] = []
    private var filtered: [TimelineItem] = []
    private var outsideClickMonitor: Any?

    init() {
        let w: CGFloat = 420
        let h: CGFloat = 520
        super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                   styleMask: [.nonactivatingPanel, .titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "Clipboard History"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 320, height: 300)
        buildUI()
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { hidePanel() }

    private func buildUI() {
        let container = NSView()

        searchField.placeholderString = "Search clipboard history…"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 6
        listStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let flipped = FlippedClipView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView = flipped
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = listStack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            listStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        contentView = container
    }

    func toggle() {
        if isVisible && alphaValue > 0.5 { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        Store.shared.rescanShots()
        items = Store.shared.timeline()
        searchField.stringValue = ""
        applyFilter("")
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
        installOutsideClickMonitor()
    }

    func hidePanel() {
        removeOutsideClickMonitor()
        orderOut(nil)
    }

    override func close() { hidePanel() }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                switch item {
                case .shot: return "screenshot".contains(q)
                case .clip(let c):
                    switch c.kind {
                    case .text(let s): return s.lowercased().contains(q)
                    case .image: return "image".contains(q)
                    }
                }
            }
        }
        reloadRows()
    }

    private func reloadRows() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if filtered.isEmpty {
            let l = NSTextField(labelWithString: items.isEmpty
                ? "Clipboard history is empty — copy something first."
                : "No matches.")
            l.textColor = .secondaryLabelColor
            l.font = .systemFont(ofSize: 12)
            listStack.addArrangedSubview(l)
            return
        }
        for item in filtered {
            let rowView = HistoryRowView(item: item) { [weak self] in
                self?.copyItem(item)
            }
            listStack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func copyItem(_ item: TimelineItem) {
        ClipboardMonitor.shared.suppressNext()
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item {
        case .shot(let s):
            if let img = NSImage(contentsOf: s.url) { pb.writeObjects([img]) }
        case .clip(let c):
            switch c.kind {
            case .text(let str): pb.setString(str, forType: .string)
            case .image(let url):
                if let img = NSImage(contentsOf: url) { pb.writeObjects([img]) }
            }
        }
        hidePanel()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { self.hidePanel() }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class HistoryRowView: NSView {
    private let onClick: () -> Void
    private var tracking: NSTrackingArea?

    init(item: TimelineItem, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        let badge = NSTextField(labelWithString: item.type.label)
        badge.font = .systemFont(ofSize: 9.5, weight: .bold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.drawsBackground = false
        let badgeWrap = NSView()
        badgeWrap.wantsLayer = true
        badgeWrap.layer?.backgroundColor = item.type.headerColor.cgColor
        badgeWrap.layer?.cornerRadius = 5
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeWrap.translatesAutoresizingMaskIntoConstraints = false
        badgeWrap.addSubview(badge)

        let time = NSTextField(labelWithString: Store.relativeTime(item.createdAt))
        time.font = .systemFont(ofSize: 10)
        time.textColor = .tertiaryLabelColor
        time.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badgeWrap)
        addSubview(time)

        var bottomAnchorTarget: NSLayoutYAxisAnchor
        var contentView: NSView
        switch item {
        case .shot(let s):
            contentView = thumbView(s.thumbnail)
        case .clip(let c):
            switch c.kind {
            case .image(let url):
                contentView = thumbView(NSImage(contentsOf: url))
            case .text(let str):
                let label = NSTextField(wrappingLabelWithString: String(str.prefix(300)))
                label.font = .systemFont(ofSize: 11.5)
                label.maximumNumberOfLines = 4
                label.textColor = .labelColor
                contentView = label
            }
        }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        bottomAnchorTarget = contentView.bottomAnchor

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: badgeWrap.leadingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: badgeWrap.trailingAnchor, constant: -6),
            badge.topAnchor.constraint(equalTo: badgeWrap.topAnchor, constant: 2),
            badge.bottomAnchor.constraint(equalTo: badgeWrap.bottomAnchor, constant: -2),
            badgeWrap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badgeWrap.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            time.centerYAnchor.constraint(equalTo: badgeWrap.centerYAnchor),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            contentView.topAnchor.constraint(equalTo: badgeWrap.bottomAnchor, constant: 6),
            bottomAnchor.constraint(equalTo: bottomAnchorTarget, constant: 8),
        ])
    }

    private func thumbView(_ image: NSImage?) -> NSView {
        let iv = NSImageView()
        iv.image = image
        iv.imageScaling = .scaleProportionallyDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        iv.heightAnchor.constraint(lessThanOrEqualToConstant: 72).isActive = true
        return iv
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
