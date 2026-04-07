import AVFoundation
import Foundation
import os
import Speech

// MARK: - Errors

enum AppleSpeechTranscriptionProviderError: LocalizedError {
    case speechRecognizerUnavailable
    case recognitionRequestFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available for the current locale."
        case .recognitionRequestFailed:
            return "Failed to create or start a speech recognition request."
        case .permissionDenied:
            return "Speech recognition permission was denied."
        }
    }
}

// MARK: - Provider

/// Apple Speech transcription provider using SFSpeechRecognizer.
/// Used as the fallback provider when OpenAI and AssemblyAI are not configured.
struct AppleSpeechTranscriptionProvider: BuddyTranscriptionProvider {

    let providerName = "Apple Speech"

    var isConfigured: Bool {
        return SFSpeechRecognizer()?.isAvailable ?? false
    }

    var requiresSpeechRecognitionPermission: Bool { true }

    func createSession() throws -> BuddyStreamingTranscriptionSession {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw AppleSpeechTranscriptionProviderError.speechRecognizerUnavailable
        }
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pucks", category: "AppleSpeech")
            .info("Transcription: using Apple Speech as fallback")
        return AppleSpeechTranscriptionSession(recognizer: recognizer)
    }

    /// Request speech recognition permission if not already granted.
    func requestSpeechRecognitionPermissionIfNeeded() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
    }
}

// MARK: - Session

private final class AppleSpeechTranscriptionSession: BuddyStreamingTranscriptionSession {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pucks",
        category: "AppleSpeechSession"
    )

    private let recognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStopping = false

    // MARK: Protocol properties

    private(set) var isReady: Bool = false
    private(set) var transcriptText: String = ""
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: Init

    init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    // MARK: Protocol methods

    func start() throws {
        isStopping = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.transcriptText = text
                DispatchQueue.main.async {
                    self.onTranscriptUpdate?(text)
                }
            }

            if let error = error {
                let nsError = error as NSError
                let noSpeechErrorCode = 1110
                if self.isStopping || (!self.transcriptText.isEmpty && nsError.domain == "kAFAssistantErrorDomain" && nsError.code == noSpeechErrorCode) {
                    self.logger.debug("Ignoring Apple Speech shutdown error: \(error.localizedDescription)")
                    return
                }

                self.logger.error("Apple Speech recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?(error)
                }
            }
        }

        isReady = true
        logger.info("Apple Speech recognition session started")
    }

    func stop() {
        isStopping = true
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isReady = false
        logger.info("Apple Speech recognition session stopped")
    }

    func feedAudio(buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
}
