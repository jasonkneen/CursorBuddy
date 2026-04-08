import SwiftUI

enum CursorStyle: String, CaseIterable, Identifiable {
    case triangle
    case arrow
    case dot
    case target
    case ring
    case diamond

    var id: String { rawValue }

    var label: String {
        switch self {
        case .triangle: return "Triangle"
        case .arrow: return "Arrow"
        case .dot: return "Dot"
        case .target: return "Target"
        case .ring: return "Ring"
        case .diamond: return "Diamond"
        }
    }
}

@MainActor
final class CursorAppearanceConfiguration: ObservableObject {
    static let shared = CursorAppearanceConfiguration()

    @Published var style: CursorStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: Self.userDefaultsKey)
        }
    }
    @Published var scale: Double {
        didSet {
            UserDefaults.standard.set(scale, forKey: Self.scaleUserDefaultsKey)
        }
    }
    /// Distance of the Pucks cursor from the real cursor (10–80pt, default 35).
    @Published var distance: Double {
        didSet {
            UserDefaults.standard.set(distance, forKey: Self.distanceUserDefaultsKey)
        }
    }

    private static let userDefaultsKey = "cursorStyle"
    private static let scaleUserDefaultsKey = "cursorScale"
    private static let distanceUserDefaultsKey = "cursorDistance"

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let style = CursorStyle(rawValue: rawValue) {
            self.style = style
        } else {
            self.style = .triangle
        }

        let storedScale = UserDefaults.standard.double(forKey: Self.scaleUserDefaultsKey)
        self.scale = storedScale == 0 ? 1.0 : min(max(storedScale, 0.6), 2.0)

        let storedDistance = UserDefaults.standard.double(forKey: Self.distanceUserDefaultsKey)
        self.distance = storedDistance == 0 ? 35.0 : min(max(storedDistance, 10), 80)
    }
}
