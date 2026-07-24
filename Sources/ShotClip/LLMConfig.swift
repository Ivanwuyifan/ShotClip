import Foundation
import Security

enum LLMProvider: String, CaseIterable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case anthropicAPI = "anthropic-api"
    case openAICompatible = "openai-compatible"

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code (subscription login)"
        case .codex: return "Codex (ChatGPT subscription login)"
        case .anthropicAPI: return "Anthropic API key"
        case .openAICompatible: return "OpenAI-compatible API key"
        }
    }

    var usesCLI: Bool { self == .claudeCode || self == .codex }
}

enum TargetLanguage: String, CaseIterable {
    case auto = "auto"
    case chinese = "Chinese (Simplified)"
    case english = "English"
    case japanese = "Japanese"

    var label: String {
        switch self {
        case .auto: return "Auto (中 ↔ EN)"
        case .chinese: return "中文"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}

enum LLMConfig {
    private static let d = UserDefaults.standard

    static var provider: LLMProvider {
        get { LLMProvider(rawValue: d.string(forKey: "ShotClip.llm.provider") ?? "") ?? .claudeCode }
        set { d.set(newValue.rawValue, forKey: "ShotClip.llm.provider") }
    }

    static var anthropicModel: String {
        get { d.string(forKey: "ShotClip.llm.anthropicModel") ?? "claude-sonnet-5" }
        set { d.set(newValue, forKey: "ShotClip.llm.anthropicModel") }
    }

    static var openAIBaseURL: String {
        get { d.string(forKey: "ShotClip.llm.openaiBaseURL") ?? "https://api.openai.com/v1" }
        set { d.set(newValue, forKey: "ShotClip.llm.openaiBaseURL") }
    }

    static var openAIModel: String {
        get { d.string(forKey: "ShotClip.llm.openaiModel") ?? "gpt-4o-mini" }
        set { d.set(newValue, forKey: "ShotClip.llm.openaiModel") }
    }

    /// Optional model override for the CLI backends (claude --model / codex -m).
    /// Empty = use the CLI's own default.
    static var cliModel: String {
        get { d.string(forKey: "ShotClip.llm.cliModel") ?? "" }
        set { d.set(newValue, forKey: "ShotClip.llm.cliModel") }
    }

    static var targetLanguage: TargetLanguage {
        get { TargetLanguage(rawValue: d.string(forKey: "ShotClip.llm.targetLang") ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: "ShotClip.llm.targetLang") }
    }

    // API keys live in the login Keychain, not UserDefaults.
    static var anthropicKey: String? {
        get { Keychain.read(account: "anthropic") }
        set { Keychain.write(account: "anthropic", value: newValue) }
    }

    static var openAIKey: String? {
        get { Keychain.read(account: "openai") }
        set { Keychain.write(account: "openai", value: newValue) }
    }

    /// Locates a CLI binary; SPM apps launched from Finder get a minimal PATH,
    /// so check the usual install locations too.
    static func findCLI(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "\(home)/.claude/local/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.nvm/current/bin/\(name)",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        // fall back to the user's login shell PATH
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return proc.terminationStatus == 0 && !out.isEmpty ? out : nil
    }
}

enum Keychain {
    private static let service = "com.shotclip.llm"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(account: String, value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value = value, !value.isEmpty,
              let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
