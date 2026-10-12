import AppIntents
import NomadCore

/// `TravelProfile` as an intent parameter.
enum TravelProfileOption: String, AppEnum {
    case nomad
    case roadTrip

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Travel Profile")

    static let caseDisplayRepresentations: [TravelProfileOption: DisplayRepresentation] = [
        .nomad: DisplayRepresentation(title: "Nomad"),
        .roadTrip: DisplayRepresentation(title: "Road trip & RV")
    ]

    init(_ profile: TravelProfile) {
        switch profile {
        case .nomad: self = .nomad
        case .roadTrip: self = .roadTrip
        }
    }

    var travelProfile: TravelProfile {
        switch self {
        case .nomad: .nomad
        case .roadTrip: .roadTrip
        }
    }
}
