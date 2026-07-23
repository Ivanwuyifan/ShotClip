import AppKit

/// Result window for screenshot-translate: shows the translation plus a
/// suggested reply in BOTH Chinese and English. Replies are editable and
/// individually copyable; a prompt field appends extra instructions and
/// regenerates. Retains itself while visible.
final class TranslateReplyWindow: NSWindow, NSWindowDelegate {
    private static var active: [TranslateReplyWindow] = []

    private let sourceText: String
    private let translationView = NSTextView()
    private let zhReplyView = NSTextView()
    private let enReplyView = NSTextView()
    private let promptField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let regenButton = NSButton(title: "Regenerate", target: nil, action: nil)
    private var extraInstructions: [String] = []

    static func begin(sourceText: String) {
        let win = TranslateReplyWindow(sourceText: sourceText)
        active.append(win)
        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.generate()
    }

    private init(sourceText: String) {
        self.sourceText = sourceText
        super.init(contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "Translate & Reply"
        isReleasedWhenClosed = false
        level = .floating
        delegate = self
        build()
    }

    // MARK: - UI

    private func makeSection(title: String, view: NSTextView, editable: Bool,
                             into stack: NSStackView, height: CGFloat) {
        let header = NSStackView()
        header.orientation = .horizontal
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let copy = NSButton(title: "Copy", target: self, action: #selector(copySection(_:)))
        copy.bezelStyle = .rounded
        copy.controlSize = .small
        copy.font = .systemFont(ofSize: 11)
        objc_setAssociatedObject(copy, &Self.copyKey, view, .OBJC_ASSOCIATION_ASSIGN)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        header.addArrangedSubview(label)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(copy)
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        view.isEditable = editable
        view.allowsUndo = editable
        view.isRichText = false
        view.font = .systemFont(ofSize: 12.5)
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 5, height: 6)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
    }

    private static var copyKey: UInt8 = 0

    private func build() {
        let content = NSView(frame: contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        makeSection(title: "Translation 译文", view: translationView, editable: false, into: stack, height: 110)
        makeSection(title: "推荐回复(中文)", view: zhReplyView, editable: true, into: stack, height: 100)
        makeSection(title: "Suggested Reply (English)", view: enReplyView, editable: true, into: stack, height: 100)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        promptField.placeholderString = "Add instructions (e.g. \"语气更强硬\", \"mention the deadline\") and press Regenerate"
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

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            spinner.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),

            promptField.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            promptField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            promptField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            regenButton.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 10),
            regenButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            regenButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    // MARK: - Generation

    private func generate() {
        setBusy(true, note: "Translating & drafting replies…")
        let prompt = Self.combinedPrompt(source: sourceText, extras: extraInstructions)
        LLMClient.complete(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false, note: "")
                switch result {
                case .success(let output):
                    let parts = Self.parse(output)
                    self.translationView.string = parts.translation
                    self.zhReplyView.string = parts.zhReply
                    self.enReplyView.string = parts.enReply
                    self.statusLabel.stringValue = "Replies are editable. Add instructions below to regenerate."
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

    @objc private func copySection(_ sender: NSButton) {
        guard let view = objc_getAssociatedObject(sender, &Self.copyKey) as? NSTextView else { return }
        ClipboardMonitor.shared.suppressNext()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(view.string, forType: .string)
        statusLabel.stringValue = "Copied ✓"
    }

    private func setBusy(_ busy: Bool, note: String) {
        regenButton.isEnabled = !busy
        if busy {
            statusLabel.stringValue = note
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    // MARK: - Prompt & parsing

    static func combinedPrompt(source: String, extras: [String]) -> String {
        var p = """
        You are given text captured from the screen (a message, email, chat or post). \
        Produce THREE things and output them EXACTLY in this format, using these \
        markers on their own lines and nothing else:

        ===TRANSLATION===
        The translation of the text: if it is mainly Chinese, translate to English; \
        otherwise translate to Simplified Chinese.
        ===REPLY_ZH===
        A suggested reply to the message, written in Simplified Chinese, natural \
        and appropriate to the content and tone.
        ===REPLY_EN===
        The same suggested reply, written in English.
        """
        if !extras.isEmpty {
            p += "\n\nAdditional instructions from the user for the replies (follow all):\n"
            p += extras.map { "- \($0)" }.joined(separator: "\n")
        }
        p += "\n\n--- CAPTURED TEXT ---\n\(source)"
        return p
    }

    static func parse(_ output: String) -> (translation: String, zhReply: String, enReply: String) {
        func between(_ start: String, _ end: String?) -> String? {
            guard let s = output.range(of: start) else { return nil }
            let tail = output[s.upperBound...]
            if let end = end, let e = tail.range(of: end) {
                return String(tail[..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let t = between("===TRANSLATION===", "===REPLY_ZH===")
        let zh = between("===REPLY_ZH===", "===REPLY_EN===")
        let en = between("===REPLY_EN===", nil)
        if t == nil && zh == nil && en == nil {
            // markers missing — dump everything into the translation box
            return (output.trimmingCharacters(in: .whitespacesAndNewlines), "", "")
        }
        return (t ?? "", zh ?? "", en ?? "")
    }

    @objc private func closeWindow() { close() }

    // Menu-bar app has no Edit menu — route standard edit key equivalents.
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
