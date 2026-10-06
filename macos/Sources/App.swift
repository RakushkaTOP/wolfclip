import AppKit
import Combine

@main
enum WolfClipApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs.shared
    private let store = HistoryStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var panel = PanelController(store: store, monitor: monitor)
    private lazy var settingsWindow = SettingsWindow(store: store)
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem!
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()
        #if WOLFCLIP_DEBUG
        // Demo mode for README screenshots: show prepared data only, never record the real clipboard.
        if ProcessInfo.processInfo.environment["WOLFCLIP_DEMO"] != "1" { monitor.start() }
        #else
        monitor.start()
        #endif
        panel.openSettings = { [weak self] in self?.settingsWindow.show() }
        panel.clearHistory = { [weak self] in self?.confirmClear() }
        setupStatusItem()

        HotKey.onPress = { [weak self] in self?.panel.toggle() }
        registerHotKey(prefs.hotKey)
        prefs.$hotKey.dropFirst()
            .sink { [weak self] preset in self?.registerHotKey(preset) }
            .store(in: &bag)
        prefs.$historyLimit.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.store.trim() } }
            .store(in: &bag)
        prefs.$theme
            .sink { theme in NSApp.appearance = theme.appearance }
            .store(in: &bag)
        prefs.$paused
            .sink { [weak self] paused in self?.statusItem?.button?.appearsDisabled = paused }
            .store(in: &bag)

        if !prefs.onboarded {
            prefs.onboarded = true
            LoginItem.set(true)
            settingsWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// Launching the app again (Finder, Spotlight) opens the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    /// wolfclip://show opens the history, wolfclip://settings opens the settings.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        DispatchQueue.main.async {
            #if WOLFCLIP_DEBUG
            if url.host == "debug" { self.panel.debug(url); return }
            #endif
            if url.host == "settings" { self.settingsWindow.show() } else { self.panel.show() }
        }
    }

    private func registerHotKey(_ preset: HotKeyPreset) {
        let ok = hotKey.register(preset)
        prefs.hotKeyTaken = !ok
        if !ok { NSLog("WolfClip: shortcut \(preset.title) is already taken") }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "WolfClip")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = prefs.paused
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: tr("Открыть историю", "Open History"), action: #selector(openPanel), keyEquivalent: "v")
        open.keyEquivalentModifierMask = prefs.hotKey.modifierFlags
        open.target = self
        menu.addItem(open)

        let items = Clip.count(store.items.count, ru: ("запись", "записи", "записей"), en: ("item", "items"))
        let count = NSMenuItem(title: tr("В истории: " + items, items + " in history"),
                               action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: prefs.paused ? tr("Возобновить запись", "Resume Recording")
                                                   : tr("Приостановить запись", "Pause Recording"),
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: tr("Очистить историю…", "Clear History…"), action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: tr("Настройки…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem(title: tr("Выйти из WolfClip", "Quit WolfClip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openPanel() {
        DispatchQueue.main.async { self.panel.show() }
    }

    @objc private func togglePause() {
        prefs.paused.toggle()
    }

    @objc private func clearHistory() {
        DispatchQueue.main.async { self.confirmClear() }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    private func confirmClear() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("Очистить историю?", "Clear history?")
        alert.informativeText = tr("Удалятся все записи, кроме закреплённых. Отменить это нельзя.",
                                   "All items except pinned ones will be deleted. This can’t be undone.")
        alert.addButton(withTitle: tr("Очистить", "Clear"))
        alert.addButton(withTitle: tr("Отмена", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }
}
