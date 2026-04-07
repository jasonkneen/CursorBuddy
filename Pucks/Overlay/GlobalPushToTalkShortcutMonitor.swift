import AppKit
import Carbon

/// Monitors a global hold-to-talk hotkey using Carbon's EventHotKey API.
/// Default shortcut: Control + Option + Space.
final class GlobalPushToTalkShortcutMonitor {

    // MARK: - Configuration

    var keyCode: UInt32 = UInt32(kVK_Space)
    var modifiers: UInt32 = UInt32(controlKey | optionKey)

    // MARK: - Callbacks

    var onShortcutPressed: (() -> Void)?
    var onShortcutReleased: (() -> Void)?

    // MARK: - State

    private(set) var isShortcutCurrentlyPressed: Bool = false
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private let hotKeySignature = GlobalPushToTalkShortcutMonitor.fourCharCode("CLUS")
    fileprivate let hotKeyID: UInt32 = 1

    deinit {
        stop()
    }

    // MARK: - Public

    @discardableResult
    func start() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalPTTHotKeyHandler,
            eventSpecs.count,
            &eventSpecs,
            selfPtr,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            print("[PTT] Failed to install hotkey event handler (\(handlerStatus))")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: self.hotKeyID)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            print("[PTT] Failed to register global hotkey (\(registerStatus))")
            return false
        }

        print("[PTT] Event hotkey started successfully")
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        isShortcutCurrentlyPressed = false
    }

    // MARK: - Internal

    fileprivate func handleShortcutPressed() {
        guard !isShortcutCurrentlyPressed else { return }
        isShortcutCurrentlyPressed = true
        DispatchQueue.main.async { [weak self] in
            self?.onShortcutPressed?()
        }
    }

    fileprivate func handleShortcutReleased() {
        guard isShortcutCurrentlyPressed else { return }
        isShortcutCurrentlyPressed = false
        DispatchQueue.main.async { [weak self] in
            self?.onShortcutReleased?()
        }
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { partial, byte in
            (partial << 8) + OSType(byte)
        }
    }
}

private func globalPTTHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return noErr }

    let monitor = Unmanaged<GlobalPushToTalkShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
    let eventKind = GetEventKind(event)

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr, hotKeyID.id == monitor.hotKeyID else {
        return noErr
    }

    switch eventKind {
    case UInt32(kEventHotKeyPressed):
        monitor.handleShortcutPressed()
    case UInt32(kEventHotKeyReleased):
        monitor.handleShortcutReleased()
    default:
        break
    }

    return noErr
}
