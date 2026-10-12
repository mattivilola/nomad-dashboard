import Foundation

public enum DashboardCardID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case connectivity
    case meteredData
    case power
    case timeTracking
    case travelContext
    case localInfo
    case fuelPrices
    case emergencyCare
    case embassy
    case travelAlerts
    case weather

    public static let defaultOrder: [DashboardCardID] = [
        .connectivity,
        .meteredData,
        .power,
        .timeTracking,
        .travelContext,
        .localInfo,
        .fuelPrices,
        .emergencyCare,
        .embassy,
        .travelAlerts,
        .weather
    ]

    /// The recommended card order for a travel profile. `.nomad` is the baseline `defaultOrder`.
    public static func defaultOrder(for profile: TravelProfile) -> [DashboardCardID] {
        switch profile {
        case .nomad:
            defaultOrder
        case .roadTrip:
            [
                .weather,
                .fuelPrices,
                .emergencyCare,
                .embassy,
                .power,
                .meteredData,
                .travelAlerts,
                .connectivity,
                .localInfo,
                .travelContext,
                .timeTracking
            ]
        }
    }

    /// Drops duplicates and adds every card missing from `order`. A missing card goes right after the
    /// nearest card before it in `defaultOrder` that is present, so a saved order from before a card
    /// existed gets it next to its recommended neighbour (an untouched old default becomes exactly the
    /// new default). A card with no earlier neighbour present goes first.
    public static func sanitizedOrder(_ order: [DashboardCardID]) -> [DashboardCardID] {
        var seen: Set<DashboardCardID> = []
        var result = order.filter { seen.insert($0).inserted }

        for (index, card) in defaultOrder.enumerated() where seen.contains(card) == false {
            let predecessor = defaultOrder[..<index].last { seen.contains($0) }
            let insertionIndex = predecessor.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(card, at: insertionIndex)
            seen.insert(card)
        }

        return result
    }

    public static let defaultWidthModes: [DashboardCardID: DashboardCardWidthMode] = Dictionary(uniqueKeysWithValues: defaultOrder.map { ($0, .wide) })

    public static func sanitizedWidthModes(
        _ widthModes: [DashboardCardID: DashboardCardWidthMode]
    ) -> [DashboardCardID: DashboardCardWidthMode] {
        var sanitized = defaultWidthModes

        for cardID in defaultOrder {
            if let widthMode = widthModes[cardID] {
                sanitized[cardID] = widthMode
            }
        }

        return sanitized
    }

    public static func fromPersistedRawValue(_ rawValue: String) -> DashboardCardID? {
        if rawValue == "localPriceLevel" {
            return .localInfo
        }

        return DashboardCardID(rawValue: rawValue)
    }
}

public extension DashboardCardID {
    /// Whether the opt-in feature behind this card is switched on in Settings.
    /// Cards without a feature toggle are always enabled.
    func isFeatureEnabled(in settings: AppSettings) -> Bool {
        switch self {
        case .meteredData:
            settings.meteredDataEnabled
        case .timeTracking:
            settings.projectTimeTrackingEnabled
        case .localInfo:
            settings.localInfoEnabled
        case .fuelPrices:
            settings.fuelPricesEnabled
        case .emergencyCare:
            settings.emergencyCareEnabled
        case .travelAlerts:
            settings.travelAdvisoryEnabled
                || settings.travelWeatherAlertsEnabled
                || settings.regionalSecurityEnabled
        case .embassy:
            settings.citizenshipCountryCodes.isEmpty == false
        case .connectivity, .power, .travelContext, .weather:
            true
        }
    }
}
