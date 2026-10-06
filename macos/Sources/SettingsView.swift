import AppKit
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 790),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "WolfClip"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct SettingsView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject private var prefs = Prefs.shared
    @State private var axTrusted = Accessibility.trusted
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmClear = false
    @State private var diskUsage: Int64 = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Form {
                Section(tr("Основное", "General")) {
                    Picker(tr("Горячая клавиша", "Shortcut"), selection: $prefs.hotKey) {
                        ForEach(HotKeyPreset.allCases) { Text($0.title).tag($0) }
                    }
                    if prefs.hotKeyTaken {
                        Text(tr("Это сочетание уже занято другим приложением — выбери другое.",
                                 "This shortcut is already used by another app — pick a different one."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.orange)
                    }
                    Picker(tr("Тема", "Appearance"), selection: $prefs.theme) {
                        ForEach(Theme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(tr("Где открывать окно", "Window position"), selection: $prefs.position) {
                        ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(tr("Вставлять сразу после выбора", "Paste immediately after choosing"), isOn: $prefs.autoPaste)
                    Toggle(tr("Запускать при входе в систему", "Launch at login"), isOn: Binding(
                        get: { launchAtLogin },
                        set: { on in
                            LoginItem.set(on)
                            launchAtLogin = LoginItem.isEnabled
                        }))
                }

                Section(tr("История", "History")) {
                    Picker(tr("Хранить записей", "Items to keep"), selection: $prefs.historyLimit) {
                        ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Toggle(tr("Сохранять картинки", "Save images"), isOn: $prefs.saveImages)
                    LabeledContent(tr("Сейчас в истории", "Currently in history")) {
                        Text("\(Clip.count(store.items.count, ru: ("запись", "записи", "записей"), en: ("item", "items"))) · \(ByteCountFormatter.string(fromByteCount: diskUsage, countStyle: .file))")
                    }
                    HStack {
                        Spacer()
                        Button(tr("Очистить историю…", "Clear History…"), role: .destructive) { confirmClear = true }
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(axTrusted ? Color.green : Color.orange)
                        Text(axTrusted ? tr("Доступ выдан — автовставка работает", "Access granted — auto-paste is on")
                                        : tr("Доступ не выдан", "Access not granted"))
                        Spacer()
                        if !axTrusted {
                            Button(tr("Выдать доступ", "Grant Access")) { Accessibility.requestFresh() }
                        }
                    }
                } header: {
                    Text(tr("Универсальный доступ", "Accessibility"))
                } footer: {
                    Text(tr("Нужен, чтобы WolfClip сам нажимал ⌘V в приложении, где ты печатаешь, и открывался у текстового курсора. Кнопка сбрасывает старую запись WolfClip в списке и просит доступ заново — останется включить переключатель.",
                             "Lets WolfClip press ⌘V for you in the app you’re typing in and open at the text cursor. The button resets WolfClip’s old entry in the list and asks for access again — then just turn on the switch."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section(tr("Приватность", "Privacy")) {
                    Label(tr("Пароли из менеджеров паролей не записываются", "Passwords from password managers are never recorded"), systemImage: "lock.shield")
                    Label(tr("История хранится только на этом Mac", "History is stored only on this Mac"), systemImage: "internaldrive")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 790)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in axTrusted = Accessibility.trusted }
        .onChange(of: store.items.count) { _, _ in diskUsage = store.diskUsage() }
        .alert(tr("Очистить историю?", "Clear history?"), isPresented: $confirmClear) {
            Button(tr("Очистить", "Clear"), role: .destructive) { store.clear() }
            Button(tr("Отмена", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Удалятся все записи, кроме закреплённых.", "All items except pinned ones will be deleted."))
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("WolfClip")
                        .font(.system(size: 22, weight: .bold))
                    Text("v\(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Text(tr("История буфера обмена. Нажми \(prefs.hotKey.title) в любом приложении — и выбери, что вставить.",
                         "Clipboard history. Press \(prefs.hotKey.title) in any app and pick what to paste."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 38)
        .padding(.bottom, 2)
    }

    private func refresh() {
        axTrusted = Accessibility.trusted
        launchAtLogin = LoginItem.isEnabled
        diskUsage = store.diskUsage()
    }
}
