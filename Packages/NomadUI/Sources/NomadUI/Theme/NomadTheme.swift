import SwiftUI

public enum NomadTheme {
    public static let background = LinearGradient(
        colors: [
            Color(hex: 0x101A24),
            Color(hex: 0x17303A),
            Color(hex: 0x33241E)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let sand = Color(hex: 0xF0C987)
    public static let teal = Color(hex: 0x5FC3C8)
    public static let coral = Color(hex: 0xF68B63)
    public static let fog = Color.white.opacity(0.84)
    public static let cardBackground = Color.white.opacity(0.10)
    public static let cardBorder = Color.white.opacity(0.12)
}

public extension Color {
    init(hex: UInt64, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

