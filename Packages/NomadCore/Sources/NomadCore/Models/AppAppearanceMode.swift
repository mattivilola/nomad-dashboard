import Foundation

public enum AppAppearanceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case system
    case dark
    case light

    public func toggled(resolvedSystemAppearanceIsDark: Bool) -> AppAppearanceMode {
        switch self {
        case .system:
            resolvedSystemAppearanceIsDark ? .light : .dark
        case .dark:
            .light
        case .light:
            .dark
        }
    }
}
