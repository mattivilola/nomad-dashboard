import AppKit
import Combine
import CoreLocation
import Foundation
import NomadCore

struct LocationDiagnosticsSnapshot: Equatable {
    let authorizationStatus: CLAuthorizationStatus
    let isLocationServicesEnabled: Bool
    let isRequestInProgress: Bool
    let lastRequestAt: Date?
    let lastErrorDescription: String?
    let hasReceivedLocation: Bool
    let lastLocationAt: Date?

    var statusText: String {
        if isLocationServicesEnabled == false {
            return "Location Services are disabled"
        }

        if isRequestInProgress {
            return "Requesting location…"
        }

        switch authorizationStatus {
        case .authorizedAlways:
            return hasReceivedLocation ? "Always allowed" : "Always allowed, waiting for a fix"
        case .authorizedWhenInUse:
            return hasReceivedLocation ? "When in use" : "When in use, waiting for a fix"
        case .denied:
            return "Permission denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Permission not requested"
        @unknown default:
            return "Unknown"
        }
    }

    var detailText: String? {
        if let lastErrorDescription {
            return lastErrorDescription
        }

        if isRequestInProgress {
            return "Waiting for macOS to return your current location."
        }

        if let lastLocationAt {
            return "Last fix \(lastLocationAt.formatted(date: .omitted, time: .shortened))."
        }

        if authorizationStatus.isNomadWeatherAuthorized {
            return "No location fix has been received yet."
        }

        if authorizationStatus == .notDetermined {
            return "Allow location access to use current weather and fill the surf spot from your position."
        }

        return nil
    }
}

@MainActor
final class CurrentLocationStore: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var isRequestInProgress = false
    @Published private(set) var lastRequestAt: Date?
    @Published private(set) var lastErrorDescription: String?
    @Published private(set) var lastLocationAt: Date?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        let initialLocation = manager.location
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.currentLocation = initialLocation
        self.currentCoordinate = initialLocation?.coordinate
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationSummary: String {
        diagnostics.statusText
    }

    var diagnostics: LocationDiagnosticsSnapshot {
        LocationDiagnosticsSnapshot(
            authorizationStatus: authorizationStatus,
            isLocationServicesEnabled: CLLocationManager.locationServicesEnabled(),
            isRequestInProgress: isRequestInProgress,
            lastRequestAt: lastRequestAt,
            lastErrorDescription: lastErrorDescription,
            hasReceivedLocation: currentLocation != nil,
            lastLocationAt: lastLocationAt
        )
    }

    func prepareForWeather() {
        if authorizationStatus == .notDetermined {
            requestAuthorization()
        } else if isAuthorized {
            requestCurrentLocation()
        }
    }

    func requestAuthorization() {
        beginLocationRequest()
        NSApp.activate(ignoringOtherApps: true)
        manager.requestWhenInUseAuthorization()
        requestCurrentLocation()
    }

    func refreshLocation() {
        requestCurrentLocation()
    }

    func requestCurrentLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            failRequest(with: "Location Services are disabled in macOS Settings.")
            return
        }

        beginLocationRequest()
        NSApp.activate(ignoringOtherApps: true)
        manager.requestLocation()
    }

    private func beginLocationRequest() {
        isRequestInProgress = true
        lastRequestAt = Date()
        lastErrorDescription = nil
    }

    private func failRequest(with message: String) {
        isRequestInProgress = false
        lastErrorDescription = message
    }
}

@MainActor
extension CurrentLocationStore: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if isAuthorized {
            requestCurrentLocation()
        } else if authorizationStatus == .denied {
            failRequest(with: "Location access is denied. Open macOS Location Services and allow this app.")
        } else if authorizationStatus == .restricted {
            failRequest(with: "Location access is restricted on this Mac.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latestLocation = locations.last
        currentLocation = latestLocation
        currentCoordinate = latestLocation?.coordinate
        lastLocationAt = latestLocation?.timestamp ?? Date()
        isRequestInProgress = false
        lastErrorDescription = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failRequest(with: Self.errorMessage(from: error))
    }
}

private extension CurrentLocationStore {
    var isAuthorized: Bool {
        authorizationStatus.isNomadWeatherAuthorized
    }

    static func errorMessage(from error: Error) -> String {
        if let error = error as? CLError {
            switch error.code {
            case .denied:
                return "Location access is denied. Open macOS Location Services and allow this app."
            case .locationUnknown:
                return "macOS could not determine your location yet. Try again in a moment."
            case .network:
                return "macOS could not reach location services. Check your network connection."
            default:
                return error.localizedDescription
            }
        }

        return error.localizedDescription
    }
}
