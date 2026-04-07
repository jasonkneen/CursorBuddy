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

    private var navigationAnimationTimer: Timer?
    private var animationStartTime: Date = .now
    private var animationDuration: TimeInterval = 0.6
    private var animationTarget: CGPoint = .zero

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
        animationDuration = 0.6

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
        let rawProgress = min(elapsed / animationDuration, 1.0)

        // Ease-out cubic
        let t = 1.0 - pow(1.0 - rawProgress, 3)

        let startPos = cursorPositionWhenNavigationStarted
        let endPos = animationTarget

        cursorPosition = CGPoint(
            x: startPos.x + (endPos.x - startPos.x) * t,
            y: startPos.y + (endPos.y - startPos.y) * t
        )

        // Scale effect during flight
        if t < 0.5 {
            buddyFlightScale = 1.0 + 0.15 * (t * 2)
        } else {
            buddyFlightScale = 1.15 - 0.15 * ((t - 0.5) * 2)
        }

        // Animation complete
        if rawProgress >= 1.0 {
            stopFlightAnimation()
            cursorPosition = endPos
            buddyFlightScale = 1.0

            if isReturningToCursor {
                // Done returning — go back to mouse-follow mode
                isNavigating = false
                isReturningToCursor = false
            } else {
                // Show bubble at target
                showBubbleAtTarget()
            }
        }
    }

    private func showBubbleAtTarget() {
        guard let label = detectedElementBubbleText, !label.isEmpty else { return }

        navigationBubbleText = label

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            navigationBubbleOpacity = 1.0
            navigationBubbleScale = 1.0
            bubbleOpacity = 1.0
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
