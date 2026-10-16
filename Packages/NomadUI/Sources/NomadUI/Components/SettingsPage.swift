import NomadCore

/// The pages of the Settings window, in sidebar order.
public enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general
    case weatherAndLocal
    case safety
    case stays
    case connectionAndData
    case work
    case privacyAndLocation
    case advanced

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .weatherAndLocal: "Weather & Local"
        case .safety: "Safety"
        case .stays: "Stays & Visas"
        case .connectionAndData: "Connection & Data"
        case .work: "Work"
        case .privacyAndLocation: "Privacy & Location"
        case .advanced: "Advanced"
        }
    }

    public var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .weatherAndLocal: "cloud.sun"
        case .safety: "cross.case"
        case .stays: "calendar.badge.clock"
        case .connectionAndData: "antenna.radiowaves.left.and.right"
        case .work: "briefcase"
        case .privacyAndLocation: "hand.raised"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// A group inside the Settings window that other parts of the app can jump to.
/// Each target belongs to one page; its raw value doubles as the scroll anchor of the group's first row.
public enum SettingsFocusTarget: String, CaseIterable, Sendable {
    case surfSpot
    case homeTimeZone
    case citizenship
    case stays
    case quietAlerts
    case workplaceDiary
    case visitedPlaces
    case weather
    case localInfo
    case fuelPrices
    case travelAlerts
    case emergencyCare
    case dataGuard
    case timeTracking

    public var page: SettingsPage {
        switch self {
        case .surfSpot, .weather, .localInfo, .fuelPrices: .weatherAndLocal
        case .homeTimeZone, .citizenship: .general
        case .quietAlerts, .dataGuard: .connectionAndData
        case .workplaceDiary, .timeTracking: .work
        case .visitedPlaces: .privacyAndLocation
        case .travelAlerts, .emergencyCare: .safety
        case .stays: .stays
        }
    }
}

public extension DashboardCardID {
    /// The Settings group that switches this card's feature on, or nil when the card has no setting of its own.
    var settingsFocusTarget: SettingsFocusTarget? {
        switch self {
        case .meteredData: .dataGuard
        case .timeTracking: .timeTracking
        case .localInfo: .localInfo
        case .fuelPrices: .fuelPrices
        case .emergencyCare: .emergencyCare
        case .embassy: .citizenship
        case .stays: .stays
        case .travelAlerts: .travelAlerts
        case .weather: .weather
        case .connectivity, .power, .travelContext: nil
        }
    }
}
