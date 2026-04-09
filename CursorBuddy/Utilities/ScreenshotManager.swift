import Foundation
import AppKit
import ScreenCaptureKit

// MARK: - ScreenCapture Model

struct ScreenCapture {
    let imageData: Data
    let label: String
    let cgImage: CGImage
    /// The actual screen frame (AppKit coords, bottom-left origin)
    let screenFrame: CGRect
    /// The pixel dimensions of the captured image (what Claude sees)
    let captureWidth: Int
    let captureHeight: Int
    /// The display size in points (for coordinate conversion)
    let displayWidthInPoints: Int
    let displayHeightInPoints: Int
    /// Whether the cursor is on this screen
    let isCursorScreen: Bool
    /// The user's cursor position in screenshot pixel coordinates (top-left origin)
    let cursorInImageX: Int
    let cursorInImageY: Int

    /// JPEG image encoded as base64 string for API calls
    var base64JPEG: String? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.8]
        ) else { return nil }
        return jpegData.base64EncodedString()
    }

    /// Convert a [POINT:x,y] from screenshot pixel space to overlay screen-point space.
    ///
    /// Claude's coordinates are in the screenshot's pixel space (e.g. 1280x800).
    /// The overlay covers the screen in display points (e.g. 1512x982).
    /// Scale from screenshot pixels → display points.
    func screenshotPointToOverlayPoint(_ point: CGPoint) -> CGPoint {
        let scaleX = CGFloat(displayWidthInPoints) / CGFloat(captureWidth)
        let scaleY = CGFloat(displayHeightInPoints) / CGFloat(captureHeight)
        let result = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        print("[ScreenCapture] Point conversion: (\(point.x), \(point.y)) × (\(scaleX), \(scaleY)) → (\(result.x), \(result.y))  [capture \(captureWidth)x\(captureHeight), display \(displayWidthInPoints)x\(displayHeightInPoints)]")
        return result
    }
}

// MARK: - Screenshot Errors

enum ScreenCaptureError: Error, LocalizedError {
    case noDisplaysFound
    case permissionDenied
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplaysFound:
            return "No displays found for screen capture."
        case .permissionDenied:
            return "Screen recording permission is required."
        case .captureFailed(let detail):
            return "Screen capture failed: \(detail)"
        }
    }
}

// MARK: - CompanionScreenCapture

@MainActor
class CompanionScreenCapture {

    /// Set this to the floating button panel so it can be excluded from captures
    var floatingButtonWindowToExcludeFromCaptures: NSWindow?

    /// Max dimension for captured screenshots. Matches Clicky's approach:
    /// smaller images = faster API calls + Claude reasons about coordinates accurately.
    private let maxCaptureDimension = 1280

    // MARK: - Permission Check

    func hasScreenRecordingPermission() -> Bool {
        CompanionPermissionCenter.shouldTreatScreenRecordingAsGranted()
    }

    func requestScreenRecordingPermission() {
        CompanionPermissionCenter.requestScreenRecordingPermission()
    }

    // MARK: - Capture

    /// Capture all connected displays as JPEG data.
    /// Screenshots are scaled to maxCaptureDimension for performance.
    /// Claude's [POINT:] coordinates are in the screenshot pixel space.
    func captureScreen(cursorAreaOnly: Bool = false) async throws -> [ScreenCapture] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            print("[ScreenCapture] Failed to get shareable content: \(error)")
            throw ScreenCaptureError.permissionDenied
        }

        let displays = content.displays
        guard !displays.isEmpty else {
            throw ScreenCaptureError.noDisplaysFound
        }

        let mouseLocation = NSEvent.mouseLocation

        // Exclude all windows belonging to this app (overlays, panels, etc.)
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let excludedWindows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == ownBundleID
        }

        // Also exclude the floating button panel
        if let panelToExclude = floatingButtonWindowToExcludeFromCaptures {
            let panelWindowNumber = panelToExclude.windowNumber
            for window in content.windows {
                if window.windowID == CGWindowID(panelWindowNumber) {
                    // Already in excludedWindows via bundle ID match
                    break
                }
            }
        }

        // Build NSScreen lookup by display ID for AppKit coordinate frames
        var nsScreenByDisplayID: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                nsScreenByDisplayID[screenNumber] = screen
            }
        }

        // Sort displays so cursor screen is first
        let sortedDisplays = displays.sorted { a, b in
            let frameA = nsScreenByDisplayID[a.displayID]?.frame ?? a.frame
            let frameB = nsScreenByDisplayID[b.displayID]?.frame ?? b.frame
            let aHasCursor = frameA.contains(mouseLocation)
            let bHasCursor = frameB.contains(mouseLocation)
            if aHasCursor != bHasCursor { return aHasCursor }
            return false
        }

        var captures: [ScreenCapture] = []

        // Get cursor position in CG coordinates (top-left origin)
        let cgCursorPos = CGEvent(source: nil)?.location ?? .zero

        for (displayIndex, display) in sortedDisplays.enumerated() {
            // Use NSScreen.frame (AppKit coords, bottom-left origin)
            let displayFrame = nsScreenByDisplayID[display.displayID]?.frame
                ?? CGRect(x: display.frame.origin.x, y: display.frame.origin.y,
                          width: CGFloat(display.width), height: CGFloat(display.height))
            let isCursorScreen = displayFrame.contains(mouseLocation)

            // Only capture cursor screen for efficiency (match Clicky behavior)
            if !isCursorScreen && sortedDisplays.count > 1 { continue }

            do {
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

                // Scale to maxCaptureDimension (e.g. 1280) maintaining aspect ratio.
                // This is the coordinate space Claude will use for [POINT:] tags.
                let aspectRatio = CGFloat(display.width) / CGFloat(display.height)
                let captureW: Int
                let captureH: Int
                if display.width >= display.height {
                    captureW = maxCaptureDimension
                    captureH = Int(CGFloat(maxCaptureDimension) / aspectRatio)
                } else {
                    captureH = maxCaptureDimension
                    captureW = Int(CGFloat(maxCaptureDimension) * aspectRatio)
                }

                let config = SCStreamConfiguration()
                config.width = captureW
                config.height = captureH
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                let actualW = cgImage.width
                let actualH = cgImage.height

                // Draw cursor highlight circle on the image
                let imageWithHighlight = drawCursorHighlight(
                    on: cgImage,
                    cursorScreenPos: cgCursorPos,
                    displayBounds: CGDisplayBounds(display.displayID),
                    imageWidth: actualW,
                    imageHeight: actualH
                )

                // Optionally crop to cursor area
                let finalImage: CGImage
                if cursorAreaOnly {
                    finalImage = cropAroundCursor(
                        image: imageWithHighlight,
                        cursorScreenPos: cgCursorPos,
                        displayBounds: CGDisplayBounds(display.displayID)
                    )
                } else {
                    finalImage = imageWithHighlight
                }

                let finalW = finalImage.width
                let finalH = finalImage.height

                guard let jpegData = NSBitmapImageRep(cgImage: finalImage)
                    .representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                    continue
                }

                // Compute cursor position in screenshot pixel space
                let displayBounds = CGDisplayBounds(display.displayID)
                let cursorInImageX = Int((cgCursorPos.x - displayBounds.origin.x) / displayBounds.width * CGFloat(finalW))
                let cursorInImageY = Int((cgCursorPos.y - displayBounds.origin.y) / displayBounds.height * CGFloat(finalH))

                // Build label with actual pixel dimensions so Claude knows the coordinate space
                let screenLabel: String
                if sortedDisplays.count == 1 {
                    screenLabel = "user's screen (image dimensions: \(finalW)x\(finalH) pixels)"
                } else if isCursorScreen {
                    screenLabel = "screen \(displayIndex + 1) of \(sortedDisplays.count) — primary focus (image dimensions: \(finalW)x\(finalH) pixels)"
                } else {
                    screenLabel = "screen \(displayIndex + 1) of \(sortedDisplays.count) — secondary (image dimensions: \(finalW)x\(finalH) pixels)"
                }

                let capture = ScreenCapture(
                    imageData: jpegData,
                    label: screenLabel,
                    cgImage: finalImage,
                    screenFrame: displayFrame,
                    captureWidth: finalW,
                    captureHeight: finalH,
                    displayWidthInPoints: Int(displayFrame.width),
                    displayHeightInPoints: Int(displayFrame.height),
                    isCursorScreen: isCursorScreen,
                    cursorInImageX: cursorInImageX,
                    cursorInImageY: cursorInImageY
                )
                captures.append(capture)

                print("[ScreenCapture] Captured display \(display.displayID): \(finalW)x\(finalH)px screenshot, \(Int(displayFrame.width))x\(Int(displayFrame.height))pt display")
            } catch {
                print("[ScreenCapture] Failed to capture display \(display.displayID): \(error)")
            }
        }

        if captures.isEmpty {
            throw ScreenCaptureError.captureFailed("No displays were captured successfully.")
        }

        return captures
    }

    // MARK: - Cursor Area Cropping

    private func cropAroundCursor(image: CGImage, cursorScreenPos: CGPoint, displayBounds: CGRect) -> CGImage {
        let cropWidth = 800
        let cropHeight = 600
        let imageW = image.width
        let imageH = image.height

        let cursorPixelX = Int((cursorScreenPos.x - displayBounds.origin.x) / displayBounds.width * CGFloat(imageW))
        let cursorPixelY = Int((cursorScreenPos.y - displayBounds.origin.y) / displayBounds.height * CGFloat(imageH))

        guard imageW > cropWidth && imageH > cropHeight else { return image }

        var originX = cursorPixelX - cropWidth / 2
        var originY = cursorPixelY - cropHeight / 2
        originX = max(0, min(originX, imageW - cropWidth))
        originY = max(0, min(originY, imageH - cropHeight))

        let cropRect = CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
        guard let cropped = image.cropping(to: cropRect) else { return image }
        return cropped
    }

    // MARK: - Cursor Highlight

    private func drawCursorHighlight(on image: CGImage, cursorScreenPos: CGPoint, displayBounds: CGRect, imageWidth: Int, imageHeight: Int) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // Draw without flipping — the pixel buffer row order naturally matches
        // JPEG convention (row 0 = top). The old translateBy/scaleBy flip was
        // correct for on-screen display but inverted the image when extracted
        // via makeImage() → JPEG, because JPEG treats row 0 as the top.
        context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        let cursorX = (cursorScreenPos.x - displayBounds.origin.x) / displayBounds.width * CGFloat(imageWidth)
        let cursorY = (cursorScreenPos.y - displayBounds.origin.y) / displayBounds.height * CGFloat(imageHeight)

        // Inner circle
        context.setStrokeColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.8)
        context.setLineWidth(3.0)
        let innerRadius: CGFloat = 20
        context.strokeEllipse(in: CGRect(x: cursorX - innerRadius, y: cursorY - innerRadius, width: innerRadius * 2, height: innerRadius * 2))

        // Outer circle
        let outerRadius: CGFloat = 35
        context.setStrokeColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.4)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: CGRect(x: cursorX - outerRadius, y: cursorY - outerRadius, width: outerRadius * 2, height: outerRadius * 2))

        // Crosshair
        context.setStrokeColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.6)
        context.setLineWidth(1.5)
        let crosshairLength: CGFloat = 15
        context.move(to: CGPoint(x: cursorX - crosshairLength, y: cursorY))
        context.addLine(to: CGPoint(x: cursorX + crosshairLength, y: cursorY))
        context.strokePath()
        context.move(to: CGPoint(x: cursorX, y: cursorY - crosshairLength))
        context.addLine(to: CGPoint(x: cursorX, y: cursorY + crosshairLength))
        context.strokePath()

        return context.makeImage() ?? image
    }
}
