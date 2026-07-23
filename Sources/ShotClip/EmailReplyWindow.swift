import AppKit

/// Editable window for AI-drafted email replies: shows the generated reply in
/// an editable text view, a Copy button, and a prompt field to append extra
/// instructions and regenerate. Retains itself while visible.
final class EmailReplyWindow: NSWindow, NSWindowDelegate {
    private static var active: [EmailReplyWindow] = []

    private let emailText: String
    private let textView = NSTextView()
    private let promptField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let regenButton = NSButton(title: "Regenerate", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private var extraInstructions: [String] = []

    static func begin(emailText: String) {
        let win = EmailReplyWindow(emailText: emailText)
        active.append(win)
        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.generate()
    }

    private init(emailText: String) {
        self.emailText = emailText
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "AI Email Reply"
        isReleasedWhenClosed = false
        level = .floating
        delegate = self
        build()
    }

    private func build() {
        let content = NSView(frame: contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        contentView = content

        // Editable reply area
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        content.addSubview(scroll)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(spinner)

        // Extra-instructions field + buttons
        promptField.placeholderString = "Add instructions (e.g. \"更正式一点\", \"politely decline\") and press Regenerate"
        promptField.font = .systemFont(ofSize: 12)
        promptField.translatesAutoresizingMaskIntoConstraints = false
        promptField.target = self
        promptField.action = #selector(regenerate)
        content.addSubview(promptField)

        regenButton.target = self
        regenButton.action = #selector(regenerate)
        regenButton.bezelStyle = .rounded
        regenButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(regenButton)

        copyButton.target = self
        copyButton.action = #selector(copyReply)
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(copyButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            statusLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            spinner.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),

            promptField.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            promptField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            promptField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            regenButton.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 10),
            regenButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            regenButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            copyButton.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 10),
            copyButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    // MARK: - Generation

    private func generate() {
        setBusy(true, note: "Drafting reply…")
        let prompt = Self.replyPrompt(email: emailText, extras: extraInstructions)
        LLMClient.complete(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false, note: "")
                switch result {
                case .success(let reply):
                    self.textView.string = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.statusLabel.stringValue = "Edit freely, or add instructions below and regenerate."
                case .failure(let error):
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func regenerate() {
        let extra = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            extraInstructions.append(extra)
            promptField.stringValue = ""
        }
        generate()
    }

    @objc private func copyReply() {
        ClipboardMonitor.shared.suppressNext()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
        statusLabel.stringValue = "Copied to clipboard ✓"
    }

    private func setBusy(_ busy: Bool, note: String) {
        regenButton.isEnabled = !busy
        copyButton.isEnabled = !busy
        if busy {
            statusLabel.stringValue = note
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    static func replyPrompt(email: String, extras: [String]) -> String {
        var p = """
        You are drafting a reply to the email below. Write a complete, ready-to-send \
        reply in the SAME language as the original email, in proper email format: \
        an appropriate greeting, a clear body that addresses the email's points, \
        and a polite sign-off. Do not include a subject line, quoted original text, \
        or any explanations — output ONLY the reply email text.
        """
        if !extras.isEmpty {
            p += "\n\nAdditional instructions from the user (follow all of them):\n"
            p += extras.map { "- \($0)" }.joined(separator: "\n")
        }
        p += "\n\n--- EMAIL TO REPLY TO ---\n\(email)"
        return p
    }

    // ShotClip is a menu-bar app with no Edit menu, so ⌘C/⌘V/⌘X/⌘A/⌘Z have no
    // key-equivalent route by default — dispatch them to the responder chain.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command {
            switch event.charactersIgnoringModifiers {
            case "c": if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "v": if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "x": if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a": if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z": if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default: break
            }
        } else if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "z" {
            if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    func windowWillClose(_ notification: Notification) {
        Self.active.removeAll { $0 === self }
    }
}
