import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreImage

// MARK: - Lens Configuration

@MainActor
final class LensConfiguration: ObservableObject {
    static let shared = LensConfiguration()

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "lensEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "lensEnabled") }
    }
    @Published var magnification: CGFloat = UserDefaults.standard.double(forKey: "lensMagnification").clamped(1.2, 4.0) {
        didSet { UserDefaults.standard.set(magnification, forKey: "lensMagnification") }
    }
    @Published var diameter: CGFloat = UserDefaults.standard.double(forKey: "lensDiameter").clamped(20, 500) {
        didSet { UserDefaults.standard.set(diameter, forKey: "lensDiameter") }
    }
    @Published var glassTintAmount: CGFloat = UserDefaults.standard.double(forKey: "lensGlassTintAmount").clamped(0.0, 1.0) {
        didSet { UserDefaults.standard.set(glassTintAmount, forKey: "lensGlassTintAmount") }
    }
    @Published var glassTintRed: Double = UserDefaults.standard.object(forKey: "lensGlassTintRed") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(glassTintRed, forKey: "lensGlassTintRed") }
    }
    @Published var glassTintGreen: Double = UserDefaults.standard.object(forKey: "lensGlassTintGreen") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(glassTintGreen, forKey: "lensGlassTintGreen") }
    }
    @Published var glassTintBlue: Double = UserDefaults.standard.object(forKey: "lensGlassTintBlue") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(glassTintBlue, forKey: "lensGlassTintBlue") }
    }

    /// When true, the glass effect is fully transparent (just magnification)
    var isTransparent: Bool { glassTintAmount < 0.01 }

    var normalizedGlassTintAmount: CGFloat {
        min(max(glassTintAmount, 0.0), 1.0)
    }

    var glassTint: Color {
        Color(
            red: glassTintRed.clamped(0.0, 1.0),
            green: glassTintGreen.clamped(0.0, 1.0),
            blue: glassTintBlue.clamped(0.0, 1.0)
        )
    }

    private init() {
        // Defaults if never set
        if magnification < 1.2 { magnification = 2.0 }
        if diameter < 20 { diameter = 20 }
        if UserDefaults.standard.object(forKey: "lensGlassTintAmount") == nil {
            let legacyOpacity = UserDefaults.standard.double(forKey: "lensGlassOpacity")
            glassTintAmount = legacyOpacity > 0 ? legacyOpacity : 0.3
        } else if glassTintAmount > 1.0 {
            glassTintAmount = glassTintAmount / 100.0
        }
    }

    func setGlassTint(_ color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        glassTintRed = Double(nsColor.redComponent)
        glassTintGreen = Double(nsColor.greenComponent)
        glassTintBlue = Double(nsColor.blueComponent)
    }
}

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double {
        max(low, min(high, self))
    }
}

// MARK: - Lens Overlay View (macOS 26 Liquid Glass)

struct LensOverlayView: View {
    @ObservedObject var config: LensConfiguration
    @StateObject private var capturer = LensCapturer()

    var body: some View {
        let d = config.diameter
        ZStack {
            // Magnified content rendered as background of the glass
            if let image = capturer.magnifiedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: d, height: d)
                    .clipShape(Circle())
                    .saturation(0.92)
                    .brightness(-0.02)
            }

            // Stable liquid-glass shell. Keep the body consistent and treat tint as a subtle accent only.
            Circle()
                .fill(.clear)
                .frame(width: d, height: d)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.96)
                }
                .glassEffect(.regular)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.22),
                                    Color.clear,
                                    Color.black.opacity(0.10)
                                ],
                                startPoint: .bottomTrailing,
                                endPoint: .topLeading
                            )
                        )
                }
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    .white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: d * 0.045)
                        .mask(
                            Circle()
                                .scale(0.96)
                                .offset(x: -d * 0.08, y: -d * 0.10)
                        )
                }
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.16)
                                ],
                                center: .center,
                                startRadius: d * 0.18,
                                endRadius: d * 0.56
                            )
                        )
                }
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.44),
                                    .white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: d * 0.46, height: d * 0.24)
                        .blur(radius: d * 0.03)
                        .offset(x: d * 0.12, y: d * 0.10)
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.24), lineWidth: d > 60 ? 1.2 : 0.8)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.22), lineWidth: d > 60 ? 1.8 : 1.0)
                        .padding(1)
                }

            if !config.isTransparent {
                let tintStrength = config.normalizedGlassTintAmount
                let tintColor = config.glassTint

                Circle()
                    .fill(tintColor.opacity(tintStrength * 0.035))
                    .frame(width: d, height: d)
                    .overlay {
                        Circle()
                            .fill(tintColor.opacity(tintStrength * 0.045))
                            .blendMode(.plusLighter)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(tintColor.opacity(tintStrength * 0.10), lineWidth: d > 60 ? 1.0 : 0.6)
                    }
            }

            // Subtle highlight ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: d > 60 ? 1.5 : 0.75
                )
                .frame(width: d, height: d)

            // Center dot (only visible when lens is big enough)
            if d > 60 {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(width: d, height: d)
        .onAppear {
            capturer.magnification = config.magnification
            capturer.diameter = config.diameter
            capturer.startCapturing()
        }
        .onDisappear {
            capturer.stopCapturing()
        }
        .onChange(of: config.magnification) { _, newVal in
            capturer.magnification = newVal
        }
        .onChange(of: config.diameter) { _, newVal in
            capturer.diameter = newVal
        }
    }
}

// MARK: - Lens Capturer — grabs the region under the lens and magnifies it

@MainActor
final class LensCapturer: ObservableObject {
    @Published var magnifiedImage: NSImage?

    var magnification: CGFloat = 2.0
    var diameter: CGFloat = 250
    private var timer: Timer?

    func startCapturing() {
        // Capture at 15fps for smooth lens without hammering the GPU
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureUnderCursor()
            }
        }
    }

    func stopCapturing() {
        timer?.invalidate()
        timer = nil
        magnifiedImage = nil
    }

    private func captureUnderCursor() async {
        let cursorPos = CGEvent(source: nil)?.location ?? .zero

        // The source region size (what we'll magnify)
        let sourceRadius = diameter / (2.0 * magnification)

        // Find which display the cursor is on
        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var matchingDisplays = [CGDirectDisplayID](repeating: 0, count: 1)
        var displayCount: UInt32 = 0
        if CGGetDisplaysWithPoint(cursorPos, 1, &matchingDisplays, &displayCount) == .success, displayCount > 0 {
            displayID = matchingDisplays[0]
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }

            // Exclude our own app windows from the lens capture
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let excludedWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }

            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

            // Capture the full display at a small size for performance
            let captureSize = Int(sourceRadius * 4)  // enough resolution
            let config = SCStreamConfiguration()
            config.width = max(captureSize, 100)
            config.height = max(captureSize, 100)
            config.showsCursor = false

            // We want to capture just the region around the cursor
            // SCStreamConfiguration has sourceRect for this
            let displayBounds = CGDisplayBounds(displayID)
            config.sourceRect = CGRect(
                x: cursorPos.x - sourceRadius - displayBounds.origin.x,
                y: cursorPos.y - sourceRadius - displayBounds.origin.y,
                width: sourceRadius * 2,
                height: sourceRadius * 2
            )

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: diameter, height: diameter))
            self.magnifiedImage = nsImage
        } catch {
            // Silently fail — lens just shows glass without content
        }
    }
}

// MARK: - Lens Window Manager

@MainActor
final class LensWindowManager {
    static let shared = LensWindowManager()

    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private let config = LensConfiguration.shared

    private init() {}

    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }

        let size = config.diameter + 20
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // The hosting view must also be transparent for glass to see through
        let hostView = NSHostingView(
            rootView: GlassEffectContainer {
                LensOverlayView(config: config)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = .clear
        panel.contentView = hostView

        self.panel = panel
        panel.orderFrontRegardless()

        // Track cursor position
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePosition()
            }
        }
    }

    func hide() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    var isVisible: Bool {
        panel != nil
    }

    func toggle() {
        if isVisible {
            hide()
            config.isEnabled = false
        } else {
            show()
            config.isEnabled = true
        }
    }

    private func updatePosition() {
        guard let panel = panel else { return }

        let mouseLocation = NSEvent.mouseLocation  // bottom-left origin
        let halfSize = config.diameter / 2 + 10

        // Offset the lens slightly so cursor isn't dead center (more natural)
        let origin = CGPoint(
            x: mouseLocation.x - halfSize,
            y: mouseLocation.y - halfSize
        )
        panel.setFrameOrigin(origin)

        // Resize if diameter changed
        let size = config.diameter + 20
        if abs(panel.frame.width - size) > 1 {
            panel.setContentSize(NSSize(width: size, height: size))
        }
    }
}
