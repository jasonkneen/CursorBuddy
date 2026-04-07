import SwiftUI
import AppKit

// MARK: - FloatingSessionButtonManager

@MainActor
class FloatingSessionButtonManager: ObservableObject {

    // MARK: - Properties

    @Published var isVisible: Bool = false
    private(set) var floatingButtonPanel: NSPanel?
    var onFloatingButtonClicked: (() -> Void)?

    private let buttonSize: CGFloat = 56
    private let margin: CGFloat = 16

    // MARK: - Panel Lifecycle

    func showFloatingButton() {
        if floatingButtonPanel != nil {
            floatingButtonPanel?.orderFront(nil)
            isVisible = true
            return
        }

        guard let screen = NSScreen.main else { return }

        let panelRect = NSRect(
            x: screen.visibleFrame.maxX - buttonSize - margin,
            y: screen.visibleFrame.maxY - buttonSize - margin,
            width: buttonSize,
            height: buttonSize
        )

        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let buttonView = FloatingButtonView { [weak self] in
            self?.onFloatingButtonClicked?()
        }

        let hostingView = NSHostingView(rootView: buttonView)
        hostingView.frame = NSRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        panel.contentView = hostingView

        panel.orderFront(nil)
        self.floatingButtonPanel = panel
        self.isVisible = true

        print("[FloatingSessionButton] Floating button shown.")
    }

    func hideFloatingButton() {
        floatingButtonPanel?.orderOut(nil)
        isVisible = false
        print("[FloatingSessionButton] Floating button hidden.")
    }

    func destroyFloatingButton() {
        floatingButtonPanel?.close()
        floatingButtonPanel = nil
        isVisible = false
        print("[FloatingSessionButton] Floating button destroyed.")
    }
}

// MARK: - FloatingButtonView

struct FloatingButtonView: View {
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
            .scaleEffect(isHovering ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.glassProminent)
        .tint(.blue)
        .shadow(
            color: isHovering ? Color.blue.opacity(0.45) : Color.blue.opacity(0.22),
            radius: isHovering ? 12 : 6,
            y: 2
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
