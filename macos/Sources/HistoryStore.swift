import AppKit
import Combine

/// Clipboard history kept in memory and mirrored to ~/Library/Application Support/WolfClip
/// (or to the absolute path in WOLFCLIP_DATA_DIR, e.g. a throwaway history for screenshots).
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let baseDir: URL
    let imagesDir: URL
    private var historyURL: URL { baseDir.appendingPathComponent("history.json") }
    private let io = DispatchQueue(label: "one.wolfteam.wolfclip.io", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init() {
        if let custom = ProcessInfo.processInfo.environment["WOLFCLIP_DATA_DIR"], custom.hasPrefix("/") {
            baseDir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            baseDir = support.appendingPathComponent("WolfClip", isDirectory: true)
        }
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        do {
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            NSLog("WolfClip: history.json is unreadable, moving it aside: \(error)")
            let backup = baseDir.appendingPathComponent("history-broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: historyURL, to: backup)
        }
        removeOrphanImages()
    }

    // MARK: Mutations

    func add(_ item: ClipItem) {
        mutate { $0.insert(item, at: 0) }
        trim()
    }

    /// Moves an existing entry with the same content to the top. Returns false if there is none.
    @discardableResult
    func promote(fingerprint: String, bundleID: String?, appName: String?) -> Bool {
        guard items.contains(where: { $0.fingerprint == fingerprint }) else { return false }
        mutate { list in
            guard let i = list.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
            var item = list.remove(at: i)
            item.date = Date()
            item.appBundleID = bundleID
            item.appName = appName
            list.insert(item, at: 0)
        }
        return true
    }

    func promote(id: UUID) {
        mutate { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            var item = list.remove(at: i)
            item.date = Date()
            list.insert(item, at: 0)
        }
    }

    func togglePin(id: UUID) {
        mutate { list in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].pinned.toggle() }
        }
        trim()
    }

    func remove(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        mutate { $0.removeAll { $0.id == id } }
        deleteFiles(of: item)
    }

    /// Removes everything except pinned entries.
    func clear() {
        let gone = items.filter { !$0.pinned }
        mutate { $0.removeAll { !$0.pinned } }
        gone.forEach(deleteFiles)
    }

    func trim() {
        let limit = Prefs.shared.historyLimit
        var kept: [ClipItem] = []
        var gone: [ClipItem] = []
        var unpinned = 0
        for item in items {
            if item.pinned { kept.append(item); continue }
            unpinned += 1
            if unpinned > limit { gone.append(item) } else { kept.append(item) }
        }
        guard !gone.isEmpty else { return }
        mutate { $0 = kept }
        gone.forEach(deleteFiles)
    }

    private func mutate(_ change: (inout [ClipItem]) -> Void) {
        var list = items
        change(&list)
        items = list
        scheduleSave()
    }

    // MARK: Disk

    func saveNow() {
        pendingSave?.cancel()
        let snapshot = items, url = historyURL
        io.sync { Self.write(snapshot, to: url) }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = items, url = historyURL
        let work = DispatchWorkItem { Self.write(snapshot, to: url) }
        pendingSave = work
        io.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func write(_ items: [ClipItem], to url: URL) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("WolfClip: failed to save history: \(error)")
        }
    }

    private func deleteFiles(of item: ClipItem) {
        guard let name = item.imageFile else { return }
        Thumbs.cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
    }

    private func removeOrphanImages() {
        let used = Set(items.compactMap(\.imageFile))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
        for name in files where !used.contains(name) {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
        }
    }

    func diskUsage() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: historyURL.path), let size = attrs[.size] as? NSNumber {
            total += size.int64Value
        }
        for name in (try? fm.contentsOfDirectory(atPath: imagesDir.path)) ?? [] {
            let path = imagesDir.appendingPathComponent(name).path
            if let attrs = try? fm.attributesOfItem(atPath: path), let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }
}
