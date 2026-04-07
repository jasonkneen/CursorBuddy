import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import Speech

enum CompanionPermissionCenter {
    static func hasMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 11.0, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        // When screen recording is granted, on-screen windows usually include readable names/owners.
        return windowList.contains {
            let name = ($0[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let owner = ($0[kCGWindowOwnerName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return !(name?.isEmpty ?? true) || !(owner?.isEmpty ?? true)
        }
    }

    static func hasScreenRecordingPermissionAsync() async -> Bool {
        if hasScreenRecordingPermission() {
            return true
        }

        if #available(macOS 13.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return !content.displays.isEmpty
            } catch {
                return false
            }
        }

        return hasScreenRecordingPermission()
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func hasSpeechRecognitionPermission() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func requestScreenRecordingPermission() {
        if #available(macOS 11.0, *) {
            let granted = CGRequestScreenCaptureAccess()
            if granted { return }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !hasScreenRecordingPermission() {
                openSystemSettingsPrivacyPane(anchor: "Privacy_ScreenCapture")
            }
        }
    }

    @discardableResult
    static func requestAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    private static func openSystemSettingsPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
