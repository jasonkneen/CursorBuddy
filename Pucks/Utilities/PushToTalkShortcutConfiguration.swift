import AppKit
import Carbon
import Foundation

@MainActor
final class PushToTalkShortcutConfiguration: ObservableObject {
    static let shared = PushToTalkShortcutConfiguration()
    static let didChangeNotification = Notification.Name("com.pucks.pushToTalkShortcutChanged")

    @Published var keyCode: UInt32 {
        didSet { persistAndNotify() }
    }

    @Published var modifiers: UInt32 {
        didSet { persistAndNotify() }
    }

    var label: String {
        Self.label(forKeyCode: keyCode, modifiers: modifiers)
    }

    private static let keyCodeUserDefaultsKey = "pushToTalkShortcutKeyCode"
    private static let modifiersUserDefaultsKey = "pushToTalkShortcutModifiers"

    private init() {
        let storedKeyCode = UserDefaults.standard.object(forKey: Self.keyCodeUserDefaultsKey) as? UInt32
        let storedModifiers = UserDefaults.standard.object(forKey: Self.modifiersUserDefaultsKey) as? UInt32

        self.keyCode = storedKeyCode ?? UInt32(kVK_Space)
        self.modifiers = storedModifiers ?? UInt32(optionKey)
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func resetToDefault() {
        update(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    }

    private func persistAndNotify() {
        UserDefaults.standard.set(keyCode, forKey: Self.keyCodeUserDefaultsKey)
        UserDefaults.standard.set(modifiers, forKey: Self.modifiersUserDefaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    static func captureModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        return carbonModifiers
    }

    static func label(forKeyCode keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Opt") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "Left Arrow"
        case kVK_RightArrow: return "Right Arrow"
        case kVK_UpArrow: return "Up Arrow"
        case kVK_DownArrow: return "Down Arrow"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key \(keyCode)"
        }
    }
}
