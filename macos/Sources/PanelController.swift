import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

enum ClipFilter: String, CaseIterable, Identifiable {
    case all, text, links, images, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Все", "All")
        case .text: return tr("Текст", "Text")
        case .links: return tr("Ссылки", "Links")
        case .images: return tr("Картинки", "Images")
        case .files: return tr("Файлы", "Files")
        }
    }

    func accepts(_ kind: ClipKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text || kind == .color
        case .links: return kind == .link
        case .images: return kind == .image
        case .files: return kind == .files
        }
    }
}

struct ScrollRequest: Equatable {
    enum Target: Equatable { case top, item(UUID) }
    let target: Target
    let animated: Bool
    let token = UUID()
}

/// UI state of the history panel: search, filter, selection.
final class PanelModel: ObservableObject {
    @Published var query = ""
    @Published var filter: ClipFilter = .all
    @Published var selectedID: UUID?
    @Published private(set) var pinned: [ClipItem] = []
    @Published private(set) var recent: [ClipItem] = []
    @Published var scrollRequest: ScrollRequest?
    @Published var axTrusted = true

    private var lastQuery = ""
    private var lastFilter = ClipFilter.all
    private var bag = Set<AnyCancellable>()

    var flat: [ClipItem] { pinned + recent }
    var selectedItem: ClipItem? { flat.first { $0.id == selectedID } }

    init(store: HistoryStore) {
        Publishers.CombineLatest3(store.$items, $query, $filter)
            .sink { [weak self] items, query, filter in self?.recompute(items, query, filter) }
            .store(in: &bag)
    }

    private func recompute(_ items: [ClipItem], _ query: String, _ filter: ClipFilter) {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matched = items.filter { filter.accepts($0.kind) && (q.isEmpty || $0.searchText.localizedStandardContains(q)) }
        pinned = matched.filter(\.pinned)
        recent = matched.filter { !$0.pinned }

        let criteriaChanged = query != lastQuery || filter != lastFilter
        lastQuery = query
        lastFilter = filter
        let all = pinned + recent
        if criteriaChanged || !all.contains(where: { $0.id == selectedID }) {
            selectedID = all.first?.id
            scrollRequest = ScrollRequest(target: .top, animated: false)
        }
    }

    func prepareForShow(axTrusted: Bool) {
        self.axTrusted = axTrusted
        query = ""
        filter = .all
        selectedID = flat.first?.id
        scrollRequest = ScrollRequest(target: .top, animated: false)
    }

    func move(_ delta: Int) {
        let all = flat
        guard !all.isEmpty else { return }
        let current = all.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), all.count - 1)
        selectedID = all[next].id
        scrollRequest = ScrollRequest(target: next == 0 ? .top : .item(all[next].id), animated: true)
    }

    func scrollToSelection() {
        guard let id = selectedID else { return }
        // The first row sits under a section title, so show the very top instead.
        let target: ScrollRequest.Target = flat.first?.id == id ? .top : .item(id)
        scrollRequest = ScrollRequest(target: target, animated: true)
    }

    func cycleFilter(back: Bool) {
        let all = ClipFilter.allCases
        let i = all.firstIndex(of: filter) ?? 0
        filter = all[(i + (back ? all.count - 1 : 1)) % all.count]
    }

    func neighbor(of id: UUID) -> UUID? {
        let all = flat
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < all.count { return all[i + 1].id }
        return i > 0 ? all[i - 1].id : nil
    }
}

struct PanelActions {
    var choose: (ClipItem, Bool) -> Void
    var togglePin: (ClipItem) -> Void
    var delete: (ClipItem) -> Void
    var requestAccess: () -> Void
    var openSettings: () -> Void
    var clearHistory: () -> Void
    var togglePause: () -> Void
    var quit: () -> Void
}

/// Borderless panel that takes keyboard focus without activating WolfClip,
/// so the app you were typing in stays frontmost and receives the paste.
final class ClipPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 400, height: 540)
    static let cornerRadius: CGFloat = 16

    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    let model: PanelModel
    var openSettings: () -> Void = {}
    var clearHistory: () -> Void = {}

    private var panel: ClipPanel!
    private weak var searchField: NSTextField?
    private var accessTimer: Timer?
    private var askedForAccess = false

    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                    kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.model = PanelModel(store: store)
        super.init()
        buildPanel()
    }

    var isVisible: Bool { panel.isVisible }

    private func buildPanel() {
        let panel = ClipPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        let actions = PanelActions(
            choose: { [weak self] item, plain in self?.choose(item, plain: plain) },
            togglePin: { [weak self] item in self?.togglePin(item) },
            delete: { [weak self] item in self?.delete(item) },
            requestAccess: { [weak self] in self?.requestAccess() },
            openSettings: { [weak self] in
                self?.close()
                DispatchQueue.main.async { self?.openSettings() }
            },
            clearHistory: { [weak self] in
                self?.close()
                DispatchQueue.main.async { self?.clearHistory() }
            },
            togglePause: { Prefs.shared.paused.toggle() },
            quit: { NSApp.terminate(nil) })

        let root = HistoryView(store: store, model: model, actions: actions,
                               onSearchField: { [weak self] field in self?.searchField = field })

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.mask(radius: Self.cornerRadius)

        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)

        panel.contentView = background
        self.panel = panel
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Show / hide

    func toggle() {
        panel.isVisible ? close() : show()
    }

    func show() {
        model.prepareForShow(axTrusted: displayedTrust)
        panel.setFrameOrigin(origin())
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        if let field = searchField { panel.makeFirstResponder(field) }
        accessTimer?.invalidate()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = self.displayedTrust
            if self.model.axTrusted != trusted { self.model.axTrusted = trusted }
        }
    }

    /// Accessibility state as the panel shows it (the access banner); pasting still checks the real one.
    private var displayedTrust: Bool {
        #if WOLFCLIP_DEBUG
        // Demo mode for README screenshots: WOLFCLIP_DEMO=1 hides the "allow auto-paste" banner.
        if ProcessInfo.processInfo.environment["WOLFCLIP_DEMO"] == "1" { return true }
        #endif
        return Accessibility.trusted
    }

    func close() {
        accessTimer?.invalidate()
        accessTimer = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func origin() -> NSPoint {
        let size = Self.size
        let mouse = NSEvent.mouseLocation
        let mouseRect = NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
        var anchor: NSRect?
        switch Prefs.shared.position {
        case .caret: anchor = Accessibility.caretRect() ?? mouseRect
        case .mouse: anchor = mouseRect
        case .center: anchor = nil
        }

        let probe = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse
        let screen = NSScreen.screens.first { NSPointInRect(probe, $0.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame

        var origin: NSPoint
        if let a = anchor {
            origin = NSPoint(x: a.minX - 14, y: a.minY - size.height - 8)
            if origin.y < area.minY + 8 { origin.y = a.maxY + 8 }
        } else {
            origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + area.height * 0.08)
        }
        origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
        origin.y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        return origin
    }

    // MARK: Actions

    private func choose(_ item: ClipItem, plain: Bool) {
        Paster.write(item, plain: plain, imagesDir: store.imagesDir)
        monitor.skipCurrent()
        store.promote(id: item.id)
        close()
        guard Prefs.shared.autoPaste else { return }
        if Accessibility.trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { Paster.sendPaste() }
        } else if !askedForAccess {
            askedForAccess = true
            Accessibility.requestFresh()
        }
    }

    private func copyOnly(_ item: ClipItem) {
        Paster.write(item, plain: false, imagesDir: store.imagesDir)
        monitor.skipCurrent()
        store.promote(id: item.id)
        close()
    }

    private func togglePin(_ item: ClipItem) {
        store.togglePin(id: item.id)
        model.selectedID = item.id
        model.scrollToSelection()
    }

    private func delete(_ item: ClipItem) {
        if model.selectedID == item.id { model.selectedID = model.neighbor(of: item.id) }
        store.remove(id: item.id)
    }

    private func requestAccess() {
        close()
        askedForAccess = true
        Accessibility.requestFresh()
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)

        switch code {
        case kVK_Escape:
            if !model.query.isEmpty { model.query = "" } else { close() }
            return true
        case kVK_DownArrow:
            model.move(1); return true
        case kVK_UpArrow:
            model.move(-1); return true
        case kVK_PageDown:
            model.move(5); return true
        case kVK_PageUp:
            model.move(-5); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem { choose(item, plain: mods.contains(.shift)) }
            return true
        case kVK_Tab:
            model.cycleFilter(back: mods.contains(.shift)); return true
        default:
            break
        }

        guard mods.contains(.command) else { return false }

        if let n = Self.digitKeys.firstIndex(of: code) {
            let all = model.flat
            if n < all.count { choose(all[n], plain: mods.contains(.shift)) }
            return true
        }

        switch code {
        case kVK_Delete, kVK_ForwardDelete:
            if let item = model.selectedItem { delete(item) }
            return true
        case kVK_ANSI_P:
            if let item = model.selectedItem { togglePin(item) }
            return true
        case kVK_ANSI_Comma:
            close()
            DispatchQueue.main.async { self.openSettings() }
            return true
        case kVK_ANSI_W:
            close(); return true
        case kVK_ANSI_C:
            if let editor = panel.firstResponder as? NSTextView, editor.selectedRange().length > 0 {
                editor.copy(nil)
            } else if let item = model.selectedItem {
                copyOnly(item)
            }
            return true
        case kVK_ANSI_A:
            return forward(#selector(NSText.selectAll(_:)))
        case kVK_ANSI_X:
            return forward(#selector(NSText.cut(_:)))
        case kVK_ANSI_V:
            return forward(#selector(NSText.paste(_:)))
        default:
            return false
        }
    }

    private func forward(_ action: Selector) -> Bool {
        panel.firstResponder?.tryToPerform(action, with: nil)
        return true
    }

    #if WOLFCLIP_DEBUG
    /// Test hook: wolfclip://debug?key=125&type=abc&mods=cmd,shift feeds real key events through the panel.
    func debug(_ url: URL) {
        if !panel.isVisible { show() }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var flags: NSEvent.ModifierFlags = []
        for item in query where item.name == "mods" {
            for m in (item.value ?? "").split(separator: ",") {
                switch m {
                case "cmd": flags.insert(.command)
                case "shift": flags.insert(.shift)
                default: break
                }
            }
        }
        for item in query {
            switch item.name {
            case "key":
                for code in (item.value ?? "").split(separator: ",") { sendKey(UInt16(code) ?? 0, "", flags) }
            case "type":
                for ch in item.value ?? "" { sendKey(0, String(ch), []) }
            default:
                break
            }
        }
    }

    private func sendKey(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: chars, charactersIgnoringModifiers: chars,
                                           isARepeat: false, keyCode: code) else { return }
        panel.sendEvent(event)
    }
    #endif
}
