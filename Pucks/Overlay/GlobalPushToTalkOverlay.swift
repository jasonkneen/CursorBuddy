import AppKit
import SwiftUI
import Combine

// MARK: - Overlay Mode

enum PushToTalkOverlayMode: Equatable {
    case hidden
    case recording
    case processing
}

// MARK: - View Model

@MainActor
private final class GlobalPushToTalkOverlayViewModel: ObservableObject {
    @Published var overlayMode: PushToTalkOverlayMode = .hidden
    @Published var pulseScale: CGFloat = 1.0
    @Published var pulseOpacity: Double = 0.6

    private var pulseTimer: Timer?

    var isRecording: Bool { overlayMode == .recording }
    var isProcessing: Bool { overlayMode == .processing }

    func startRecording() {
        overlayMode = .recording
        startPulse()
    }

    func startProcessing() {
        overlayMode = .processing
        stopPulse()
    }

    func hide() {
        overlayMode = .hidden
        stopPulse()
    }

    private func startPulse() {
        pulseScale = 1.0
        pulseOpacity = 0.6
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording else { return }
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.pulseScale = self.pulseScale > 1.15 ? 1.0 : 1.2
                    self.pulseOpacity = self.pulseOpacity > 0.5 ? 0.3 : 0.7
                }
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseScale = 1.0
        pulseOpacity = 0.6
    }
}

// MARK: - Overlay View

private struct GlobalPushToTalkOverlayView: View {
    @ObservedObject var viewModel: GlobalPushToTalkOverlayViewModel

    var body: some View {
        if viewModel.overlayMode != .hidden {
            VStack(spacing: 8) {
                ZStack {
                    // Pulsing background circle
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.orange)
                        .frame(width: 48, height: 48)
                        .scaleEffect(viewModel.pulseScale)
                        .opacity(viewModel.pulseOpacity)

                    // Icon
                    Image(systemName: viewModel.isRecording ? "mic.fill" : "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(viewModel.isRecording ? "Listening…" : "Processing…")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Manager

@MainActor
final class GlobalPushToTalkOverlayManager {

    static let shared = GlobalPushToTalkOverlayManager()

    private let viewModel = GlobalPushToTalkOverlayViewModel()
    private var panel: NSPanel?

    var overlayMode: PushToTalkOverlayMode {
        get { viewModel.overlayMode }
        set {
            switch newValue {
            case .hidden:
                viewModel.hide()
                panel?.orderOut(nil)
            case .recording:
                ensurePanel()
                positionPanel()
                viewModel.startRecording()
                panel?.orderFrontRegardless()
            case .processing:
                viewModel.startProcessing()
            }
        }
    }

    init() {}

    // MARK: - Public

    func show(mode: PushToTalkOverlayMode) {
        overlayMode = mode
    }

    func showRecording() {
        overlayMode = .recording
    }

    func showProcessing() {
        overlayMode = .processing
    }

    func hide() {
        overlayMode = .hidden
    }

    // MARK: - Private

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hostView = NSHostingView(
            rootView: GlobalPushToTalkOverlayView(viewModel: viewModel)
        )
        panel.contentView = hostView

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        // Center horizontally, near the top of the screen
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 60
        let y = screenFrame.maxY - 140
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }
}
