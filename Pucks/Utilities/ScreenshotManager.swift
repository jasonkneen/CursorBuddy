import Foundation
import AppKit
import ScreenCaptureKit

// MARK: - ScreenCapture Model

struct ScreenCapture {
    let imageData: Data
    let label: String
    let cgImage: CGImage
    /// The actual screen frame (in screen points) this capture came from
    let screenFrame: CGRect
    /// The pixel dimensions of the captured image (what Claude sees)
    let captureWidth: Int
    let captureHeight: Int
    /// The user's cursor position in screenshot pixel coordinates (top-left origin)
    let cursorInImageX: Int
    let cursorInImageY: Int

    /// JPEG image encoded as base64 string for API calls
    var base64JPEG: String? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.7]
        ) else { return nil }
        return jpegData.base64EncodedString()
    }

    /// Convert a [POINT:x,y] from screenshot pixel space to overlay screen-point space.
    ///
    /// The screenshot is captureWidth x captureHeight pixels.
    /// The overlay covers the screen which is screenFrame.width x screenFrame.height points.
    /// Both have top-left origin. Simple ratio scale.
    func screenshotPointToOverlayPoint(_ point: CGPoint) -> CGPoint {
        let scaleX = screenFrame.width / CGFloat(captureWidth)
        let scaleY = screenFrame.height / CGFloat(captureHeight)
        let result = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        print("[ScreenCapture] Point conversion: (\(point.x), \(point.y)) × (\(scaleX), \(scaleY)) → (\(result.x), \(result.y))  [capture \(captureWidth)x\(captureHeight), screen \(screenFrame.width)x\(screenFrame.height)]")
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

    // MARK: - Permission Check

    /// Check if we have screen recording permission
    func hasScreenRecordingPermission() -> Bool {
        // Attempt to create a small capture to test permission
        // CGWindowListCopyWindowInfo requires screen recording permission on macOS 10.15+
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        return windowList != nil
    }

    /// Request screen recording permission by triggering the system prompt
    func requestScreenRecordingPermission() {
        // Triggering a capture attempt will show the system permission dialog
        let _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        print("[ScreenCapture] Screen recording permission requested.")
    }

    // MARK: - Capture

    /// Capture all displays, labeling the primary (cursor) display as 'primary focus'
    func captureScreen() async throws -> [ScreenCapture] {
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

        // Determine which display the cursor is on
        let primaryDisplayID = displayContainingCursor(displays: displays, cursorLocation: .zero)

        // Build exclusion list for the floating button window
        let excludedWindows = buildExcludedWindows(from: content.windows)

        var captures: [ScreenCapture] = []

        // Get cursor position in CG coordinates (top-left origin)
        let cgCursorPos = CGEvent(source: nil)?.location ?? .zero

        for display in displays {
            let isPrimary = display.displayID == primaryDisplayID
            if !isPrimary { continue }  // Only capture the screen the cursor is on
            let label = "primary focus"

            do {
                let filter = SCContentFilter(
                    display: display,
                    excludingWindows: excludedWindows
                )

                // Use display.width/height directly for capture config.
                // SCDisplay width/height are in points; SCStreamConfiguration interprets them as pixels.
                // This gives us a 1x-point-resolution capture which is good for performance + Claude vision.
                let captureW = Int(display.width)
                let captureH = Int(display.height)

                let config = SCStreamConfiguration()
                config.width = captureW
                config.height = captureH
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true   // Show cursor so Claude can see where the user is pointing

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                // Draw a subtle circle around cursor to help Claude identify the focus point
                let imageWithCursorHighlight = drawCursorHighlight(
                    on: image,
                    cursorScreenPos: cgCursorPos,
                    displayBounds: CGDisplayBounds(display.displayID)
                )
                
                let data = imageToJPEGData(imageWithCursorHighlight) ?? Data()

                // Use actual captured image dimensions (what Claude will see)
                let actualW = imageWithCursorHighlight.width
                let actualH = imageWithCursorHighlight.height

                // Find the NSScreen for this display to get the screen frame
                let screenFrame = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
                })?.frame ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))

                // Include actual pixel dimensions in the label so Claude knows the coordinate space
                let labelWithDimensions = "\(label) (\(actualW)x\(actualH) pixels)"

                // Compute cursor position in screenshot pixel space
                let displayBounds = CGDisplayBounds(display.displayID)
                let cursorInImageX = Int((cgCursorPos.x - displayBounds.origin.x) / displayBounds.width * CGFloat(actualW))
                let cursorInImageY = Int((cgCursorPos.y - displayBounds.origin.y) / displayBounds.height * CGFloat(actualH))
                print("[ScreenCapture] Cursor in image: (\(cursorInImageX), \(cursorInImageY)) — CG cursor \(cgCursorPos), displayBounds \(displayBounds), image \(actualW)x\(actualH)")

                let capture = ScreenCapture(
                    imageData: data,
                    label: labelWithDimensions,
                    cgImage: image,
                    screenFrame: screenFrame,
                    captureWidth: actualW,
                    captureHeight: actualH,
                    cursorInImageX: cursorInImageX,
                    cursorInImageY: cursorInImageY
                )
                captures.append(capture)

                print("[ScreenCapture] Captured display \(display.displayID) as '\(label)'")
            } catch {
                print("[ScreenCapture] Failed to capture display \(display.displayID): \(error)")
            }
        }

        if captures.isEmpty {
            throw ScreenCaptureError.captureFailed("No displays were captured successfully.")
        }

        return captures
    }

    // MARK: - Helpers

    /// Determine which display contains the cursor using CoreGraphics (reliable across multi-monitor)
    private func displayContainingCursor(displays: [SCDisplay], cursorLocation: NSPoint) -> CGDirectDisplayID {
        // Use CGEvent to get cursor position in CG coordinates (top-left origin, pixels)
        // This is the most reliable method across all monitor configurations
        let cgCursorPos = CGEvent(source: nil)?.location ?? .zero

        // Ask CG which display contains that point
        var matchingDisplays = [CGDirectDisplayID](repeating: 0, count: 1)
        var displayCount: UInt32 = 0
        let err = CGGetDisplaysWithPoint(cgCursorPos, 1, &matchingDisplays, &displayCount)

        if err == .success, displayCount > 0 {
            let foundID = matchingDisplays[0]
            print("[ScreenCapture] Cursor at CG \(cgCursorPos) → display \(foundID)")
            // Verify this display is in our SCDisplay list
            if displays.contains(where: { $0.displayID == foundID }) {
                return foundID
            }
        }

        print("[ScreenCapture] ⚠️ CGGetDisplaysWithPoint failed (cursor \(cgCursorPos)), falling back to main display")
        return CGMainDisplayID()
    }

    /// Build list of windows to exclude from capture
    private func buildExcludedWindows(from windows: [SCWindow]) -> [SCWindow] {
        var excluded: [SCWindow] = []

        if let panelToExclude = floatingButtonWindowToExcludeFromCaptures {
            let panelWindowNumber = panelToExclude.windowNumber
            for window in windows {
                if window.windowID == CGWindowID(panelWindowNumber) {
                    excluded.append(window)
                    break
                }
            }
        }

        // Also exclude our own app windows
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if !bundleID.isEmpty {
            for window in windows {
                if window.owningApplication?.bundleIdentifier == bundleID {
                    excluded.append(window)
                }
            }
        }

        return excluded
    }

    /// Convert CGImage to JPEG data
    private func imageToJPEGData(_ image: CGImage) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.7]
        )
    }
    
    /// Draw a subtle highlight circle around the cursor position to help Claude identify focus
    private func drawCursorHighlight(on image: CGImage, cursorScreenPos: CGPoint, displayBounds: CGRect) -> CGImage {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // CGContext has y=0 at bottom by default, but CGEvent cursor coordinates have y=0 at top.
        // Flip the context so drawing coordinates match CG global space (y increases downward).
        // This ensures the image is stored right-side-up AND the cursor circle lands at the correct pixel.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        // Draw the original image (appears correctly oriented after the flip)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Cursor position in image pixel coordinates.
        // cursorScreenPos uses CG global coords (y from top), which now matches our flipped context.
        let cursorX = (cursorScreenPos.x - displayBounds.origin.x) / displayBounds.width * CGFloat(width)
        let cursorY = (cursorScreenPos.y - displayBounds.origin.y) / displayBounds.height * CGFloat(height)

        // Draw a circle around cursor (red with alpha)
        context.setStrokeColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.8)
        context.setLineWidth(3.0)

        let innerRadius: CGFloat = 20
        let outerRadius: CGFloat = 35

        context.strokeEllipse(in: CGRect(
            x: cursorX - innerRadius,
            y: cursorY - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))

        context.setStrokeColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.4)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: CGRect(
            x: cursorX - outerRadius,
            y: cursorY - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))

        // Draw crosshair for precision
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
