import AppKit

/// Floating panel that shows OCR / translation results with per-section copy buttons.
/// Retains itself while visible.
final class ResultPopup: NSPanel {
    private static var active: [ResultPopup] = []

    struct Section {
        let title: String
        let text: String
    }

    static func show(title: String, sections: [Section]) {
        let popup = ResultPopup(title: title, sections: sections)
        active.append(popup)
        NSApp.activate(ignoringOtherApps: true)
        popup.center()
        popup.makeKeyAndOrderFront(nil)
    }

    static func showSpinner(title: String) -> ResultPopup {
        let popup = ResultPopup(title: title, sections: nil)
        active.append(popup)
        NSApp.activate(ignoringOtherApps: true)
        popup.center()
        popup.makeKeyAndOrderFront(nil)
        return popup
    }

    func replace(sections: [Section]) {
        buildContent(sections: sections)
    }

    func fail(_ message: String) {
        buildContent(sections: [Section(title: "Error", text: message)])
    }

    private init(title: String, sections: [Section]?) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: false)
        self.title = title
        isFloatingPanel = true
        level = .floating
        isReleasedWhenClosed = false
        minSize = NSSize(width: 380, height: 220)
        if let sections = sections {
            buildContent(sections: sections)
        } else {
            buildSpinner()
        }
    }

    override func close() {
        super.close()
        ResultPopup.active.removeAll { $0 === self }
    }

    override func cancelOperation(_ sender: Any?) { close() }

    private func buildSpinner() {
        let container = NSView()
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "Thinking…")
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -14),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
        ])
        contentView = container
    }

    private func buildContent(sections: [Section]) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for section in sections {
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 8
            let titleLabel = NSTextField(labelWithString: section.title)
            titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            titleLabel.textColor = .secondaryLabelColor
            header.addArrangedSubview(titleLabel)
            let copyButton = NSButton(title: "Copy", target: nil, action: #selector(copySection(_:)))
            copyButton.target = self
            copyButton.bezelStyle = .accessoryBarAction
            copyButton.font = .systemFont(ofSize: 10.5)
            sectionTexts[ObjectIdentifier(copyButton)] = section.text
            header.addArrangedSubview(copyButton)
            stack.addArrangedSubview(header)

            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
            let textView = NSTextView()
            textView.string = section.text
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .systemFont(ofSize: 13)
            textView.textContainerInset = NSSize(width: 6, height: 8)
            textView.autoresizingMask = [.width]
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = true
            scroll.documentView = textView
            stack.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
            scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
    }

    private var sectionTexts: [ObjectIdentifier: String] = [:]

    @objc private func copySection(_ sender: NSButton) {
        guard let text = sectionTexts[ObjectIdentifier(sender)] else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        sender.title = "✓ Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { sender.title = "Copy" }
    }
}
