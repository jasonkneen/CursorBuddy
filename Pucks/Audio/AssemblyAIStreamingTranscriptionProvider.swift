import AVFoundation
import Foundation
import os

// MARK: - Errors

enum AssemblyAIStreamingTranscriptionProviderError: LocalizedError {
    case notConfigured
    case connectionFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AssemblyAI is not configured. Add AssemblyAIAPIKey or AssemblyAIStreamingToken to Info.plist."
        case .connectionFailed(let reason):
            return "AssemblyAI WebSocket connection failed: \(reason)"
        case .invalidResponse:
            return "Received invalid response from AssemblyAI."
        }
    }
}

// MARK: - Provider

/// AssemblyAI real-time streaming transcription provider using WebSocket.
struct AssemblyAIStreamingTranscriptionProvider: BuddyTranscriptionProvider {

    let providerName = "AssemblyAI"

    var isConfigured: Bool {
        return token != nil
    }

    var requiresSpeechRecognitionPermission: Bool { false }

    private var token: String? {
        APIKeyConfig.assemblyAIStreamingToken ?? APIKeyConfig.assemblyAIKey
    }

    func createSession() throws -> BuddyStreamingTranscriptionSession {
        guard let token = token, !token.isEmpty else {
            throw AssemblyAIStreamingTranscriptionProviderError.notConfigured
        }
        return AssemblyAIStreamingTranscriptionSession(token: token)
    }
}

// MARK: - Session

private final class AssemblyAIStreamingTranscriptionSession: BuddyStreamingTranscriptionSession {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pucks",
        category: "AssemblyAISession"
    )

    private let token: String
    private var webSocketTask: URLSessionWebSocketTask?
    private let sendQueue = DispatchQueue(label: "com.learningbuddy.assemblyai.send")
    private let stateQueue = DispatchQueue(label: "com.learningbuddy.assemblyai.state")

    private let pcmConverter = BuddyPCM16AudioConverter()

    // MARK: Protocol properties

    private(set) var isReady: Bool = false
    private(set) var transcriptText: String = ""
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: Init

    init(token: String) {
        self.token = token
    }

    // MARK: Protocol methods

    func start() throws {
        let urlString = "wss://streaming.assemblyai.com/v3/ws"
        guard var urlComponents = URLComponents(string: urlString) else {
            throw AssemblyAIStreamingTranscriptionProviderError.connectionFailed("Invalid URL")
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "pcm_s16le")
        ]

        guard let url = urlComponents.url else {
            throw AssemblyAIStreamingTranscriptionProviderError.connectionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        stateQueue.sync { isReady = true }
        logger.info("AssemblyAI streaming session started")

        receiveMessages()
    }

    func stop() {
        stateQueue.sync { isReady = false }

        // Send terminate message
        let terminateMessage = "{\"terminate_session\": true}"
        webSocketTask?.send(.string(terminateMessage)) { [weak self] error in
            if let error = error {
                self?.logger.warning("Error sending terminate: \(error.localizedDescription)")
            }
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        logger.info("AssemblyAI streaming session stopped")
    }

    func feedAudio(buffer: AVAudioPCMBuffer) {
        guard isReady else { return }

        // Convert to PCM16
        pcmConverter.reset()
        pcmConverter.appendAudioPCMBuffer(buffer: buffer)
        let pcmData = pcmConverter.pcm16Data
        let base64Audio = pcmData.base64EncodedString()

        let jsonMessage = "{\"audio_data\": \"\(base64Audio)\"}"

        sendQueue.async { [weak self] in
            self?.webSocketTask?.send(.string(jsonMessage)) { error in
                if let error = error {
                    self?.logger.warning("Error sending audio: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.receiveMessages()

            case .failure(let error):
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTranscriptionResponse(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTranscriptionResponse(text)
            }
        @unknown default:
            break
        }
    }

    private func parseTranscriptionResponse(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // AssemblyAI v3 streaming response format
        if let text = json["text"] as? String,
           let messageType = json["message_type"] as? String {

            if messageType == "FinalTranscript" || messageType == "PartialTranscript" {
                if !text.isEmpty {
                    stateQueue.sync {
                        if messageType == "FinalTranscript" {
                            if self.transcriptText.isEmpty {
                                self.transcriptText = text
                            } else {
                                self.transcriptText += " " + text
                            }
                        }
                    }

                    let currentText = stateQueue.sync { self.transcriptText }
                    let displayText = messageType == "PartialTranscript"
                        ? (currentText.isEmpty ? text : currentText + " " + text)
                        : currentText

                    DispatchQueue.main.async {
                        self.onTranscriptUpdate?(displayText)
                    }
                }
            }
        }

        // Handle errors from the server
        if let error = json["error"] as? String {
            logger.error("AssemblyAI error: \(error)")
            DispatchQueue.main.async {
                self.onError?(AssemblyAIStreamingTranscriptionProviderError.connectionFailed(error))
            }
        }
    }
}
