import AppKit
import CryptoKit
import Security

/// Silent self-update from GitHub Releases. Checks shortly after launch and every 6 hours,
/// downloads WolfClip-macOS.zip, verifies its SHA-256 and code signature, swaps the app bundle
/// in place and relaunches while the history panel is closed.
@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle, checking, upToDate
        case downloading(String)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    /// Restarting is allowed only when nothing is on screen (the panel is closed).
    var canRestartNow: () -> Bool = { true }
    /// Called right before quitting for the restart (history is saved on quit as usual).
    var willRestart: () -> Void = {}

    private static let assetName = "WolfClip-macOS.zip"
    private static let checkInterval: TimeInterval = 6 * 3600
    private var timer: Timer?
    private var busy = false

    nonisolated init() {}

    private var feed: URL? {
        #if WOLFCLIP_DEBUG
        // Test builds update only from a local feed (WOLFCLIP_UPDATE_FEED), never from GitHub.
        return ProcessInfo.processInfo.environment["WOLFCLIP_UPDATE_FEED"].flatMap(URL.init(string:))
        #else
        return URL(string: "https://api.github.com/repos/RakushkaTOP/wolfclip/releases/latest")
        #endif
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        timer?.invalidate()
        guard Prefs.shared.autoUpdate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfEnabled() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfEnabled() }
        }
    }

    private func checkIfEnabled() {
        guard Prefs.shared.autoUpdate else { return }
        Task { await check(manual: false) }
    }

    /// Manual checks restart right away; automatic ones wait until the panel is closed.
    func check(manual: Bool) async {
        guard !busy, let feed else { return }
        busy = true
        defer { busy = false }
        status = .checking
        do {
            let release = try await latestRelease(feed)
            let version = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
            guard Self.isNewer(version, than: Self.currentVersion) else {
                status = .upToDate
                return
            }
            guard let target = installTarget() else {
                throw UpdateError(tr("Нет прав на запись в папку приложения", "No write access to the app folder"))
            }
            status = .downloading(version)
            let app = try await download(release, version: version, near: target)
            status = .installing(version)
            while !manual && !canRestartNow() {
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
            _ = try FileManager.default.replaceItemAt(target, withItemAt: app)
            NSLog("WolfClip: updated to \(version), relaunching")
            relaunch(target)
        } catch {
            NSLog("WolfClip: update failed: \(error)")
            status = .failed((error as? UpdateError)?.message ?? error.localizedDescription)
        }
    }

    // MARK: Steps

    private struct Release {
        let tag: String
        let assetURL: URL
        let sha256: String
    }

    private struct UpdateError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func latestRelease(_ feed: URL) async throws -> Release {
        var request = URLRequest(url: feed, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WolfClip/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == Self.assetName }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link)
        else { throw UpdateError(tr("Не удалось прочитать релиз на GitHub", "Couldn’t read the GitHub release")) }
        // GitHub publishes a digest for every asset; without it the download can't be verified.
        guard let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") else {
            throw UpdateError(tr("У релиза нет контрольной суммы", "The release has no checksum"))
        }
        return Release(tag: tag, assetURL: url, sha256: String(digest.dropFirst(7)).lowercased())
    }

    /// Downloads, checks and unpacks the release next to the installed app (same volume, so the swap is atomic).
    private func download(_ release: Release, version: String, near target: URL) async throws -> URL {
        let fm = FileManager.default
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        let (file, _) = try await URLSession.shared.download(from: release.assetURL)
        let zip = work.appendingPathComponent(Self.assetName)
        try fm.moveItem(at: file, to: zip)

        let hash = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard hash == release.sha256 else {
            throw UpdateError(tr("Контрольная сумма не совпала", "Checksum mismatch"))
        }

        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let app = work.appendingPathComponent("WolfClip.app")
        let info = Bundle(url: app)
        guard info?.bundleIdentifier == Bundle.main.bundleIdentifier,
              info?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
        else { throw UpdateError(tr("В архиве не та версия WolfClip", "The archive has the wrong WolfClip version")) }
        try verifySignature(app)
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Same designated requirement the app is signed with: identifier "<bundle id>".
    private func verifySignature(_ app: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let id = Bundle.main.bundleIdentifier ?? ""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("identifier \"\(id)\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
        else { throw UpdateError(tr("Подпись новой версии не прошла проверку", "The new version’s signature is invalid")) }
    }

    /// The running bundle, if it can be replaced (not translocated, folder writable).
    private func installTarget() -> URL? {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app", !target.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
        else { return nil }
        return target
    }

    /// Waits for this process to quit, then opens the new version. WOLFCLIP_* settings
    /// (e.g. a test history in WOLFCLIP_DATA_DIR) carry over to the new process.
    private func relaunch(_ app: URL) {
        willRestart()
        let pid = ProcessInfo.processInfo.processIdentifier
        let env = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("WOLFCLIP_") }
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$@\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh"] + env.flatMap { ["--env", "\($0.key)=\($0.value)"] } + [app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError(tr("Не удалось распаковать обновление", "Couldn’t unpack the update"))
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
