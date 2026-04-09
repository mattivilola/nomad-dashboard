import Foundation

public enum DashboardCardID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case connectivity
    case power
    case timeTracking
    case travelContext
    case localInfo
    case fuelPrices
    case emergencyCare
    case travelAlerts
    case weather

    public static let defaultOrder: [DashboardCardID] = [
        .connectivity,
        .power,
        .timeTracking,
        .travelContext,
        .localInfo,
        .fuelPrices,
        .emergencyCare,
        .travelAlerts,
        .weather
    ]

    public static func sanitizedOrder(_ order: [DashboardCardID]) -> [DashboardCardID] {
        var seen: Set<DashboardCardID> = []
        let deduplicated = order.filter { seen.insert($0).inserted }
        let missing = defaultOrder.filter { seen.contains($0) == false }
        return deduplicated + missing
    }

    public static let defaultWidthModes: [DashboardCardID: DashboardCardWidthMode] = {
        Dictionary(uniqueKeysWithValues: defaultOrder.map { ($0, .wide) })
    }()

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
