import AVFoundation
import Foundation
import os

class ElevenLabsTTSClient {
    static let shared = ElevenLabsTTSClient()

    private let baseURL = "https://api.elevenlabs.io/v1/text-to-speech"
    private let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM" // Rachel
    private let modelId = "eleven_flash_v2_5"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pucks", category: "ElevenLabsTTS")

    var audioPlayer: AVAudioPlayer?

    /// Speaks text aloud via ElevenLabs TTS.
    /// Returns audio data. Also plays it immediately.
    func speak(text: String) async throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Data()
        }

        guard let apiKey = APIKeyConfig.elevenLabsKey else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "ElevenLabs API key not configured."])
        }

        let audioData = try await callAPI(text: text, apiKey: apiKey)

        // Play the audio
        try await MainActor.run {
            do {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.play()
                logger.info("ElevenLabs TTS: playing \(audioData.count) bytes")
            } catch {
                logger.error("ElevenLabs TTS error: \(error.localizedDescription)")
                throw error
            }
        }

        // Wait for playback to finish
        while await MainActor.run(body: { audioPlayer?.isPlaying == true }) {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        return audioData
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - API

    private func callAPI(text: String, apiKey: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/\(defaultVoiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 429 || httpResponse.statusCode == 402 {
            throw NSError(domain: "ElevenLabsTTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "ElevenLabs quota exceeded. Check your plan and billing."])
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("ElevenLabs TTS error: HTTP \(httpResponse.statusCode) \(errorText)")
            throw NSError(domain: "ElevenLabsTTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "TTS failed: \(errorText)"])
        }

        return data
    }
}
