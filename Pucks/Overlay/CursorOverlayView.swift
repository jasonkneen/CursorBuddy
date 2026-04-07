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
                            // Pulsing dot
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .modifier(PulseModifier())
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
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.black.opacity(0.45)))
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
                    .position(x: pos.x + 50, y: pos.y - 10)
                    .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: pos)
                }

                // ── Suggestion chip when text is selected ──
                if !detector.isNavigating &&
                    voiceState.state != .listening &&
                    voiceState.state != .thinking &&
                    selectedTextMonitor.hasSelection {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Suggest")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            Text("Use \(shortcutConfig.label)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.72))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.35))
                                )
                        )

                        Text(selectionPreviewText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 220, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    }
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    .position(x: pos.x + 118, y: pos.y + 22)
                } else if voiceState.state != .listening && voiceState.state != .thinking {
                    let cursorW: CGFloat = 20
                    let cursorH: CGFloat = 28
                    let iconSize: CGFloat = 20
                    let idleAnchorOffset = CGPoint(x: 28, y: 8)
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
                        .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: tipPos)
                }

                // ── Label bubble at target ──
                if detector.navigationBubbleOpacity > 0,
                   let targetPoint = detector.detectedElementScreenLocation {
                    Text(detector.navigationBubbleText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.85))
                        )
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
    var selectionPreviewText: String {
        let normalized = selectedTextMonitor.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count > 120 {
            return "\"\(normalized.prefix(117))...\""
        }

        return "\"\(normalized)\""
    }

    var cursorAnchorSize: CGSize {
        switch cursorAppearance.style {
        case .arrow:
            return CGSize(width: 20, height: 28)
        case .dot, .target, .ring, .diamond:
            return CGSize(width: 20, height: 20)
        }
    }

    @ViewBuilder
    func cursorSymbolView(cursorW: CGFloat, cursorH: CGFloat, iconSize: CGFloat) -> some View {
        switch cursorAppearance.style {
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

// MARK: - Voice State Observable (bridge from CompanionVoiceState)

@MainActor
class VoiceStateObservable: ObservableObject {
    @Published var state: CompanionVoiceState = .idle
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
