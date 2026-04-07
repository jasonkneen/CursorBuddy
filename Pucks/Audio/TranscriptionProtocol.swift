import AVFoundation
import Foundation

// MARK: - Transcription Session Protocol

/// A transcription session that can receive audio buffers and produce transcript text.
protocol BuddyStreamingTranscriptionSession: AnyObject {
    /// Whether the session is ready to receive audio.
    var isReady: Bool { get }

    /// The current best transcript text. Updated as new audio is processed.
    var transcriptText: String { get }

    /// Callback invoked on the main queue when transcriptText changes.
    var onTranscriptUpdate: ((String) -> Void)? { get set }

    /// Callback invoked when the session encounters an error.
    var onError: ((Error) -> Void)? { get set }

    /// Start the transcription session.
    func start() throws

    /// Stop the transcription session and finalize results.
    func stop()

    /// Feed an audio buffer into the session for transcription.
    /// - Parameter buffer: PCM audio buffer from AVAudioEngine tap.
    func feedAudio(buffer: AVAudioPCMBuffer)
}

// MARK: - Transcription Provider Protocol

/// A provider that can create transcription sessions.
protocol BuddyTranscriptionProvider {
    /// Display name for logging.
    var providerName: String { get }

    /// Whether this provider is currently configured and available.
    var isConfigured: Bool { get }

    /// Whether this provider requires speech recognition permission (e.g., Apple Speech).
    var requiresSpeechRecognitionPermission: Bool { get }

    /// Create a new transcription session.
    func createSession() throws -> BuddyStreamingTranscriptionSession
}

extension BuddyTranscriptionProvider {
    var requiresSpeechRecognitionPermission: Bool { false }
}
