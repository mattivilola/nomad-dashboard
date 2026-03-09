import AppKit
import NomadCore
import SwiftUI

extension AppAppearanceMode {
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .dark:
            NSAppearance(named: .darkAqua)
        case .light:
            NSAppearance(named: .aqua)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .dark:
            .dark
        case .light:
            .light
        }
    }

    var displayName: String {
        switch self {
        case .system:
            "System"
        case .dark:
            "Dark"
        case .light:
            "Light"
        }
    }
}
