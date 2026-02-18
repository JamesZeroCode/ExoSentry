import SwiftUI

enum ExoSentryTheme {
    // MARK: - Brand Colors
    static let primary = Color(red: 0.075, green: 0.925, blue: 0.502)        // #13ec80
    static let primaryDim = Color(red: 0.075, green: 0.925, blue: 0.502).opacity(0.6)

    // MARK: - Popover Colors
    enum Popover {
        static let background = Color(red: 0.063, green: 0.133, blue: 0.098) // #102219
        static let sectionDivider = Color.white.opacity(0.08)
        static let cardBackground = Color.white.opacity(0.05)
        static let hoverBackground = Color.white.opacity(0.08)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)
        static let textTertiary = Color.white.opacity(0.4)
    }

    // MARK: - DESIGN.md Brand Colors
    static let warningAmber = Color(red: 0.961, green: 0.620, blue: 0.043)   // #F59E0B
    static let inactiveSlate = Color(red: 0.392, green: 0.455, blue: 0.545)  // #64748B

    // MARK: - Icon Colors
    static let iconGradientTop = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let iconGradientBottom = Color.black                                  // #000000

    // MARK: - Glow Effects
    static let primaryGlow = primary.opacity(0.5)
    static let primaryGlowIcon = primary.opacity(0.6)
    static let primaryGlowInner = primary.opacity(0.15)

    // MARK: - Status Colors
    static let statusActive = primary  // 品牌绿 #13EC80
    static let statusPaused = Color.red
    static let statusDegraded = Color.yellow
    static let statusOverheat = Color.orange
    static let warningYellow = Color.yellow
    static let warningOrange = Color.orange

    // MARK: - Load Level
    enum LoadLevel: String {
        case low = "低"
        case medium = "中"
        case high = "高"
        case extreme = "极高"

        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .extreme: return .red
            }
        }

        static func from(temperature: Double?) -> LoadLevel {
            guard let temp = temperature else { return .low }
            switch temp {
            case ..<60: return .low
            case 60..<80: return .medium
            case 80..<95: return .high
            default: return .extreme
            }
        }
    }
}

// MARK: - Hover Highlight Modifier

struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let hoverColor: Color
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? hoverColor : .clear)
            )
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct HoverScale: ViewModifier {
    let scale: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

extension View {
    func hoverHighlight(
        cornerRadius: CGFloat = 4,
        color: Color = ExoSentryTheme.Popover.hoverBackground
    ) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, hoverColor: color))
    }

    func hoverScale(_ scale: CGFloat = 1.03) -> some View {
        modifier(HoverScale(scale: scale))
    }
}
