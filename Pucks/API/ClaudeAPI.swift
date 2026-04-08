import AppKit
import Foundation
import os

class ClaudeAPI {
    static let shared = ClaudeAPI()

    /// Uses direct Anthropic API if ANTHROPIC_API_KEY is set, otherwise falls back to proxy.
    private var endpoint: String {
        if APIKeyConfig.anthropicKey != nil {
            return "https://api.anthropic.com/v1/messages"
        }
        return "https://clicky-proxy.farza-0cb.workers.dev/chat"
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pucks", category: "ClaudeAPI")

    private let systemPrompt = """
you're pucks, a friendly always-on companion that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation
- all lowercase, casual, warm. no emojis.
- default to one or two sentences. be direct and dense. BUT if the user asks you to explain more, go deeper, or elaborate, then go all out – give a thorough, detailed explanation with no length limit.
- write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting
- don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
- don't read out code verbatim. describe what the code does or what needs to change conversationally.
- focus on giving a thorough, useful explanation. don't end with simple yes/no questions like "want me to explain more?" or "should i show you?" – mention something bigger or more ambitious they could try, a related concept that goes deeper, or a next-level technique that builds on what you just explained. make it something worth coming back for, not a question they'd just nod to. it's okay to not end with anything extra if the answer is complete on its own.
 you remember everything they've said before.

CRITICAL: CURSOR FOCUS & "WHAT IS THIS" QUESTIONS
when the user says "what is this", "what does this do", "what am i looking at", "explain this", or points vaguely at something, they are ALWAYS referring to what's at or near their cursor position. you'll see a RED CIRCLE with a crosshair drawn on the screenshot showing exactly where their cursor is. look at what's inside or immediately next to that red circle. if there's a UI element, button, menu item, code, text, or anything at that spot, that's what they're asking about. the red circle is your PRIMARY reference point for vague questions.

the frontmost/active window is what they're looking at. if multiple windows are visible, prioritize the one that's in front (you'll be told which one). assume "this" refers to something in the active window near the cursor unless they explicitly mention something else.

you have a small blue triangle cursor that can fly to and point at things on screen. use it whenever pointing would genuinely help the user – if they're asking how to do something, looking for a menu, trying to find a button, or need help navigating an app, point at the relevant element. err on the side of pointing rather than not pointing, because it makes your help way more useful and concrete.
 like if the user asks a general knowledge question, or the conversation has nothing to do with what's on screen, or you'd just be pointing at something obvious they're already looking at. but if there's a specific UI element, menu, button, or area on screen that's relevant to what you're helping with, point at it.
you can include multiple [POINT:] tags – one per element you mention. place each tag immediately after the sentence that describes that element. the cursor will fly to each one in sequence while you speak. each screenshot is labeled with its pixel dimensions like "primary focus (1440x900 pixels)". use those pixel dimensions as the coordinate space. the origin (0,0) is the top-left corner of the image. x increases rightward, y increases downward.
format: [POINT:x,y:label] where x,y are integer pixel coordinates in the screenshot's pixel coordinate space, and label is a short 1-3 word description of the element (like "search bar" or "save button"). be precise – aim for the center of the element you're pointing at.
- if the screenshot doesn't seem relevant to their question, just answer the question directly.
- if the user's question relates to what's on their screen, reference specific things you see.
- if you receive multiple screen images, the one labeled "primary focus" is where the cursor is.
- you can point at anything visible on screen – buttons, menus, sidebar items, toolbar icons, text, whatever is most relevant. no restrictions on where you can point.
"""

    struct Message {
        let role: String
        let content: String
    }

    /// Anthropic-recommended resolutions for Computer Use, matched to display aspect ratio.
    private static let computerUseResolutions: [(width: Int, height: Int, aspectRatio: Double)] = [
        (1024, 768,  1024.0 / 768.0),   // 4:3   (legacy)
        (1280, 800,  1280.0 / 800.0),   // 16:10  (MacBook Air/Pro)
        (1366, 768,  1366.0 / 768.0)    // ~16:9  (external monitors)
    ]

    /// Pick the Computer Use resolution closest to the primary display's aspect ratio.
    private func bestComputerUseResolution() -> (width: Int, height: Int) {
        guard let screen = NSScreen.main else { return (1280, 800) }
        let displayAR = screen.frame.width / screen.frame.height
        let best = Self.computerUseResolutions.min(by: {
            abs($0.aspectRatio - displayAR) < abs($1.aspectRatio - displayAR)
        })!
        return (best.width, best.height)
    }

    func sendMessage(messages: [Message], screenshots: [String], screenLabels: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

                    // If calling Anthropic directly, add auth headers
                    if let apiKey = APIKeyConfig.anthropicKey {
                        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                        request.setValue("computer-use-2025-11-24", forHTTPHeaderField: "anthropic-beta")
                    }

                    // Build the messages array for the API
                    var apiMessages: [[String: Any]] = []

                    for message in messages {
                        apiMessages.append([
                            "role": message.role,
                            "content": message.content
                        ])
                    }

                    // Build the latest user message content with screenshots
                    if !screenshots.isEmpty {
                        var contentBlocks: [[String: Any]] = []

                        for (index, base64Image) in screenshots.enumerated() {
                            let label = index < screenLabels.count ? screenLabels[index] : "screen \(index + 1)"
                            contentBlocks.append([
                                "type": "text",
                                "text": "[\(label)]"
                            ])
                            contentBlocks.append([
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": "image/jpeg",
                                    "data": base64Image
                                ]
                            ])
                        }

                        // Replace last user message content with multimodal
                        if let lastMessage = apiMessages.last, lastMessage["role"] as? String == "user" {
                            let textContent = lastMessage["content"] as? String ?? ""
                            contentBlocks.append([
                                "type": "text",
                                "text": textContent
                            ])
                            apiMessages[apiMessages.count - 1] = [
                                "role": "user",
                                "content": contentBlocks
                            ]
                        }
                    }

                    // Include Computer Use tool for pixel-precise element detection
                    let resolution = self.bestComputerUseResolution()
                    let computerTool: [String: Any] = [
                        "type": "computer_20251124",
                        "name": "computer",
                        "display_width_px": resolution.width,
                        "display_height_px": resolution.height
                    ]

                    let body: [String: Any] = [
                        "model": "claude-sonnet-4-6",
                        "max_tokens": 4096,
                        "stream": true,
                        "system": self.systemPrompt,
                        "messages": apiMessages,
                        "tools": [computerTool]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let bodySize = request.httpBody?.count ?? 0
                    self.logger.info("Claude streaming request: \(bodySize) bytes, \(screenshots.count) screenshot(s), endpoint: \(self.endpoint, privacy: .public)")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 500 { break }
                        }
                        self.logger.error("Claude API HTTP \(httpResponse.statusCode): \(errorBody, privacy: .public)")
                        throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"])
                    }

                    // Parse SSE stream
                    var currentEvent = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event: ") {
                            currentEvent = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))

                            if currentEvent == "content_block_delta" {
                                if let jsonData = data.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                   let delta = json["delta"] as? [String: Any],
                                   let text = delta["text"] as? String {
                                    continuation.yield(text)
                                }
                            } else if currentEvent == "message_stop" {
                                break
                            } else if currentEvent == "error" {
                                if let jsonData = data.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                   let error = json["error"] as? [String: Any],
                                   let message = error["message"] as? String {
                                    throw NSError(domain: "ClaudeAPI", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: message])
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    self.logger.error("Claude API error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
