import CoreLocation
import NomadCore
import SwiftUI

/// Text-field state for the surf spot group. It lives above the pages so a location request started on the
/// Weather & Local page still fills the fields when the location arrives after another page was selected.
@MainActor
final class SurfSpotFormModel: ObservableObject {
    @Published private(set) var nameText: String
    @Published private(set) var latitudeText: String
    @Published private(set) var longitudeText: String
    @Published private(set) var isAwaitingLocation = false

    private let settingsStore: AppSettingsStore

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        nameText = settingsStore.settings.surfSpotName
        latitudeText = Self.coordinateText(for: settingsStore.settings.surfSpotLatitude)
        longitudeText = Self.coordinateText(for: settingsStore.settings.surfSpotLongitude)
    }

    var nameBinding: Binding<String> {
        Binding(
            get: { self.nameText },
            set: { newValue in
                self.nameText = newValue
                self.settingsStore.settings.surfSpotName = newValue
            }
        )
    }

    var latitudeBinding: Binding<String> {
        Binding(
            get: { self.latitudeText },
            set: { newValue in
                self.latitudeText = newValue
                self.settingsStore.settings.surfSpotLatitude = Self.parsedCoordinate(from: newValue)
            }
        )
    }

    var longitudeBinding: Binding<String> {
        Binding(
            get: { self.longitudeText },
            set: { newValue in
                self.longitudeText = newValue
                self.settingsStore.settings.surfSpotLongitude = Self.parsedCoordinate(from: newValue)
            }
        )
    }

    var validationMessage: String? {
        let normalizedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let latitude = Self.parsedCoordinate(from: latitudeText)
        let longitude = Self.parsedCoordinate(from: longitudeText)
        let hasAnyInput = normalizedName.isEmpty == false
            || latitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || longitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        guard hasAnyInput else {
            return nil
        }

        if normalizedName.isEmpty {
            return "Add a surf spot name."
        }

        if latitude == nil || ((-90.0)...90.0).contains(latitude ?? 0) == false {
            return "Latitude must be between -90 and 90."
        }

        if longitude == nil || ((-180.0)...180.0).contains(longitude ?? 0) == false {
            return "Longitude must be between -180 and 180."
        }

        return nil
    }

    func syncFromSettings() {
        nameText = settingsStore.settings.surfSpotName
        latitudeText = Self.coordinateText(for: settingsStore.settings.surfSpotLatitude)
        longitudeText = Self.coordinateText(for: settingsStore.settings.surfSpotLongitude)
    }

    func useCurrentLocation(snapshotStore: DashboardSnapshotStore, locationStore: CurrentLocationStore) {
        guard let location = locationStore.currentLocation else {
            snapshotStore.setCurrentLocation(locationStore.currentLocation)
            isAwaitingLocation = true

            if locationStore.diagnostics.isLocationServicesEnabled == false {
                CurrentLocationStore.openLocationPrivacySettings()
                return
            }

            switch locationStore.authorizationStatus {
            case .notDetermined:
                locationStore.requestAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationStore.requestCurrentLocation()
            case .denied, .restricted:
                CurrentLocationStore.openLocationPrivacySettings()
            @unknown default:
                CurrentLocationStore.openLocationPrivacySettings()
            }

            return
        }

        applyCoordinate(from: location)
    }

    /// Completes a "Use Current Location" request once a location is available.
    func fillFromLocationIfAwaiting(_ location: CLLocation?) {
        guard isAwaitingLocation, let location else {
            return
        }

        applyCoordinate(from: location)
        isAwaitingLocation = false
    }

    private func applyCoordinate(from location: CLLocation) {
        if nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameText = "Current Spot"
            settingsStore.settings.surfSpotName = nameText
        }

        latitudeText = Self.coordinateText(for: location.coordinate.latitude)
        longitudeText = Self.coordinateText(for: location.coordinate.longitude)
        settingsStore.settings.surfSpotLatitude = location.coordinate.latitude
        settingsStore.settings.surfSpotLongitude = location.coordinate.longitude
    }

    private static func parsedCoordinate(from value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private static func coordinateText(for value: Double?) -> String {
        guard let value else {
            return ""
        }

        return String(format: "%.5f", value)
    }
}
