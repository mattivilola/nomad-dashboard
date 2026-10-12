import Foundation

/// The kind of traveller the dashboard is tuned for. It shapes the recommended card order
/// and how heads-up items are ranked; it never hides a card or feature.
public enum TravelProfile: String, Codable, CaseIterable, Sendable {
    case nomad
    case roadTrip

    public var title: String {
        switch self {
        case .nomad:
            "Nomad"
        case .roadTrip:
            "Road trip & RV"
        }
    }

    public var summary: String {
        switch self {
        case .nomad:
            "Puts connection quality, work time and city context first."
        case .roadTrip:
            "Puts weather, fuel, emergency care, power and data allowance first."
        }
    }
}
