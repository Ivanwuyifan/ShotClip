import Foundation

enum LLMError: LocalizedError {
    case cliNotFound(String)
    case noAPIKey(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let name):
            return "\(name) CLI not found. Install it and log in first (AI Settings… has instructions)."
        case .noAPIKey(let which):
            return "No \(which) API key configured — open AI Settings… from the menu bar."
        case .badResponse(let msg):
            return msg
        }
    }
}

enum LLMClient {
    static func translationPrompt(for text: String) -> String {
        let target: String
        switch LLMConfig.targetLanguage {
        case .auto:
            let hanCount = text.unicodeScalars.filter { $0.properties.isIdeographic }.count
            target = hanCount * 3 > text.count ? "English" : "Simplified Chinese"
        case .chinese: target = "Simplified Chinese"
        case .english: target = "English"
        case .japanese: target = "Japanese"
        }
        return """
        Translate the following text into \(target). \
        Output ONLY the translation — no explanations, no quotes, keep the original line breaks.

        \(text)
        """
    }

    /// Sends `prompt` to the configured backend; completion is delivered on the main queue.
    static func complete(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let done: (Result<String, Error>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
        DispatchQueue.global(qos: .userInitiated).async {
            switch LLMConfig.provider {
            case .claudeCode: runClaudeCLI(prompt: prompt, completion: done)
            case .codex: runCodexCLI(prompt: prompt, completion: done)
            case .anthropicAPI: callAnthropic(prompt: prompt, completion: done)
            case .openAICompatible: callOpenAI(prompt: prompt, completion: done)
            }
        }
    }

    // MARK: - CLI backends (subscription login — no API key needed)

    private static func runClaudeCLI(prompt: String, completion: (Result<String, Error>) -> Void) {
        guard let bin = LLMConfig.findCLI("claude") else {
            completion(.failure(LLMError.cliNotFound("claude")))
            return
        }
        // Override Claude Code's agent system prompt: without this, smaller
        // models answer in their "coding assistant" persona instead of just
        // producing the requested text.
        var args = ["-p", prompt, "--output-format", "text",
                    "--system-prompt",
                    "You are a text-writing engine. Follow the instruction exactly and output ONLY the requested text — no preamble, no explanations, no questions, no offers to help."]
        let model = LLMConfig.cliModel.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { args += ["--model", model] }
        runProcess(bin, args: args, completion: completion)
    }

    private static func runCodexCLI(prompt: String, completion: (Result<String, Error>) -> Void) {
        guard let bin = LLMConfig.findCLI("codex") else {
            completion(.failure(LLMError.cliNotFound("codex")))
            return
        }
        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotclip-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }
        var args = ["exec", "--skip-git-repo-check",
                    "--output-last-message", outFile.path]
        let model = LLMConfig.cliModel.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { args += ["-m", model] }
        args.append(prompt)
        let result = runProcessCapturing(bin, args: args)
        switch result {
        case .failure(let e): completion(.failure(e))
        case .success:
            if let msg = try? String(contentsOf: outFile, encoding: .utf8),
               !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(.success(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                completion(.failure(LLMError.badResponse("codex returned no output — run `codex login` in a terminal?")))
            }
        }
    }

    private static func runProcess(_ bin: String, args: [String],
                                   completion: (Result<String, Error>) -> Void) {
        completion(runProcessCapturing(bin, args: args))
    }

    private static func runProcessCapturing(_ bin: String, args: [String]) -> Result<String, Error> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        proc.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"
        env["PATH"] = (env["PATH"].map { "\($0):" } ?? "") + extra
        proc.environment = env
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do { try proc.run() } catch { return .failure(error) }

        // Drain both pipes concurrently to avoid pipe-buffer deadlock, with a 60s timeout.
        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + 60) == .timedOut {
            proc.terminate()
            return .failure(LLMError.badResponse("LLM call timed out after 60s"))
        }
        proc.waitUntilExit()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        let text = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if proc.terminationStatus != 0 {
            let detail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(LLMError.badResponse(detail.isEmpty ? "CLI exited with status \(proc.terminationStatus)" : String(detail.suffix(300))))
        }
        return .success(text)
    }

    // MARK: - HTTP backends (API key)

    private static func callAnthropic(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let key = LLMConfig.anthropicKey, !key.isEmpty else {
            completion(.failure(LLMError.noAPIKey("Anthropic")))
            return
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": LLMConfig.anthropicModel,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        httpSend(req) { json in
            guard let content = json["content"] as? [[String: Any]],
                  let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            else { return nil }
            return text
        } completion: { completion($0) }
    }

    private static func callOpenAI(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let key = LLMConfig.openAIKey, !key.isEmpty else {
            completion(.failure(LLMError.noAPIKey("OpenAI-compatible")))
            return
        }
        let base = LLMConfig.openAIBaseURL.hasSuffix("/")
            ? String(LLMConfig.openAIBaseURL.dropLast()) : LLMConfig.openAIBaseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            completion(.failure(LLMError.badResponse("Invalid base URL")))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": LLMConfig.openAIModel,
            "messages": [["role": "user", "content": prompt]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        httpSend(req) { json in
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { return nil }
            return text
        } completion: { completion($0) }
    }

    private static func httpSend(_ req: URLRequest,
                                 extract: @escaping ([String: Any]) -> String?,
                                 completion: @escaping (Result<String, Error>) -> Void) {
        URLSession.shared.dataTask(with: req) { data, resp, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(.failure(LLMError.badResponse("Empty or non-JSON response")))
                return
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let detail = (json["error"] as? [String: Any])?["message"] as? String
                    ?? String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
                completion(.failure(LLMError.badResponse("HTTP \(status): \(detail)")))
                return
            }
            if let text = extract(json) {
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                completion(.failure(LLMError.badResponse("Unexpected response shape")))
            }
        }.resume()
    }
}
