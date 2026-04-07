import AVFoundation
import Foundation
import os

// MARK: - Errors

enum OpenAIAudioTranscriptionProviderError: LocalizedError {
    case notConfigured
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI transcription is not configured. Add OpenAIAPIKey to Info.plist."
        case .transcriptionFailed(let reason):
            return "OpenAI transcription failed: \(reason)"
        }
    }
}

// MARK: - Provider

/// OpenAI audio transcription provider. Transcribes audio after recording stops (not streaming).
/// This is the preferred provider when configured.
struct OpenAIAudioTranscriptionProvider: BuddyTranscriptionProvider {

    let providerName = "OpenAI"

    var isConfigured: Bool {
        guard let key = apiKey, !key.isEmpty else {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pucks", category: "OpenAITranscription")
                .info("Transcription: OpenAI preferred but not configured, falling back")
            return false
        }
        return true
    }

    var requiresSpeechRecognitionPermission: Bool { false }

    private var apiKey: String? {
        APIKeyConfig.openAIKey
    }

    func createSession() throws -> BuddyStreamingTranscriptionSession {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenAIAudioTranscriptionProviderError.notConfigured
        }
        return OpenAIAudioTranscriptionSession(apiKey: key)
    }
}

// MARK: - Session

/// OpenAI transcription session. Buffers all audio and transcribes when stopped.
final class OpenAIAudioTranscriptionSession: BuddyStreamingTranscriptionSession, @unchecked Sendable {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pucks",
        category: "OpenAITranscriptionSession"
    )

    private let apiKey: String
    private let transcriptionQueue = DispatchQueue(label: "com.learningbuddy.openai.transcription")
    private let pcmConverter = BuddyPCM16AudioConverter()

    // MARK: Protocol properties

    private(set) var isReady: Bool = false
    private(set) var transcriptText: String = ""
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: Init

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: Protocol methods

    func start() throws {
        pcmConverter.reset()
        isReady = true
        logger.info("OpenAI transcription session started (buffering audio)")
    }

    func stop() {
        isReady = false
        // For OpenAI, actual transcription happens in stopAndTranscribe() async
    }

    /// Async version: stops recording and waits for OpenAI to return the transcript.
    func stopAndTranscribe() async -> String? {
        isReady = false

        let wavData = pcmConverter.getWAVData()
        logger.info("OpenAI transcription session stopped. Buffered \(wavData.count) bytes, sending to API.")

        guard wavData.count > 44 else {
            logger.warning("No audio data buffered, skipping transcription")
            return nil
        }

        do {
            let text = try await OpenAIAPI.shared.transcribe(
                audioData: wavData,
                apiKey: self.apiKey
            )
            self.transcriptText = text
            self.logger.info("OpenAI transcription complete: \(text.prefix(80))...")
            self.onTranscriptUpdate?(text)
            return text
        } catch {
            self.logger.error("OpenAI transcription error: \(error.localizedDescription)")
            self.onError?(error)
            return nil
        }
    }

    func feedAudio(buffer: AVAudioPCMBuffer) {
        guard isReady else { return }
        pcmConverter.appendAudioPCMBuffer(buffer: buffer)
    }
}
