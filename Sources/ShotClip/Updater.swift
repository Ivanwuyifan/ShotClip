import AppKit

enum Updater {
    static let repo = "Ivanwuyifan/ShotClip"
    private static let apiURL = "https://api.github.com/repos/\(repo)/releases/latest"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // 静默检查，有新版才弹提示。manual=true 时即使已是最新也提示。
    static func checkInBackground(manual: Bool = false) {
        guard let url = URL(string: apiURL) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if manual { DispatchQueue.main.async { showError("检查更新失败，请稍后再试。") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isNewer(latest, than: currentVersion) else {
                if manual {
                    DispatchQueue.main.async {
                        let a = NSAlert()
                        a.messageText = "已是最新版本"
                        a.informativeText = "ShotClip \(currentVersion) 已经是最新的了。"
                        NSApp.activate(ignoringOtherApps: true)
                        a.runModal()
                    }
                }
                return
            }

            let assets = (json["assets"] as? [[String: Any]]) ?? []
            let zipURL = assets.compactMap { $0["browser_download_url"] as? String }
                .first { $0.hasSuffix(".zip") }
            let notes = (json["body"] as? String) ?? ""

            DispatchQueue.main.async {
                promptUpdate(version: latest, notes: notes, zipURLString: zipURL)
            }
        }.resume()
    }

    // 语义版本比较：latest > current 返回 true
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").map { Int($0) ?? 0 }
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }

    private static func promptUpdate(version: String, notes: String, zipURLString: String?) {
        let alert = NSAlert()
        alert.messageText = "ShotClip \(version) 可用"
        alert.informativeText = "当前版本 \(currentVersion)。\n\n\(notes.prefix(300))"
        alert.addButton(withTitle: "更新并重启")
        alert.addButton(withTitle: "打开发布页")
        alert.addButton(withTitle: "以后再说")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let z = zipURLString, let url = URL(string: z) {
                downloadAndInstall(url)
            } else {
                openReleasePage()
            }
        case .alertSecondButtonReturn:
            openReleasePage()
        default:
            break
        }
    }

    private static func openReleasePage() {
        if let url = URL(string: "https://github.com/\(repo)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func downloadAndInstall(_ url: URL) {
        let task = URLSession.shared.downloadTask(with: url) { tmp, _, err in
            guard let tmp = tmp, err == nil else {
                DispatchQueue.main.async { showError("下载失败：\(err?.localizedDescription ?? "未知错误")") }
                return
            }
            do {
                try install(zipAt: tmp)
            } catch {
                DispatchQueue.main.async { showError("安装失败：\(error.localizedDescription)") }
            }
        }
        task.resume()
    }

    private static func install(zipAt tmpZip: URL) throws {
        let fm = FileManager.default
        let appPath = Bundle.main.bundlePath                       // /path/ShotClip.app
        let appURL = URL(fileURLWithPath: appPath)
        let parent = appURL.deletingLastPathComponent()
        let work = fm.temporaryDirectory.appendingPathComponent("ShotClipUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // 解压
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", tmpZip.path, work.path]
        try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.unzipFailed }

        // 找到解压出来的 ShotClip.app
        guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.appNotFound }

        // 用外部脚本替换并重启（App 不能替换正在运行的自己）
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(appPath)"
        ditto "\(newApp.path)" "\(appPath)"
        rm -rf "\(work.path)"
        open "\(appPath)"
        """
        let scriptURL = work.appendingPathComponent("apply.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let applier = Process()
        applier.executableURL = URL(fileURLWithPath: "/bin/bash")
        applier.arguments = [scriptURL.path]
        try applier.run()

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        _ = parent
    }

    private static func showError(_ msg: String) {
        let a = NSAlert()
        a.messageText = "更新出错"
        a.informativeText = msg + "\n\n可到发布页手动下载。"
        a.addButton(withTitle: "打开发布页")
        a.addButton(withTitle: "好")
        if a.runModal() == .alertFirstButtonReturn { openReleasePage() }
    }

    enum UpdateError: LocalizedError {
        case unzipFailed, appNotFound
        var errorDescription: String? {
            switch self {
            case .unzipFailed: return "解压失败"
            case .appNotFound: return "更新包里找不到 ShotClip.app"
            }
        }
    }
}
