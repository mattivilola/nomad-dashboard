import CoreLocation

public extension CLAuthorizationStatus {
    var isNomadWeatherAuthorized: Bool {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse:
            true
        default:
            false
        }
    }
}
