import SwiftUI

extension Color {
    /// Create a Color from a "#RRGGBB" hex string; returns nil if malformed.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    /// Preset mascot colors offered in Settings / the quick menu.
    static let mascotPresets: [(name: String, hex: String)] = [
        ("Blue", "738CF2"),
        ("Green", "4DC78C"),
        ("Purple", "8C73F2"),
        ("Pink", "F277A6"),
        ("Orange", "F2A24D"),
        ("Graphite", "8A8A99")
    ]
}
