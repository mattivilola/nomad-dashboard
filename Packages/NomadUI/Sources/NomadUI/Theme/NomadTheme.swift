import AppKit
import SwiftUI

public enum NomadTheme {
    public static let sand = Color(dynamicLight: 0xA56E17, dark: 0xF0C987)
    public static let teal = Color(dynamicLight: 0x0E8C92, dark: 0x5FC3C8)
    public static let coral = Color(dynamicLight: 0xC85C34, dark: 0xF68B63)

    public static let primaryText = Color(dynamicLight: 0x13212A, dark: 0xFFFFFF, darkOpacity: 0.84)
    public static let secondaryText = Color(dynamicLight: 0x425663, dark: 0xFFFFFF, darkOpacity: 0.68)
    public static let tertiaryText = Color(dynamicLight: 0x657784, dark: 0xFFFFFF, darkOpacity: 0.58)
    public static let quaternaryText = Color(dynamicLight: 0x80909B, dark: 0xFFFFFF, darkOpacity: 0.44)

    public static let cardBackground = Color(dynamicLight: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.74, darkOpacity: 0.10)
    public static let cardBorder = Color(dynamicLight: 0xCAD7DC, dark: 0xFFFFFF, lightOpacity: 0.92, darkOpacity: 0.12)
    public static let tileBackground = Color(dynamicLight: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.58, darkOpacity: 0.08)
    public static let actionIconForeground = Color(dynamicLight: 0x17303A, dark: 0xFFFFFF, lightOpacity: 0.92, darkOpacity: 0.88)
    public static let actionIconBackground = Color(dynamicLight: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.76, darkOpacity: 0.10)
    public static let actionIconBorder = Color(dynamicLight: 0xD4E0E4, dark: 0xFFFFFF, lightOpacity: 0.90, darkOpacity: 0.10)
    public static let chartBackground = Color(dynamicLight: 0xFFFFFF, dark: 0x000000, lightOpacity: 0.58, darkOpacity: 0.14)
    public static let inlineButtonBackground = Color(dynamicLight: 0xE3EDF0, dark: 0xFFFFFF, lightOpacity: 0.88, darkOpacity: 0.09)

    public static let background = LinearGradient(
        colors: [
            Color(dynamicLight: 0xF6EEDD, dark: 0x101A24),
            Color(dynamicLight: 0xE7F4F2, dark: 0x17303A),
            Color(dynamicLight: 0xFCEBDD, dark: 0x33241E)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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

    init(dynamicLight lightHex: UInt64, dark darkHex: UInt64, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
                case .darkAqua:
                    NSColor(hex: darkHex, opacity: darkOpacity)
                default:
                    NSColor(hex: lightHex, opacity: lightOpacity)
                }
            }
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt64, opacity: Double = 1) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: opacity
        )
    }
}
