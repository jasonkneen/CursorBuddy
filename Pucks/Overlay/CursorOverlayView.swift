import SwiftUI
import Combine

/// The blue triangle cursor buddy and label bubble rendered on the transparent overlay.
/// The cursor follows the mouse at all times and flies to [POINT:] targets.
/// When listening, it shows a "Listening..." chip instead of the triangle.
struct CursorOverlayView: View {
    @ObservedObject var detector: ElementLocationDetector
    @ObservedObject var voiceState: VoiceStateObservable
    @ObservedObject var selectedTextMonitor: SelectedTextMonitor
    @ObservedObject var cursorAppearance = CursorAppearanceConfiguration.shared
    @ObservedObject var shortcutConfig = PushToTalkShortcutConfiguration.shared
    @StateObject private var mouseTracker = MouseTracker()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let pos = detector.isNavigating
                    ? detector.cursorPosition
                    : mouseTracker.screenPosition(in: geo)

                // ── Listening/Processing chip (replaces cursor when active) ──
                if voiceState.state == .listening || voiceState.state == .thinking {
                    HStack(spacing: 6) {
                        if voiceState.state == .listening {
                            AudioWaveformView(levels: voiceState.audioLevels)
                                .frame(width: 48, height: 16)
                            Text("Listening...")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("Thinking...")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    .position(x: pos.x + 50, y: pos.y - 10)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: pos)
                }

                // ── Suggestion chip when text is selected ──
                if !detector.isNavigating &&
                    voiceState.state != .listening &&
                    voiceState.state != .thinking &&
                    selectedTextMonitor.hasSelection {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Hold \(shortcutConfig.label) and speak")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(Color.blue.opacity(0.15))
                            .glassEffect(.regular)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    .position(x: pos.x + 90, y: pos.y + 12)
                } else if voiceState.state != .listening && voiceState.state != .thinking {
                    let cursorW: CGFloat = 20
                    let cursorH: CGFloat = 28
                    let iconSize: CGFloat = 20
                    let d = cursorAppearance.distance
                    let idleAnchorOffset = CGPoint(x: d, y: d * 0.7)
                    // When navigating, place the arrow tip on the target and leave it there.
                    let tipPos = detector.isNavigating
                        ? CGPoint(x: pos.x + cursorW / 2, y: pos.y + cursorH / 2)
                        : CGPoint(
                            x: pos.x + idleAnchorOffset.x + cursorAnchorSize.width / 2,
                            y: pos.y + idleAnchorOffset.y + cursorAnchorSize.height / 2
                        )

                    cursorSymbolView(cursorW: cursorW, cursorH: cursorH, iconSize: iconSize)
                        .position(tipPos)
                        .opacity(detector.isNavigating ? 1.0 : 0.88)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: tipPos)
                }

                // ── Label bubble at target ──
                if detector.navigationBubbleOpacity > 0,
                   let targetPoint = detector.detectedElementScreenLocation {
                    Text(detector.navigationBubbleText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.2))
                                .glassEffect(.regular)
                        }
                        // Position bubble above the cursor target
                        .position(x: targetPoint.x, y: targetPoint.y - 28)
                        .scaleEffect(detector.navigationBubbleScale)
                        .opacity(detector.navigationBubbleOpacity)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension CursorOverlayView {
    var cursorAnchorSize: CGSize {
        switch cursorAppearance.style {
        case .triangle:
            return CGSize(width: 16, height: 16)
        case .arrow:
            return CGSize(width: 20, height: 28)
        case .dot, .target, .ring, .diamond:
            return CGSize(width: 20, height: 20)
        }
    }

    @ViewBuilder
    func cursorSymbolView(cursorW: CGFloat, cursorH: CGFloat, iconSize: CGFloat) -> some View {
        switch cursorAppearance.style {
        case .triangle:
            TriangleCursorShape()
                .fill(Color(red: 0.2, green: 0.5, blue: 1.0))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(
                    detector.isNavigating
                        ? detector.triangleRotationDegrees
                        : -35
                ))
                .scaleEffect(detector.buddyFlightScale * cursorAppearance.scale)
                .shadow(color: Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.6), radius: 8 + (detector.buddyFlightScale - 1.0) * 20, x: 0, y: 0)
        case .arrow:
            BlueCursorTriangle()
                .frame(width: cursorW, height: cursorH)
                .rotationEffect(.degrees(
                    detector.isNavigating
                        ? detector.triangleRotationDegrees
                        : -12
                ))
                .scaleEffect(detector.buddyFlightScale * cursorAppearance.scale)
                .shadow(color: .blue.opacity(0.5), radius: 6, x: 0, y: 2)
        case .dot:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.23, green: 0.56, blue: 0.99), Color(red: 0.08, green: 0.38, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: iconSize, height: iconSize)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                .shadow(color: .blue.opacity(0.45), radius: 6, x: 0, y: 2)
                .scaleEffect(detector.buddyFlightScale * cursorAppearance.scale)
        case .target:
            TargetCursorView()
                .frame(width: iconSize + 6, height: iconSize + 6)
                .shadow(color: .blue.opacity(0.35), radius: 6, x: 0, y: 2)
                .scaleEffect(detector.buddyFlightScale * cursorAppearance.scale)
        case .ring:
            RingCursorView()
                .frame(width: iconSize + 4, height: iconSize + 4)
                .shadow(color: .blue.opacity(0.35), radius: 6, x: 0, y: 2)
                .scaleEffect(detector.buddyFlightScale * cursorAppearance.scale)
        case .diamond:
            DiamondCursorView()
                .frame(width: iconSize + 4, height: iconSize + 4)
                .shadow(color: .blue.opacity(0.4), radius: 6, x: 0, y: 2)
                .scaleEffect(detector.buddyFlightScale * cursorAppearance.scale)
        }
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Audio Waveform View

/// A mini waveform that reacts to live audio power levels.
/// Renders vertical bars that scale based on incoming audio amplitude.
struct AudioWaveformView: View {
    let levels: [Float]

    /// Number of bars to display.
    private let barCount = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = sampleLevel(at: index)
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: level))
                    .frame(width: 2, height: barHeight(for: level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }

    /// Map bar index to a level from the rolling buffer.
    private func sampleLevel(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0.05 }
        // Map barCount indices across the available levels
        let fraction = Float(index) / Float(max(barCount - 1, 1))
        let sampleIndex = Int(fraction * Float(levels.count - 1))
        return levels[min(sampleIndex, levels.count - 1)]
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minH: CGFloat = 2
        let maxH: CGFloat = 16
        return minH + CGFloat(level) * (maxH - minH)
    }

    private func barColor(for level: Float) -> Color {
        // Gradient from white to red as level increases
        let t = Double(min(level * 1.5, 1.0))
        return Color(
            red: 1.0,
            green: 1.0 - t * 0.6,
            blue: 1.0 - t * 0.7
        )
    }
}

// MARK: - Voice State Observable (bridge from CompanionVoiceState)

@MainActor
class VoiceStateObservable: ObservableObject {
    @Published var state: CompanionVoiceState = .idle

    /// Rolling window of recent audio power levels (0…1) for waveform display.
    @Published var audioLevels: [Float] = []

    /// Maximum number of bars in the waveform.
    private let maxBars = 28

    /// Push a new audio power sample into the rolling buffer.
    func pushAudioLevel(_ level: Float) {
        audioLevels.append(level)
        if audioLevels.count > maxBars {
            audioLevels.removeFirst(audioLevels.count - maxBars)
        }
    }

    /// Clear the waveform when recording stops.
    func clearAudioLevels() {
        audioLevels.removeAll()
    }
}

// MARK: - Mouse Tracker

@MainActor
final class MouseTracker: ObservableObject {
    @Published var mouseLocation: CGPoint = .zero
    private var timer: Timer?

    init() {
        mouseLocation = NSEvent.mouseLocation
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mouseLocation = NSEvent.mouseLocation
            }
        }
    }

    deinit { timer?.invalidate() }

    func screenPosition(in geo: GeometryProxy) -> CGPoint {
        // Find the screen containing the cursor. Fall back to main if not found.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else {
            return CGPoint(x: mouseLocation.x, y: mouseLocation.y)
        }
        // Convert global AppKit coords (y=0 at bottom) to the overlay window's local space (y=0 at top).
        let localX = mouseLocation.x - screen.frame.minX
        let localY = screen.frame.maxY - mouseLocation.y
        return CGPoint(x: localX, y: localY)
    }
}

// MARK: - Pucks Cursor

/// A sharper macOS-style pointer arrow with a blue gradient fill.
/// The tip is at the top-left (0,0) of the frame.
struct BlueCursorTriangle: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: 0))
            arrow.addLine(to: CGPoint(x: w * 0.08, y: h * 0.80))
            arrow.addLine(to: CGPoint(x: w * 0.27, y: h * 0.64))
            arrow.addLine(to: CGPoint(x: w * 0.39, y: h * 0.96))
            arrow.addLine(to: CGPoint(x: w * 0.55, y: h * 0.89))
            arrow.addLine(to: CGPoint(x: w * 0.43, y: h * 0.58))
            arrow.addLine(to: CGPoint(x: w * 0.78, y: h * 0.54))
            arrow.closeSubpath()

            context.stroke(
                arrow,
                with: .color(.white),
                lineWidth: 2.0
            )

            context.fill(arrow, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.23, green: 0.56, blue: 0.99),
                    Color(red: 0.08, green: 0.38, blue: 0.94),
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: w, y: h)
            ))

            var highlight = Path()
            highlight.move(to: CGPoint(x: w * 0.06, y: h * 0.08))
            highlight.addLine(to: CGPoint(x: w * 0.13, y: h * 0.63))
            context.stroke(
                highlight,
                with: .color(.white.opacity(0.4)),
                lineWidth: 1.0
            )

            var innerEdge = Path()
            innerEdge.move(to: CGPoint(x: w * 0.18, y: h * 0.18))
            innerEdge.addLine(to: CGPoint(x: w * 0.27, y: h * 0.57))
            innerEdge.addLine(to: CGPoint(x: w * 0.56, y: h * 0.53))
            context.stroke(
                innerEdge,
                with: .color(.black.opacity(0.18)),
                lineWidth: 1.0
            )
        }
    }
}

struct TargetCursorView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.96), lineWidth: 1.5)
            Circle()
                .stroke(Color(red: 0.12, green: 0.46, blue: 0.98), lineWidth: 3)
                .padding(1)
            Circle()
                .fill(Color(red: 0.19, green: 0.56, blue: 0.99))
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 1.5, height: 16)
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 16, height: 1.5)
            Circle()
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
                .padding(0.5)
        }
    }
}

struct RingCursorView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 2)
            Circle()
                .stroke(Color(red: 0.18, green: 0.54, blue: 0.99), lineWidth: 5)
                .padding(2)
        }
    }
}

struct DiamondCursorView: View {
    var body: some View {
        DiamondShape()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.23, green: 0.56, blue: 0.99), Color(red: 0.08, green: 0.38, blue: 0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                DiamondShape()
                    .stroke(Color.white.opacity(0.95), lineWidth: 2)
            )
    }
}

/// Equilateral triangle cursor ported from clicky/sticky.
struct TriangleCursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0

        // Top vertex
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - height / 1.5))
        // Bottom left vertex
        path.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        // Bottom right vertex
        path.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
