import AppKit
import Carbon.HIToolbox

/// Screen text actions: extract text from any on-screen region (even where the
/// app blocks copying), and translate — a captured region or the current selection.
enum TextActions {

    // MARK: - Extract text (⌘⇧E)

    /// Select a region → offline Vision OCR → text lands on the clipboard,
    /// in the clipboard history, and in a popup.
    static func extractTextFromRegion() {
        captureTempRegion { image in
            guard let image = image else { return }
            let popup = ResultPopup.showSpinner(title: "Extract Text")
            OCR.recognise(in: image) { text in
                DispatchQueue.main.async {
                    guard let text = text, !text.isEmpty else {
                        popup.fail("No text recognised in the selected region.")
                        return
                    }
                    copyToClipboardAndHistory(text)
                    popup.replace(sections: [.init(title: "Extracted text (copied to clipboard)", text: text)])
                }
            }
        }
    }

    // MARK: - AI email reply (screenshot an email, get a drafted reply)

    static func replyToEmail() {
        captureTempRegion { image in
            guard let image = image else { return }
            replyToEmail(image: image)
        }
    }

    /// Same flow for an image already in hand (e.g. the editor's current shot).
    static func replyToEmail(image: NSImage) {
        OCR.recognise(in: image) { text in
            DispatchQueue.main.async {
                guard let text = text, !text.isEmpty else {
                    ResultPopup.show(title: "AI Email Reply", sections: [
                        .init(title: "No text recognised",
                              text: "Select the email's text area and try again."),
                    ])
                    return
                }
                EmailReplyWindow.begin(emailText: text)
            }
        }
    }

    // MARK: - Operate on an already-captured image (annotation editor)

    /// OCR an image already in hand (e.g. the editor's current shot).
    static func extractText(from image: NSImage) {
        let popup = ResultPopup.showSpinner(title: "Extract Text")
        OCR.recognise(in: image) { text in
            DispatchQueue.main.async {
                guard let text = text, !text.isEmpty else {
                    popup.fail("No text recognised in this image.")
                    return
                }
                copyToClipboardAndHistory(text)
                popup.replace(sections: [.init(title: "Extracted text (copied to clipboard)", text: text)])
            }
        }
    }

    /// OCR + translate an image already in hand.
    static func translate(image: NSImage) {
        let popup = ResultPopup.showSpinner(title: "Translate Screenshot")
        OCR.recognise(in: image) { text in
            DispatchQueue.main.async {
                guard let text = text, !text.isEmpty else {
                    popup.fail("No text recognised in this image.")
                    return
                }
                translate(text, into: popup)
            }
        }
    }

    // MARK: - Paste English reply (⌘⇧V)

    /// Copy the message you're replying to (⌘C), put the cursor in the input
    /// box, press ⌘⇧V: an English reply is generated from the clipboard text
    /// and pasted straight into the field — no window.
    static func pasteEnglishReply() {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { NSSound.beep(); return }
        let hud = GeneratingHUD.show(text: "Drafting English reply…")
        let prompt = """
        You are replying to the message below. Write a natural, ready-to-send \
        reply in English, appropriate to the message's content and tone. \
        Output ONLY the reply text — no explanations, no quotes of the original.

        --- MESSAGE ---
        \(text)
        """
        LLMClient.complete(prompt: prompt) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let reply):
                    hud.dismiss()
                    ClipboardMonitor.shared.suppressNext()
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(reply.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
                    // Paste into whatever field currently has focus.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { sendPasteKeystroke() }
                case .failure(let error):
                    hud.dismiss(failed: true)
                    NSSound.beep()
                    NSLog("ShotClip: paste-reply failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Translate captured region (⌘⇧T)

    /// Select a region → OCR → LLM translation. Translation is auto-copied.
    static func translateRegion() {
        captureTempRegion { image in
            guard let image = image else { return }
            translate(image: image)
        }
    }

    // MARK: - Translate current selection (⌘⇧L)

    /// Copies the frontmost app's selection via a synthetic ⌘C (needs the
    /// Accessibility permission ShotClip already requests), then translates it.
    static func translateSelection() {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        ClipboardMonitor.shared.suppressNext()
        // Small delay so the user's still-held hotkey modifiers don't merge into ⌘C.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { sendCopyKeystroke() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard pb.changeCount != before,
                  let text = pb.string(forType: .string)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                ResultPopup.show(title: "Translate Selection", sections: [
                    .init(title: "Nothing selected",
                          text: "Select some text first, then press ⌘⇧L. (If this keeps happening, check the Accessibility permission in Permissions & Setup…)"),
                ])
                return
            }
            let popup = ResultPopup.showSpinner(title: "Translate Selection")
            translate(text, into: popup)
        }
    }

    // MARK: - Helpers

    private static func translate(_ text: String, into popup: ResultPopup) {
        LLMClient.complete(prompt: LLMClient.translationPrompt(for: text)) { result in
            switch result {
            case .success(let translation):
                copyToClipboardAndHistory(translation)
                popup.replace(sections: [
                    .init(title: "Translation (copied to clipboard)", text: translation),
                    .init(title: "Original", text: text),
                ])
            case .failure(let error):
                popup.fail(error.localizedDescription)
            }
        }
    }

    private static func copyToClipboardAndHistory(_ text: String) {
        ClipboardMonitor.shared.suppressNext()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        Store.shared.addClipText(text)
    }

    /// Interactive region capture into a throwaway file (not the shot store).
    private static func captureTempRegion(completion: @escaping (NSImage?) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotclip-ocr-\(UUID().uuidString).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-i", "-o", url.path]
        proc.terminationHandler = { _ in
            DispatchQueue.main.async {
                let image = NSImage(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                completion(image)
            }
        }
        do { try proc.run() } catch {
            NSLog("ShotClip: screencapture failed: \(error)")
            completion(nil)
        }
    }

    private static func sendPasteKeystroke() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func sendCopyKeystroke() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
