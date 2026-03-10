import Foundation

public enum DashboardCardID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case connectivity
    case power
    case travelContext
    case fuelPrices
    case travelAlerts
    case weather

    public static let defaultOrder: [DashboardCardID] = [
        .connectivity,
        .power,
        .travelContext,
        .fuelPrices,
        .travelAlerts,
        .weather
    ]

    public static func sanitizedOrder(_ order: [DashboardCardID]) -> [DashboardCardID] {
        var seen: Set<DashboardCardID> = []
        let deduplicated = order.filter { seen.insert($0).inserted }
        let missing = defaultOrder.filter { seen.contains($0) == false }
        return deduplicated + missing
    }
}
