import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var model: PanelModel
    @ObservedObject private var prefs = Prefs.shared
    let actions: PanelActions
    let onSearchField: (NSTextField) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            if model.pinned.isEmpty && model.recent.isEmpty {
                EmptyState(searching: !model.query.isEmpty || model.filter != .all)
            } else {
                list
            }
            if prefs.autoPaste && !model.axTrusted { accessBanner }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .background(Color(nsColor: .panelTint))
        .overlay(
            RoundedRectangle(cornerRadius: PanelController.cornerRadius, style: .circular)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                SearchField(text: $model.query, placeholder: tr("Поиск по истории", "Search history"), onCreate: onSearchField)
                    .frame(height: 22)
                if prefs.paused {
                    Text(tr("пауза", "paused"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(.orange)
                }
                Menu {
                    Button(prefs.paused ? tr("Возобновить запись", "Resume Recording")
                                         : tr("Приостановить запись", "Pause Recording")) { actions.togglePause() }
                    Button(tr("Очистить историю…", "Clear History…")) { actions.clearHistory() }
                    Divider()
                    Button(tr("Настройки…", "Settings…")) { actions.openSettings() }
                    Button(tr("Выйти из WolfClip", "Quit WolfClip")) { actions.quit() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            HStack(spacing: 6) {
                ForEach(ClipFilter.allCases) { filter in
                    FilterChip(title: filter.title, selected: model.filter == filter) { model.filter = filter }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Color.clear.frame(height: 0).id("top")
                    if !model.pinned.isEmpty {
                        SectionTitle(text: tr("Закреплённые", "Pinned"))
                        ForEach(Array(model.pinned.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                        }
                        if !model.recent.isEmpty {
                            SectionTitle(text: tr("Недавние", "Recent")).padding(.top, 6)
                        }
                    }
                    ForEach(Array(model.recent.enumerated()), id: \.element.id) { index, item in
                        row(item, index: model.pinned.count + index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: model.scrollRequest) { _, request in
                guard let request else { return }
                let scroll = {
                    switch request.target {
                    case .top: proxy.scrollTo("top", anchor: .top)
                    case .item(let id): proxy.scrollTo(id)
                    }
                }
                if request.animated {
                    withAnimation(.easeOut(duration: 0.12)) { scroll() }
                } else {
                    scroll()
                }
            }
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        ClipRow(item: item,
                index: index,
                selected: model.selectedID == item.id,
                imagesDir: store.imagesDir,
                onChoose: { actions.choose(item, false) },
                onChoosePlain: { actions.choose(item, true) },
                onPin: { actions.togglePin(item) },
                onDelete: { actions.delete(item) })
            .id(item.id)
    }

    private var accessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Разреши автовставку", "Allow auto-paste"))
                    .font(.system(size: 12, weight: .semibold))
                Text(tr("Пока выбранное только копируется в буфер", "Right now, picked items are only copied"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(tr("Разрешить", "Allow")) { actions.requestAccess() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.1)))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 11) {
            KeyHint(keys: "↵", label: prefs.autoPaste ? tr("вставить", "paste") : tr("копировать", "copy"))
            KeyHint(keys: "⇧↵", label: tr("без формата", "plain"))
            KeyHint(keys: "⌘P", label: tr("закрепить", "pin"))
            KeyHint(keys: "⌘⌫", label: tr("удалить", "delete"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

extension NSColor {
    /// Dense tint over the blur so busy windows underneath don't bleed through.
    static let panelTint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.086, green: 0.09, blue: 0.102, alpha: 0.86)
            : NSColor(srgbRed: 0.976, green: 0.976, blue: 0.982, alpha: 0.84)
    }
}

// MARK: - Row

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let imagesDir: URL
    let onChoose: () -> Void
    let onChoosePlain: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                ClipContent(item: item, imagesDir: imagesDir)
                MetaLine(item: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .frame(width: 52, alignment: .topTrailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(selected ? 0.55 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hover = $0 && !Demo.active }
        .onTapGesture { onChoose() }
        .contextMenu {
            Button(tr("Вставить", "Paste"), action: onChoose)
            if item.kind != .image { Button(tr("Вставить без форматирования", "Paste as Plain Text"), action: onChoosePlain) }
            Button(item.pinned ? tr("Открепить", "Unpin") : tr("Закрепить", "Pin"), action: onPin)
            Divider()
            Button(tr("Удалить", "Delete"), role: .destructive, action: onDelete)
        }
    }

    private var background: Color {
        if selected { return Color.accentColor.opacity(0.16) }
        return Color.primary.opacity(hover ? 0.08 : 0.04)
    }

    @ViewBuilder private var trailing: some View {
        if hover || selected {
            HStack(spacing: 0) {
                RowButton(symbol: item.pinned ? "pin.slash" : "pin", help: item.pinned ? tr("Открепить", "Unpin") : tr("Закрепить", "Pin"), action: onPin)
                RowButton(symbol: "trash", help: tr("Удалить", "Delete"), action: onDelete)
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 4)
        }
    }
}

struct ClipContent: View {
    let item: ClipItem
    let imagesDir: URL

    var body: some View {
        switch item.kind {
        case .text: textView
        case .link: linkView
        case .color: colorView
        case .image: imageView
        case .files: filesView
        }
    }

    private var trimmed: String { (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private var textView: some View {
        let raw = item.text ?? ""
        let code = Clip.looksLikeCode(raw)
        return Text(Clip.preview(raw))
            .font(code ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .lineLimit(4)
            .foregroundStyle(.primary)
    }

    private var linkView: some View {
        let url = URL(string: trimmed)
        var host = url?.host ?? trimmed
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(host)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(trimmed)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var colorView: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: Clip.color(fromHex: trimmed) ?? .clear))
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            Text(trimmed.uppercased())
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }

    @ViewBuilder private var imageView: some View {
        if let image = Thumbs.image(for: item, in: imagesDir) {
            let size = Clip.fit(CGFloat(item.pixelWidth ?? Int(image.size.width)),
                                CGFloat(item.pixelHeight ?? Int(image.size.height)),
                                maxW: 300, maxH: 120)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        } else {
            Label(tr("Картинка недоступна", "Image unavailable"), systemImage: "photo")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var filesView: some View {
        let urls = item.fileURLs
        let names = urls.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
        let subtitle = urls.count == 1
            ? Clip.abbreviate(urls[0].deletingLastPathComponent().path)
            : Clip.count(urls.count, ru: ("файл", "файла", "файлов"), en: ("file", "files"))
        return HStack(spacing: 10) {
            ZStack {
                if urls.count > 1 {
                    Image(nsImage: FileIcons.icon(for: urls[1]))
                        .resizable()
                        .frame(width: 26, height: 26)
                        .offset(x: 6, y: -4)
                        .opacity(0.75)
                }
                if let first = urls.first {
                    Image(nsImage: FileIcons.icon(for: first))
                        .resizable()
                        .frame(width: 30, height: 30)
                }
            }
            .frame(width: 36, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(names)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct MetaLine: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 5) {
            if let icon = AppIcons.icon(for: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            Text(item.appName ?? tr("Неизвестно", "Unknown"))
            Text("·")
            Text(Clip.relative(item.date))
            if let detail = Clip.detail(item) {
                Text("·")
                Text(detail)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - Small pieces

struct RowButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hover ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { hover = $0 }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(hover ? 0.11 : 0.06)))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }
}

struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

struct EmptyState: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: searching ? "magnifyingglass" : "list.clipboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching ? tr("Ничего не найдено", "Nothing found") : tr("История пуста", "History is empty"))
                .font(.system(size: 14, weight: .semibold))
            Text(searching ? tr("Попробуй другой запрос или фильтр", "Try a different search or filter")
                           : tr("Скопируй что-нибудь — оно появится здесь", "Copy something and it will show up here"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Plain AppKit text field: reliable focus inside a non-activating panel.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCreate: (NSTextField) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        onCreate(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// README screenshots (test builds only): the mouse may rest over the panel, so rows ignore hover.
enum Demo {
    #if WOLFCLIP_DEBUG
    static let active = ProcessInfo.processInfo.environment["WOLFCLIP_DEMO"] == "1"
    #else
    static let active = false
    #endif
}
