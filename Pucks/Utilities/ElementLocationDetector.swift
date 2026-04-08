import AppKit
import SwiftUI
import Combine

/// Parses `[POINT:x,y:label]` or `[POINT:none]` from Claude's response text
/// and drives a smooth cursor-flight animation to the detected coordinates.
@MainActor
final class ElementLocationDetector: ObservableObject {

    // MARK: - Regex

    /// Matches any `[POINT:none]` or `[POINT:123,456:Some Label]` tag anywhere in a string.
    private static let pointRegex = try! NSRegularExpression(
        pattern: #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]]+))?)\]"#,
        options: []
    )

    // MARK: - Published cursor state

    @Published var cursorPosition: CGPoint = .zero
    @Published var cursorOpacity: CGFloat = 0.0
    @Published var triangleRotationDegrees: CGFloat = 0.0
    @Published var buddyFlightScale: CGFloat = 1.0

    // MARK: - Detected element

    @Published var detectedElementScreenLocation: CGPoint?
    @Published var detectedElementBubbleText: String?
    @Published var detectedElementDisplayFrame: CGRect?

    // MARK: - Navigation bubble

    @Published var navigationBubbleText: String = ""
    @Published var navigationBubbleOpacity: Double = 0.0
    @Published var navigationBubbleScale: CGFloat = 0.5
    @Published var navigationBubbleSize: CGSize = .zero

    // MARK: - Element label bubble

    @Published var bubbleOpacity: Double = 0.0
    @Published var bubbleSize: CGSize = .zero

    // MARK: - Animation state

    @Published var isNavigating: Bool = false

    var cursorPositionWhenNavigationStarted: CGPoint = .zero
    var isReturningToCursor: Bool = false

    private var bubbleStreamingTask: Task<Void, Never>?
    private var navigationAnimationTimer: Timer?
    private var animationStartTime: Date = .now
    private var animationDuration: TimeInterval = 0.6
    private var animationTarget: CGPoint = .zero
    private var bezierControlPoint: CGPoint = .zero

    // MARK: - Public API

    /// Parses the response text for all `[POINT:...]` tags and returns
    /// the cleaned text (all tags removed) plus every extracted location in order.
    struct ParsedResult {
        let cleanedText: String
        let points: [(point: CGPoint, label: String?)]

        /// Convenience: first point (backward compat).
        var point: CGPoint? { points.first?.point }
        var label: String? { points.first?.label }
    }

    func parse(responseText: String) -> ParsedResult {
        let nsString = responseText as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = Self.pointRegex.matches(in: responseText, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return ParsedResult(cleanedText: responseText, points: [])
        }

        // Collect all points and remove all tags from the text (iterate in reverse to preserve ranges).
        var mutable = responseText
        var collected: [(point: CGPoint, label: String?)] = []

        for match in matches.reversed() {
            let xRange = match.range(at: 1)
            let yRange = match.range(at: 2)

            if xRange.location != NSNotFound, yRange.location != NSNotFound,
               let x = Int(nsString.substring(with: xRange)),
               let y = Int(nsString.substring(with: yRange)) {
                let label: String? = match.range(at: 3).location != NSNotFound
                    ? nsString.substring(with: match.range(at: 3))
                    : nil
                collected.insert((CGPoint(x: x, y: y), label), at: 0)
            }
            // Remove the tag from the text regardless of whether it's [POINT:none] or a coordinate
            if let range = Range(match.range, in: mutable) {
                mutable.replaceSubrange(range, with: "")
            }
        }

        // Clean up any double-spaces or leading/trailing whitespace left by removals
        let cleaned = mutable
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collected.isEmpty {
            // All tags were [POINT:none] — reset
            resetDetection()
        }

        return ParsedResult(cleanedText: cleaned, points: collected)
    }

    /// Drives the cursor animation to the given screen point.
    func navigateTo(point: CGPoint, label: String? = nil) {
        detectedElementScreenLocation = point
        detectedElementBubbleText = label

        // Start flying from current position
        cursorPositionWhenNavigationStarted = cursorPosition
        animationTarget = point
        isReturningToCursor = false

        // Show cursor in navigation mode
        isNavigating = true
        cursorOpacity = 1.0
        buddyFlightScale = 1.0

        // Compute rotation toward target
        let dx = point.x - cursorPosition.x
        let dy = point.y - cursorPosition.y
        triangleRotationDegrees = atan2(dy, dx) * 180 / .pi + 90

        // Set up bubble text
        if let label = label {
            navigationBubbleText = label
        }

        startFlightAnimation()
    }

    /// Animates the cursor back to the real mouse location and fades out.
    func returnToCursor() {
        let mouseLocation = NSEvent.mouseLocation
        // Use the screen actually containing the cursor, not always the main screen.
        // Coordinates must be in the overlay's local space (origin at top-left of that screen).
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }

        let target = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: screen.frame.maxY - mouseLocation.y
        )

        cursorPositionWhenNavigationStarted = cursorPosition
        animationTarget = target
        isReturningToCursor = true

        startFlightAnimation()
    }

    /// Resets all detection state.
    func resetDetection() {
        stopFlightAnimation()
        bubbleStreamingTask?.cancel()
        bubbleStreamingTask = nil
        isNavigating = false
        detectedElementScreenLocation = nil
        detectedElementBubbleText = nil
        detectedElementDisplayFrame = nil
        cursorOpacity = 0.0
        navigationBubbleOpacity = 0.0
        navigationBubbleScale = 0.5
        bubbleOpacity = 0.0
        isReturningToCursor = false
    }

    // MARK: - Animation Engine

    private func startFlightAnimation() {
        stopFlightAnimation()

        animationStartTime = .now

        // Distance-based duration (0.6s – 1.4s), matching clicky
        let startPos = cursorPositionWhenNavigationStarted
        let endPos = animationTarget
        let dx = endPos.x - startPos.x
        let dy = endPos.y - startPos.y
        let distance = sqrt(dx * dx + dy * dy)
        animationDuration = min(max(distance / 800.0, 0.6), 1.4)

        // Compute bezier control point for arc (perpendicular to flight line)
        let midX = (startPos.x + endPos.x) / 2.0
        let midY = (startPos.y + endPos.y) / 2.0
        let arcHeight = min(distance * 0.2, 80.0)
        // Perpendicular offset for the arc
        let norm = distance > 0 ? 1.0 / distance : 0
        let perpX = -(dy) * norm
        let perpY = dx * norm
        bezierControlPoint = CGPoint(
            x: midX + perpX * arcHeight,
            y: midY + perpY * arcHeight
        )

        // Dismiss existing bubbles during flight
        navigationBubbleOpacity = 0.0
        bubbleOpacity = 0.0

        navigationAnimationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickFlightAnimation()
            }
        }
    }

    private func stopFlightAnimation() {
        navigationAnimationTimer?.invalidate()
        navigationAnimationTimer = nil
    }

    private func tickFlightAnimation() {
        let elapsed = Date.now.timeIntervalSince(animationStartTime)
        let linearProgress = min(elapsed / animationDuration, 1.0)

        // Smoothstep easing (Hermite interpolation): 3t² - 2t³
        let t = linearProgress * linearProgress * (3.0 - 2.0 * linearProgress)

        let startPos = cursorPositionWhenNavigationStarted
        let endPos = animationTarget
        let cp = bezierControlPoint

        // Quadratic bezier: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
        let oneMinusT = 1.0 - t
        let bezierX = oneMinusT * oneMinusT * startPos.x
                     + 2.0 * oneMinusT * t * cp.x
                     + t * t * endPos.x
        let bezierY = oneMinusT * oneMinusT * startPos.y
                     + 2.0 * oneMinusT * t * cp.y
                     + t * t * endPos.y

        cursorPosition = CGPoint(x: bezierX, y: bezierY)

        // Rotation follows bezier tangent
        let tangentX = 2.0 * (1.0 - t) * (cp.x - startPos.x) + 2.0 * t * (endPos.x - cp.x)
        let tangentY = 2.0 * (1.0 - t) * (cp.y - startPos.y) + 2.0 * t * (endPos.y - cp.y)
        triangleRotationDegrees = atan2(tangentY, tangentX) * 180.0 / .pi + 90.0

        // Scale pulse: grows to 1.3x at midpoint, back to 1.0 at landing
        buddyFlightScale = 1.0 + sin(linearProgress * .pi) * 0.3

        // Animation complete
        if linearProgress >= 1.0 {
            stopFlightAnimation()
            cursorPosition = endPos
            buddyFlightScale = 1.0

            if isReturningToCursor {
                isNavigating = false
                isReturningToCursor = false
                triangleRotationDegrees = -35.0
            } else {
                showBubbleAtTarget()
            }
        }
    }

    private func showBubbleAtTarget() {
        guard let label = detectedElementBubbleText, !label.isEmpty else { return }

        // Start with empty text — will stream character by character
        navigationBubbleText = ""

        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            navigationBubbleOpacity = 1.0
            navigationBubbleScale = 1.0
            bubbleOpacity = 1.0
        }

        // Stream characters with 30-60ms random delays (matching clicky)
        bubbleStreamingTask?.cancel()
        bubbleStreamingTask = Task { @MainActor in
            for char in label {
                if Task.isCancelled { break }
                navigationBubbleText.append(char)
                let delay = Double.random(in: 0.03...0.06)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // Compute display frame around the detected element
        if let point = detectedElementScreenLocation {
            let bubbleWidth: CGFloat = CGFloat(label.count * 9 + 24)
            let bubbleHeight: CGFloat = 32
            detectedElementDisplayFrame = CGRect(
                x: point.x - bubbleWidth / 2,
                y: point.y - bubbleHeight - 8,
                width: bubbleWidth,
                height: bubbleHeight
            )
            navigationBubbleSize = CGSize(width: bubbleWidth, height: bubbleHeight)
            bubbleSize = navigationBubbleSize
        }
    }
}
