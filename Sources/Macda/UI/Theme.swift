import SwiftUI

/// Macda's warm visual language — terracotta + cream, soft cards, rounded chips.
enum Theme {
    // Core palette
    static let accent      = Color(hex: "B85C38") ?? .orange      // terracotta
    static let accentDeep  = Color(hex: "A24E2E") ?? .orange
    static let accentSoft  = Color(hex: "E8C9B3") ?? .orange

    static let cream       = Color(hex: "FBF3EA") ?? .white       // page bg (light)
    static let card        = Color(hex: "FFFDFA") ?? .white       // raised cards
    static let sand        = Color(hex: "F1E4D5") ?? .white       // sidebar / wells
    static let liveHighlight = Color(hex: "F6E7D2") ?? .white     // live meeting card

    static let ink         = Color(hex: "3B2C22") ?? .primary     // primary text
    static let inkSoft     = Color(hex: "8C7B6D") ?? .secondary   // secondary text
    static let hairline    = Color(hex: "E7D9C8") ?? .gray

    // Dark "live" surface
    static let darkBg      = Color(hex: "241A13") ?? .black
    static let darkCard    = Color(hex: "33271D") ?? .black
    static let darkText    = Color(hex: "F3E7D9") ?? .white
    static let darkTextSoft = Color(hex: "B7A290") ?? .gray

    // Chip palettes
    static let chipNeutralBg = Color(hex: "EFE2D2") ?? .gray
    static let chipGreenBg   = Color(hex: "D9E7CE") ?? .green
    static let chipGreenInk  = Color(hex: "4E6B3C") ?? .green
    static let chipAccentBg  = Color(hex: "F3DCCB") ?? .orange
}

/// A small rounded pill used for tags, speakers, tool traces.
struct Chip: View {
    enum Kind { case neutral, green, accent }
    var text: String
    var systemImage: String? = nil
    var kind: Kind = .neutral

    private var bg: Color {
        switch kind {
        case .neutral: return Theme.chipNeutralBg
        case .green: return Theme.chipGreenBg
        case .accent: return Theme.chipAccentBg
        }
    }
    private var fg: Color {
        switch kind {
        case .green: return Theme.chipGreenInk
        default: return Theme.accentDeep
        }
    }
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(bg, in: Capsule())
    }
}

/// Primary terracotta button (Stop & save, Start listening…).
struct MacdaButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Theme.accentDeep)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(filled ? Theme.accent : Theme.chipAccentBg)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

extension View {
    /// A soft raised card.
    func macdaCard(_ fill: Color = Theme.card, radius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
    }
}
