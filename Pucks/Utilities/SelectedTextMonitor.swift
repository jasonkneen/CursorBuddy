import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class SelectedTextMonitor: ObservableObject {
    private let focusedUIElementAttribute: NSString = "AXFocusedUIElement"
    private let focusedWindowAttribute: NSString = "AXFocusedWindow"
    private let selectedTextAttribute: NSString = "AXSelectedText"

    @Published private(set) var selectedText: String = ""

    var hasSelection: Bool {
        !selectedText.isEmpty
    }

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard CompanionPermissionCenter.hasAccessibilityPermission() else {
            selectedText = ""
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            selectedText = ""
            return
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        guard let focusedElement = copyAXElement(appElement, attribute: focusedUIElementAttribute)
            ?? copyAXElement(appElement, attribute: focusedWindowAttribute) else {
            selectedText = ""
            return
        }

        let text = extractSelectedText(from: focusedElement)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let filteredText = validatedSelectionText(from: text) else {
            selectedText = ""
            return
        }

        selectedText = filteredText
    }

    private func extractSelectedText(from element: AXUIElement) -> String? {
        if let text = copyStringValue(from: element, attribute: selectedTextAttribute), !text.isEmpty {
            return text
        }

        if let nestedElement = copyAXElement(element, attribute: focusedUIElementAttribute) {
            return copyStringValue(from: nestedElement, attribute: selectedTextAttribute)
        }

        return nil
    }

    private func copyAXElement(_ element: AXUIElement, attribute: NSString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyStringValue(from element: AXUIElement, attribute: NSString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func validatedSelectionText(from text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        let wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        let identifierPattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
        let looksLikeSingleIdentifier = normalized.range(of: identifierPattern, options: .regularExpression) != nil
        let hasStructure = normalized.contains("\n")
            || normalized.contains(" ")
            || normalized.contains("{")
            || normalized.contains("(")
            || normalized.contains(".")
            || normalized.contains(":")

        guard !looksLikeSingleIdentifier else { return nil }
        guard normalized.count >= 16 || wordCount >= 3 || hasStructure else { return nil }

        return String(normalized.prefix(280))
    }
}
