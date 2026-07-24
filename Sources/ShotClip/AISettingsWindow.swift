import AppKit

/// Configuration window for the translation backend: Claude Code / Codex
/// subscription CLIs, or a raw Anthropic / OpenAI-compatible API key.
final class AISettingsWindow: NSWindow {
    private static var current: AISettingsWindow?

    private let providerPopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let anthropicKeyField = NSSecureTextField()
    private let anthropicModelField = NSTextField()
    private let cliModelField = NSComboBox()
    private let openAIKeyField = NSSecureTextField()
    private let openAIBaseField = NSTextField()
    private let openAIModelField = NSTextField()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let testButton = NSButton()

    private var anthropicRows: [NSView] = []
    private var openAIRows: [NSView] = []
    private var cliRow: NSView?
    private var cliModelRow: NSView?

    static func present() {
        if let existing = current {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = AISettingsWindow()
        current = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "AI Settings"
        isReleasedWhenClosed = false
        delegate = self
        buildUI()
        loadValues()
        refreshVisibility()
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(row("Backend", control: providerPopup))
        providerPopup.removeAllItems()
        for p in LLMProvider.allCases { providerPopup.addItem(withTitle: p.label) }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)

        let cli = NSTextField(wrappingLabelWithString: "")
        cli.font = .systemFont(ofSize: 11.5)
        cli.textColor = .secondaryLabelColor
        cliRow = cli
        stack.addArrangedSubview(cli)
        cli.widthAnchor.constraint(equalToConstant: 430).isActive = true

        cliModelField.placeholderString = "empty = CLI default"
        cliModelField.completes = true
        let cliModelRow = row("Model (optional)", control: cliModelField)
        self.cliModelRow = cliModelRow
        stack.addArrangedSubview(cliModelRow)

        let anthropicKeyRow = row("API key", control: anthropicKeyField)
        let anthropicModelRow = row("Model", control: anthropicModelField)
        anthropicRows = [anthropicKeyRow, anthropicModelRow]
        stack.addArrangedSubview(anthropicKeyRow)
        stack.addArrangedSubview(anthropicModelRow)

        let openAIKeyRow = row("API key", control: openAIKeyField)
        let openAIBaseRow = row("Base URL", control: openAIBaseField)
        let openAIModelRow = row("Model", control: openAIModelField)
        openAIRows = [openAIKeyRow, openAIBaseRow, openAIModelRow]
        stack.addArrangedSubview(openAIKeyRow)
        stack.addArrangedSubview(openAIBaseRow)
        stack.addArrangedSubview(openAIModelRow)

        stack.addArrangedSubview(row("Translate to", control: languagePopup))
        languagePopup.removeAllItems()
        for l in TargetLanguage.allCases { languagePopup.addItem(withTitle: l.label) }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        testButton.title = "Save & Test"
        testButton.bezelStyle = .rounded
        testButton.keyEquivalent = "\r"
        testButton.target = self
        testButton.action = #selector(saveAndTest)
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveOnly))
        saveButton.bezelStyle = .rounded
        buttons.addArrangedSubview(testButton)
        buttons.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttons)

        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalToConstant: 430).isActive = true

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        contentView = container
        setContentSize(NSSize(width: 480, height: 420))
    }

    private func row(_ label: String, control: NSControl) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 12)
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        if let field = control as? NSTextField {
            field.font = .systemFont(ofSize: 12)
        }
        let v = NSView()
        v.addSubview(l)
        v.addSubview(control)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            l.widthAnchor.constraint(equalToConstant: 90),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: l.trailingAnchor, constant: 10),
            control.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            control.topAnchor.constraint(equalTo: v.topAnchor),
            control.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            v.widthAnchor.constraint(equalToConstant: 430),
        ])
        return v
    }

    private func loadValues() {
        providerPopup.selectItem(at: LLMProvider.allCases.firstIndex(of: LLMConfig.provider) ?? 0)
        languagePopup.selectItem(at: TargetLanguage.allCases.firstIndex(of: LLMConfig.targetLanguage) ?? 0)
        anthropicKeyField.stringValue = LLMConfig.anthropicKey ?? ""
        anthropicModelField.stringValue = LLMConfig.anthropicModel
        openAIKeyField.stringValue = LLMConfig.openAIKey ?? ""
        openAIBaseField.stringValue = LLMConfig.openAIBaseURL
        openAIModelField.stringValue = LLMConfig.openAIModel
        cliModelField.stringValue = LLMConfig.cliModel
    }

    private var selectedProvider: LLMProvider {
        LLMProvider.allCases[max(0, providerPopup.indexOfSelectedItem)]
    }

    @objc private func providerChanged() { refreshVisibility() }

    private func refreshVisibility() {
        let p = selectedProvider
        anthropicRows.forEach { $0.isHidden = p != .anthropicAPI }
        openAIRows.forEach { $0.isHidden = p != .openAICompatible }
        cliModelRow?.isHidden = !(p == .claudeCode || p == .codex)
        let presets: [String]
        switch p {
        case .claudeCode: presets = ["fable", "opus", "sonnet", "haiku"]   // aliases always resolve to the latest model
        case .codex:      presets = ["gpt-5-codex", "gpt-5", "o3"]
        default:          presets = []
        }
        if cliModelField.objectValues as? [String] != presets {
            let current = cliModelField.stringValue
            cliModelField.removeAllItems()
            cliModelField.addItems(withObjectValues: presets)
            cliModelField.stringValue = current
        }
        guard let cli = cliRow as? NSTextField else { return }
        switch p {
        case .claudeCode:
            if let path = LLMConfig.findCLI("claude") {
                cli.stringValue = "✓ claude CLI found at \(path). It uses your Claude subscription login — if calls fail, run `claude` in a terminal and log in once."
            } else {
                cli.stringValue = "✗ claude CLI not found. Install Claude Code (https://claude.com/claude-code), run `claude` once to log in with your subscription, then reopen this window."
            }
            cli.isHidden = false
        case .codex:
            if let path = LLMConfig.findCLI("codex") {
                cli.stringValue = "✓ codex CLI found at \(path). It uses your ChatGPT subscription login — if calls fail, run `codex login` in a terminal."
            } else {
                cli.stringValue = "✗ codex CLI not found. Install it (`npm i -g @openai/codex` or `brew install codex`), run `codex login`, then reopen this window."
            }
            cli.isHidden = false
        default:
            cli.isHidden = true
        }
    }

    private func save() {
        LLMConfig.provider = selectedProvider
        LLMConfig.targetLanguage = TargetLanguage.allCases[max(0, languagePopup.indexOfSelectedItem)]
        LLMConfig.anthropicKey = anthropicKeyField.stringValue
        LLMConfig.anthropicModel = anthropicModelField.stringValue.isEmpty
            ? "claude-sonnet-5" : anthropicModelField.stringValue
        LLMConfig.openAIKey = openAIKeyField.stringValue
        LLMConfig.openAIBaseURL = openAIBaseField.stringValue.isEmpty
            ? "https://api.openai.com/v1" : openAIBaseField.stringValue
        LLMConfig.openAIModel = openAIModelField.stringValue.isEmpty
            ? "gpt-4o-mini" : openAIModelField.stringValue
        LLMConfig.cliModel = cliModelField.stringValue.trimmingCharacters(in: .whitespaces)
    }

    @objc private func saveOnly() {
        save()
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Saved."
    }

    @objc private func saveAndTest() {
        save()
        testButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Testing — asking the model to say “ok”…"
        LLMClient.complete(prompt: "Reply with exactly: ok") { [weak self] result in
            guard let self = self else { return }
            self.testButton.isEnabled = true
            switch result {
            case .success(let text):
                self.statusLabel.textColor = .systemGreen
                self.statusLabel.stringValue = "✓ Working — model replied: \(text.prefix(80))"
            case .failure(let error):
                self.statusLabel.textColor = .systemRed
                self.statusLabel.stringValue = "✗ \(error.localizedDescription)"
            }
        }
    }
}

extension AISettingsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AISettingsWindow.current = nil
    }
}
