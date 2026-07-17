import Foundation
import AppKit

enum ClipKind {
    case text(String)
    case image(URL)
}

enum CardType {
    case screenshot
    case image
    case link
    case text

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .image: return "Image"
        case .link: return "Link"
        case .text: return "Text"
        }
    }

    var headerColor: NSColor {
        switch self {
        case .screenshot: return NSColor(red: 0.20, green: 0.70, blue: 0.62, alpha: 1)
        case .image:      return NSColor(red: 0.30, green: 0.60, blue: 0.98, alpha: 1)
        case .link:       return NSColor(red: 0.55, green: 0.42, blue: 0.92, alpha: 1)
        case .text:       return NSColor(red: 0.95, green: 0.70, blue: 0.25, alpha: 1)
        }
    }
}

enum TimelineItem {
    case shot(ShotItem)
    case clip(ClipItem)

    var createdAt: Date {
        switch self {
        case .shot(let s): return s.createdAt
        case .clip(let c): return c.createdAt
        }
    }

    var type: CardType {
        switch self {
        case .shot: return .screenshot
        case .clip(let c):
            switch c.kind {
            case .image: return .image
            case .text(let s):
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("http://") || t.hasPrefix("https://") { return .link }
                return .text
            }
        }
    }
}

final class ShotItem: Identifiable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let thumbnail: NSImage?

    init(url: URL, createdAt: Date) {
        self.url = url
        self.createdAt = createdAt
        self.thumbnail = NSImage(contentsOf: url)
    }
}

final class ClipItem: Identifiable {
    let id = UUID()
    let kind: ClipKind
    let createdAt: Date

    init(kind: ClipKind, createdAt: Date) {
        self.kind = kind
        self.createdAt = createdAt
    }

    var preview: String {
        switch kind {
        case .text(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            return String(oneLine.prefix(60))
        case .image:
            return "🖼 Image"
        }
    }
}

final class Store {
    static let shared = Store()

    private(set) var shots: [ShotItem] = []
    private(set) var clips: [ClipItem] = []

    let baseDir: URL
    private let ttl: TimeInterval = 30 * 24 * 60 * 60
    private let maxItems = 40

    var onChange: (() -> Void)?

    func timeline() -> [TimelineItem] {
        let items = shots.map { TimelineItem.shot($0) } + clips.map { TimelineItem.clip($0) }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }

    private var clipsFile: URL { baseDir.appendingPathComponent("clips.json") }

    private init() {
        let tmp = FileManager.default.temporaryDirectory
        baseDir = tmp.appendingPathComponent("ShotClip", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        loadExistingShots()
        loadClips()
    }

    private struct StoredClip: Codable {
        var kind: String
        var text: String?
        var imagePath: String?
        var createdAt: Date
    }

    private func loadClips() {
        guard let data = try? Data(contentsOf: clipsFile),
              let stored = try? JSONDecoder().decode([StoredClip].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-ttl)
        for s in stored where s.createdAt >= cutoff {
            if s.kind == "text", let t = s.text {
                clips.append(ClipItem(kind: .text(t), createdAt: s.createdAt))
            } else if s.kind == "image", let p = s.imagePath,
                      FileManager.default.fileExists(atPath: p) {
                clips.append(ClipItem(kind: .image(URL(fileURLWithPath: p)), createdAt: s.createdAt))
            }
        }
        clips.sort { $0.createdAt > $1.createdAt }
    }

    private func saveClips() {
        let stored: [StoredClip] = clips.map { item in
            switch item.kind {
            case .text(let t):
                return StoredClip(kind: "text", text: t, imagePath: nil, createdAt: item.createdAt)
            case .image(let u):
                return StoredClip(kind: "image", text: nil, imagePath: u.path, createdAt: item.createdAt)
            }
        }
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: clipsFile)
        }
    }

    private func loadExistingShots() {
        rescanShots()
    }

    func rescanShots() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let known = Set(shots.map { $0.url.lastPathComponent })
        for url in entries where url.pathExtension.lowercased() == "png"
            && url.lastPathComponent.hasPrefix("shot-")
            && !known.contains(url.lastPathComponent) {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            shots.append(ShotItem(url: url, createdAt: created))
        }
        shots.sort { $0.createdAt > $1.createdAt }
        purge()
    }

    func addShot(_ url: URL) {
        let item = ShotItem(url: url, createdAt: Date())
        shots.insert(item, at: 0)
        trimAndNotify()
    }

    func addClipText(_ text: String) {
        if case .text(let last)? = clips.first?.kind, last == text { return }
        clips.insert(ClipItem(kind: .text(text), createdAt: Date()), at: 0)
        trimAndNotify()
    }

    func addClipImage(_ image: NSImage) {
        let url = baseDir.appendingPathComponent("clip-\(UUID().uuidString).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        clips.insert(ClipItem(kind: .image(url), createdAt: Date()), at: 0)
        trimAndNotify()
    }

    private func trimAndNotify() {
        purge()
        if shots.count > maxItems {
            for old in shots[maxItems...] { try? FileManager.default.removeItem(at: old.url) }
            shots = Array(shots.prefix(maxItems))
        }
        if clips.count > maxItems {
            for old in clips[maxItems...] {
                if case .image(let u) = old.kind { try? FileManager.default.removeItem(at: u) }
            }
            clips = Array(clips.prefix(maxItems))
        }
        saveClips()
        onChange?()
    }

    func purge() {
        let cutoff = Date().addingTimeInterval(-ttl)
        for s in shots where s.createdAt < cutoff {
            try? FileManager.default.removeItem(at: s.url)
        }
        shots.removeAll { $0.createdAt < cutoff }
        for c in clips where c.createdAt < cutoff {
            if case .image(let u) = c.kind { try? FileManager.default.removeItem(at: u) }
        }
        clips.removeAll { $0.createdAt < cutoff }
    }
}
