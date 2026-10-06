import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

/// Global shortcut through Carbon: works without the Accessibility permission.
final class HotKey {
    static var onPress: (() -> Void)?
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()
        Self.installHandler()
        let id = EventHotKeyID(signature: 0x5743_4C50, id: 1) // 'WCLP'
        let status = RegisterEventHotKey(preset.keyCode, preset.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKey.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum Paster {
    static func write(_ item: ClipItem, plain: Bool, imagesDir: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .files where !plain:
            pb.writeObjects(item.fileURLs as [NSURL])
        case .image:
            guard let name = item.imageFile,
                  let data = try? Data(contentsOf: imagesDir.appendingPathComponent(name)) else { return }
            let pi = NSPasteboardItem()
            pi.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { pi.setData(tiff, forType: .tiff) }
            pb.writeObjects([pi])
        default:
            let pi = NSPasteboardItem()
            pi.setString(item.text ?? "", forType: .string)
            if !plain {
                if let rtf = item.rtf { pi.setData(rtf, forType: .rtf) }
                if let html = item.html { pi.setData(html, forType: .html) }
            }
            pb.writeObjects([pi])
        }
    }

    /// Presses ⌘V in whatever app has keyboard focus. Needs the Accessibility permission.
    static func sendPaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}

enum Accessibility {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Drops any stale entry (e.g. left by an older build), asks again and opens the settings pane.
    static func requestFresh() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "one.wolfteam.wolfclip"]
        try? reset.run()
        reset.waitUntilExit()
        prompt()
        openSettings()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Screen rect of the text caret in the focused app, in Cocoa coordinates.
    static func caretRect() -> NSRect? {
        guard trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
              rect.origin != .zero, rect.height > 0, rect.height < 200 else { return nil }

        // AX uses a top-left origin on the primary screen; Cocoa uses bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoa = NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: max(rect.width, 1), height: rect.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(cocoa) }) else { return nil }
        return cocoa
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("WolfClip: login item change failed: \(error)")
        }
    }
}
