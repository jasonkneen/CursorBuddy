import AppKit
import SwiftUI
import Combine

// MARK: - View Model

@MainActor
final class CompanionResponseOverlayViewModel: ObservableObject {
    @Published var streamingResponseText: String = ""
    @Published var isVisible: Bool = false
    @Published var opacity: Double = 0.0

    /// The screen-space origin where the overlay should appear (near cursor).
    @Published var displayOrigin: CGPoint = .zero

    private var fadeTask: Task<Void, Never>?

    func showResponse(_ text: String, near point: CGPoint) {
        streamingResponseText = text
        displayOrigin = point
        show()
    }

    func appendText(_ text: String) {
        streamingResponseText += text
    }

    func show() {
        fadeTask?.cancel()
        isVisible = true
        withAnimation(.easeIn(duration: 0.2)) {
            opacity = 1.0
        }
    }

    func hide() {
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0.0
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            isVisible = false
            streamingResponseText = ""
        }
    }

    func clear() {
        fadeTask?.cancel()
        opacity = 0.0
        isVisible = false
        streamingResponseText = ""
    }
}

// MARK: - Overlay View

struct CompanionResponseOverlayView: View {
    @ObservedObject var viewModel: CompanionResponseOverlayViewModel

    var body: some View {
        if viewModel.isVisible {
            Text(viewModel.streamingResponseText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .frame(maxWidth: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(viewModel.opacity)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Manager

@MainActor
final class CompanionResponseOverlayManager {

    static let shared = CompanionResponseOverlayManager()

    let viewModel = CompanionResponseOverlayViewModel()

    private var panel: NSPanel?

    private init() {}

    // MARK: - Public

    func showStreamingResponse(_ text: String, near cursorLocation: CGPoint) {
        ensurePanel()
        positionPanel(near: cursorLocation)
        viewModel.showResponse(text, near: cursorLocation)
        panel?.orderFrontRegardless()
    }

    func appendStreamingText(_ text: String) {
        viewModel.appendText(text)
    }

    func dismiss() {
        viewModel.hide()
        // Allow fade-out before removing panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    func clear() {
        viewModel.clear()
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hostView = NSHostingView(
            rootView: CompanionResponseOverlayView(viewModel: viewModel)
        )
        panel.contentView = hostView

        self.panel = panel
    }

    private func positionPanel(near point: CGPoint) {
        guard let panel = panel, let screen = NSScreen.main else { return }

        // Position the overlay slightly below-right of the cursor
        let offset = CGPoint(x: 20, y: -30)
        var origin = CGPoint(
            x: point.x + offset.x,
            y: point.y + offset.y - 200  // NSWindow origin is bottom-left
        )

        // Keep on screen
        let screenFrame = screen.visibleFrame
        if origin.x + 380 > screenFrame.maxX {
            origin.x = point.x - 400
        }
        if origin.y < screenFrame.minY {
            origin.y = screenFrame.minY
        }

        panel.setFrameOrigin(origin)
    }
}
