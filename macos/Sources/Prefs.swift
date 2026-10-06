import AppKit
import Carbon.HIToolbox

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case shiftCmdV, optCmdV, ctrlCmdV, ctrlOptV, ctrlShiftV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shiftCmdV: return "⇧⌘V"
        case .optCmdV: return "⌥⌘V"
        case .ctrlCmdV: return "⌃⌘V"
        case .ctrlOptV: return "⌃⌥V"
        case .ctrlShiftV: return "⌃⇧V"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_ANSI_V) }

    var carbonModifiers: UInt32 {
        switch self {
        case .shiftCmdV: return UInt32(shiftKey | cmdKey)
        case .optCmdV: return UInt32(optionKey | cmdKey)
        case .ctrlCmdV: return UInt32(controlKey | cmdKey)
        case .ctrlOptV: return UInt32(controlKey | optionKey)
        case .ctrlShiftV: return UInt32(controlKey | shiftKey)
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        switch self {
        case .shiftCmdV: return [.shift, .command]
        case .optCmdV: return [.option, .command]
        case .ctrlCmdV: return [.control, .command]
        case .ctrlOptV: return [.control, .option]
        case .ctrlShiftV: return [.control, .shift]
        }
    }
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case caret, mouse, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caret: return tr("У текстового курсора", "At text cursor")
        case .mouse: return tr("У указателя мыши", "At mouse pointer")
        case .center: return tr("По центру экрана", "Center of screen")
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return tr("Тёмная", "Dark")
        case .light: return tr("Светлая", "Light")
        case .system: return tr("Как в системе", "System")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .system: return nil
        }
    }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var hotKey: HotKeyPreset { didSet { d.set(hotKey.rawValue, forKey: "hotKey") } }
    @Published var theme: Theme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var position: PanelPosition { didSet { d.set(position.rawValue, forKey: "position") } }
    @Published var autoPaste: Bool { didSet { d.set(autoPaste, forKey: "autoPaste") } }
    @Published var historyLimit: Int { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    @Published var saveImages: Bool { didSet { d.set(saveImages, forKey: "saveImages") } }
    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    /// Not persisted: true when another app already owns the chosen shortcut.
    @Published var hotKeyTaken = false

    var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }

    private init() {
        d.register(defaults: [
            "hotKey": HotKeyPreset.shiftCmdV.rawValue,
            "theme": Theme.dark.rawValue,
            "position": PanelPosition.caret.rawValue,
            "autoPaste": true,
            "historyLimit": 200,
            "saveImages": true,
            "paused": false,
        ])
        hotKey = HotKeyPreset(rawValue: d.string(forKey: "hotKey") ?? "") ?? .shiftCmdV
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .dark
        position = PanelPosition(rawValue: d.string(forKey: "position") ?? "") ?? .caret
        autoPaste = d.bool(forKey: "autoPaste")
        historyLimit = d.integer(forKey: "historyLimit")
        saveImages = d.bool(forKey: "saveImages")
        paused = d.bool(forKey: "paused")
    }
}
