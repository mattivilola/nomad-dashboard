import Combine
import CoreLocation
import Foundation

@MainActor
final class CurrentLocationStore: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.currentCoordinate = manager.location?.coordinate
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationSummary: String {
        switch authorizationStatus {
        case .authorizedAlways:
            "Always allowed"
        case .authorizedWhenInUse:
            "When in use"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .notDetermined:
            "Not determined"
        @unknown default:
            "Unknown"
        }
    }

    func prepareForWeather() {
        if authorizationStatus == .notDetermined {
            requestAuthorization()
        } else if isAuthorized {
            refreshLocation()
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func refreshLocation() {
        manager.requestLocation()
    }
}

@MainActor
extension CurrentLocationStore: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

private extension CurrentLocationStore {
    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }
}
