import AppKit
import CryptoKit
import ImageIO

enum ClipKind: String, Codable {
    case text, link, color, image, files
}

struct ClipItem: Codable, Identifiable {
    var id = UUID()
    var kind: ClipKind
    var text: String?
    var rtf: Data?
    var html: Data?
    var imageFile: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var files: [String]?
    var chars: Int?
    var lines: Int?
    var fingerprint: String
    var appBundleID: String?
    var appName: String?
    var date = Date()
    var pinned = false

    var fileURLs: [URL] { (files ?? []).map { URL(fileURLWithPath: $0) } }

    var searchText: String {
        let app = appName ?? ""
        switch kind {
        case .files:
            return fileURLs.map(\.lastPathComponent).joined(separator: " ") + " " + app
        case .image:
            return "картинка изображение скриншот image picture screenshot " + app
        default:
            return String((text ?? "").prefix(20_000)) + " " + app
        }
    }
}

enum Clip {
    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func classify(_ s: String) -> ClipKind {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 9, t.range(of: #"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil {
            return .color
        }
        if t.count < 4096, !t.contains(where: \.isWhitespace),
           let url = URL(string: t), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return .link
        }
        return .text
    }

    static func color(fromHex hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let alpha = s.count == 8
        let r = CGFloat((v >> (alpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (alpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (alpha ? 8 : 0)) & 0xFF) / 255
        let a = alpha ? CGFloat(v & 0xFF) / 255 : 1
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// First lines of the text with blank edges and common indentation removed.
    static func preview(_ s: String) -> String {
        let head = String(s.prefix(1200)).replacingOccurrences(of: "\r\n", with: "\n")
        var lines = head.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\t", with: "    ") }
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let indents = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }
        if let common = indents.min(), common > 0 {
            lines = lines.map { String($0.dropFirst(min(common, $0.prefix(while: { $0 == " " }).count))) }
        }
        return lines.prefix(8).joined(separator: "\n")
    }

    static func looksLikeCode(_ s: String) -> Bool {
        let head = s.prefix(800)
        guard head.contains("\n") else { return false }
        let markers = ["{", "}", ";", "=>", "->", "</", "def ", "func ", "const ", "import ", "return ", "#include", "$ ", "()"]
        let hits = markers.filter { head.contains($0) }.count
        let indented = head.split(separator: "\n").filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        return hits >= 3 || (hits >= 1 && indented >= 1)
    }

    private static let dateLocale = Locale(identifier: L10n.isRussian ? "ru_RU" : "en_US")

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = dateLocale
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = dateLocale
        f.dateFormat = L10n.isRussian ? "d MMM, HH:mm" : "MMM d, HH:mm"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = dateLocale
        f.dateFormat = L10n.isRussian ? "d MMM yyyy" : "MMM d, yyyy"
        return f
    }()

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        let cal = Calendar.current
        if s < 45 { return tr("только что", "just now") }
        if s < 3600 {
            let m = max(1, Int(s / 60))
            return tr("\(m) мин назад", "\(m) min ago")
        }
        if cal.isDateInToday(date) {
            let h = Int(s / 3600)
            return tr("\(h) ч назад", "\(h) h ago")
        }
        if cal.isDateInYesterday(date) { return tr("вчера, ", "yesterday, ") + timeFormatter.string(from: date) }
        if cal.isDate(date, equalTo: now, toGranularity: .year) { return dayFormatter.string(from: date) }
        return yearFormatter.string(from: date)
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        let word: String
        if m10 == 1 && m100 != 11 {
            word = one
        } else if (2...4).contains(m10) && !(12...14).contains(m100) {
            word = few
        } else {
            word = many
        }
        return "\(n) \(word)"
    }

    /// "5 записей" in Russian (via `plural`), "5 items" in English.
    static func count(_ n: Int, ru: (String, String, String), en: (String, String)) -> String {
        L10n.isRussian ? plural(n, ru.0, ru.1, ru.2) : "\(n) \(n == 1 ? en.0 : en.1)"
    }

    static func detail(_ item: ClipItem) -> String? {
        switch item.kind {
        case .text:
            if let l = item.lines, l > 8 { return count(l, ru: ("строка", "строки", "строк"), en: ("line", "lines")) }
            if let c = item.chars, c > 300 { return tr("\(c.formatted()) симв.", "\(c.formatted()) chars") }
            return nil
        case .image:
            guard let w = item.pixelWidth, let h = item.pixelHeight else { return nil }
            return "\(w)×\(h)"
        default:
            return nil
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func fit(_ w: CGFloat, _ h: CGFloat, maxW: CGFloat, maxH: CGFloat) -> CGSize {
        guard w > 0, h > 0 else { return CGSize(width: maxH, height: maxH) }
        let scale = min(1, maxW / w, maxH / h)
        return CGSize(width: max(12, (w * scale).rounded()), height: max(12, (h * scale).rounded()))
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let id = bundleID else { return nil }
        if let hit = cache[id] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache[id] = icon
        return icon
    }
}

enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let hit = cache[url.path] { return hit }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        cache[url.path] = icon
        return icon
    }
}

enum Thumbs {
    static let cache = NSCache<NSString, NSImage>()

    static func image(for item: ClipItem, in dir: URL) -> NSImage? {
        guard let name = item.imageFile else { return nil }
        if let hit = cache.object(forKey: name as NSString) { return hit }
        let url = dir.appendingPathComponent(name)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}
