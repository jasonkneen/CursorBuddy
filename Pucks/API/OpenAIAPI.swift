import Foundation
import os

class OpenAIAPI {
    static let shared = OpenAIAPI()

    private let endpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pucks", category: "OpenAIAPI")

    var transcriptionModel: String = "gpt-4o-transcribe"

    func transcribe(audioData: Data, apiKey: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(transcriptionModel)\r\n".data(using: .utf8)!)

        // audio file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        logger.info("OpenAI transcription request: \(audioData.count) bytes of audio")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAIAPI", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"])
        }

        // Parse the response - could be JSON with a "text" field
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text
        }

        // Fallback: return raw string
        guard let transcript = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "OpenAIAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to decode transcription response"])
        }

        return transcript
    }
}
