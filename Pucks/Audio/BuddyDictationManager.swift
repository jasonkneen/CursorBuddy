import AVFoundation
import Combine
import Foundation
import os
import Speech

enum BuddyDictationPermissionError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required for push-to-talk."
        case .speechRecognitionDenied:
            return "Speech recognition permission is required for the current transcription provider."
        }
    }
}

/// Manages audio recording via AVAudioEngine and transcription provider selection.
/// Provider priority: OpenAI (if configured) > AssemblyAI > Apple Speech.
@MainActor
final class BuddyDictationManager: ObservableObject {

    // MARK: - Published Properties

    @Published var audioPowerLevel: Float = 0.0
    @Published var currentAudioPowerLevel: Float = 0.0
    @Published var recordedAudioPowerHistory: [Float] = []
    @Published var isRecording: Bool = false
    @Published var transcriptText: String = ""

    // MARK: - Audio Engine

    private let audioEngine = AVAudioEngine()
    private let pcmConverter = BuddyPCM16AudioConverter()
    private(set) var bufferedPCM16AudioData = Data()

    // MARK: - Transcription

    private var transcriptionSession: BuddyStreamingTranscriptionSession?
    private var activeProvider: BuddyTranscriptionProvider?

    // MARK: - Providers

    private let providers: [BuddyTranscriptionProvider] = [
        OpenAIAudioTranscriptionProvider(),
        AssemblyAIStreamingTranscriptionProvider(),
        AppleSpeechTranscriptionProvider()
    ]

    // MARK: - Monitoring

    private var audioPowerCancellable: AnyCancellable?
    private var powerUpdateTimer: Timer?

    // MARK: - Logging

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pucks",
        category: "BuddyDictationManager"
    )

    // MARK: - Init

    init() {}

    // MARK: - Permissions

    /// Check microphone and speech recognition permissions without prompting.
    func hasRequiredPermissions() -> Bool {
        guard CompanionPermissionCenter.hasMicrophonePermission() else {
            logger.warning("microphone permission missing or denied")
            return false
        }

        let selectedProvider = resolveProvider()
        if selectedProvider.requiresSpeechRecognitionPermission {
            guard CompanionPermissionCenter.hasSpeechRecognitionPermission() else {
                logger.warning("speech recognition permission missing or denied")
                return false
            }
        }

        return true
    }

    // MARK: - Provider Resolution

    /// Resolve the best available transcription provider.
    /// Priority: OpenAI > AssemblyAI > Apple Speech
    private func resolveProvider() -> BuddyTranscriptionProvider {
        for provider in providers {
            if provider.isConfigured {
                return provider
            }
        }
        // Apple Speech is always the ultimate fallback
        return providers.last!
    }

    // MARK: - Recording

    /// Start recording audio. Installs a tap on the audio engine input node,
    /// buffers PCM16 audio, and feeds it to the active transcription session.
    func startRecording() async throws {
        guard !isRecording else { return }

        guard CompanionPermissionCenter.hasMicrophonePermission() else {
            logger.warning("microphone permission missing or denied")
            throw BuddyDictationPermissionError.microphoneDenied
        }

        let selectedProvider = resolveProvider()
        if selectedProvider.requiresSpeechRecognitionPermission,
           !CompanionPermissionCenter.hasSpeechRecognitionPermission() {
            logger.warning("speech recognition permission missing or denied")
            throw BuddyDictationPermissionError.speechRecognitionDenied
        }

        // Resolve provider
        let provider = selectedProvider
        activeProvider = provider
        logger.info("Using transcription provider: \(provider.providerName)")

        // Create transcription session
        do {
            let session = try provider.createSession()
            session.onTranscriptUpdate = { [weak self] text in
                Task { @MainActor in
                    self?.transcriptText = text
                }
            }
            session.onError = { [weak self] error in
                Task { @MainActor in
                    if !(self?.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        self?.logger.debug("Ignoring late transcription error after transcript was captured: \(error.localizedDescription)")
                        return
                    }
                    self?.logger.error("Transcription error: \(error.localizedDescription)")
                }
            }
            try session.start()
            transcriptionSession = session
        } catch {
            logger.error("Failed to create transcription session: \(error.localizedDescription)")
            throw error
        }

        // Reset buffers
        pcmConverter.reset()
        bufferedPCM16AudioData = Data()
        recordedAudioPowerHistory = []
        transcriptText = ""

        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create a format for 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("Failed to create target audio format")
            return
        }

        // Install converter if needed
        guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
            logger.error("Failed to create audio converter")
            return
        }

        logger.info("BuddyDictationManager: provider ready, starting audio engine")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, time in
            guard let self = self else { return }

            // Convert to target format
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / recordingFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error else {
                return
            }

            // Buffer PCM16 data
            self.pcmConverter.appendAudioPCMBuffer(buffer: convertedBuffer)

            // Feed to transcription session
            self.transcriptionSession?.feedAudio(buffer: convertedBuffer)

            // Calculate power level
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<frameCount {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(frameCount))
                let power = 20 * log10(max(rms, 0.000001))
                let normalizedPower = max(0.0, min(1.0, (power + 50) / 50))

                Task { @MainActor [weak self] in
                    self?.audioPowerLevel = normalizedPower
                    self?.currentAudioPowerLevel = normalizedPower
                    self?.recordedAudioPowerHistory.append(normalizedPower)
                }
            }
        }

        do {
            try audioEngine.start()
            isRecording = true
            logger.info("recognition session started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    /// Stop recording, wait for transcription, and return the transcript text.
    /// - Returns: The transcribed text, or nil if transcription failed.
    @discardableResult
    func stopRecording() async -> String? {
        guard isRecording else { return nil }

        // Stop audio engine and remove tap
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        isRecording = false
        audioPowerLevel = 0.0
        currentAudioPowerLevel = 0.0

        // Get WAV data
        let wavData = pcmConverter.getWAVData()
        bufferedPCM16AudioData = pcmConverter.pcm16Data
        logger.info("Recording stopped. WAV data: \(wavData.count) bytes")

        // If using OpenAI provider, await the transcription
        if let openAISession = transcriptionSession as? OpenAIAudioTranscriptionSession {
            let result = await openAISession.stopAndTranscribe()
            if let text = result, !text.isEmpty {
                transcriptText = text
            }
        } else {
            // Streaming providers (Apple Speech, AssemblyAI) already set transcriptText
            transcriptionSession?.stop()
        }

        let result = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Final transcript: \"\(result.prefix(80))\"")
        return result.isEmpty ? nil : result
    }

    /// Cancel a recording that was in progress (e.g., shortcut released early).
    func cancelRecording() {
        guard isRecording else { return }

        logger.info("start cancelled (shortcut released before/during recording)")

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        transcriptionSession?.stop()
        transcriptionSession = nil

        isRecording = false
        audioPowerLevel = 0.0
        currentAudioPowerLevel = 0.0
        pcmConverter.reset()
        bufferedPCM16AudioData = Data()
    }
}
