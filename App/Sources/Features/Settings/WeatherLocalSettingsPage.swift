import NomadCore
import NomadUI
import SwiftUI

struct WeatherLocalSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var navigationController: SettingsNavigationController
    @ObservedObject var surfSpotForm: SurfSpotFormModel

    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case surfSpotName
        case hudUserAPIToken
        case tankerkonigAPIKey
    }

    var body: some View {
        SettingsPageForm(
            page: .weatherAndLocal,
            navigationController: navigationController,
            onFocus: focusField(for:)
        ) {
            weatherSection
            airQualitySection
            surfSpotSection
            localInfoSection
            fuelPricesSection
        }
    }

    private func focusField(for target: SettingsFocusTarget) {
        guard target == .surfSpot else {
            return
        }

        DispatchQueue.main.async {
            focusedField = .surfSpotName
        }
    }

    private var weatherSection: some View {
        Section {
            Toggle("Use current location for weather", isOn: weatherLocationBinding)
                .id(SettingsFocusTarget.weather.rawValue)
        } header: {
            Text("Weather")
        }
    }

    /// Air quality is fetched for the weather location, so it follows the weather location setting.
    private var airQualitySection: some View {
        Section {
            Toggle(StaySettingsPresentation.airQualityToggleTitle, isOn: settingsStore.binding(\.airQualityEnabled))
                .disabled(settingsStore.settings.useCurrentLocationForWeather == false)

            if settingsStore.settings.useCurrentLocationForWeather == false {
                Text(StaySettingsPresentation.airQualityNeedsLocationExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(StaySettingsPresentation.airQualityTitle)
        } footer: {
            Text(StaySettingsPresentation.airQualityFooter)
        }
    }

    private var surfSpotSection: some View {
        Section {
            TextField("Spot name", text: surfSpotForm.nameBinding)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .surfSpotName)
                .id(SettingsFocusTarget.surfSpot.rawValue)

            HStack(spacing: 12) {
                TextField("Latitude", text: surfSpotForm.latitudeBinding)
                    .textFieldStyle(.roundedBorder)

                TextField("Longitude", text: surfSpotForm.longitudeBinding)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()

                Button("Use Current Location") {
                    surfSpotForm.useCurrentLocation(snapshotStore: snapshotStore, locationStore: locationStore)
                }
                .disabled(locationStore.diagnostics.isRequestInProgress)
            }

            if let validationMessage = surfSpotForm.validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if surfSpotForm.isAwaitingLocation, let detail = locationStore.diagnostics.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Surf spot")
        } footer: {
            Text("Add one surf spot for wave, swell, wind, and sea-surface context. Surf data uses Open-Meteo; local weather and alerts continue to use WeatherKit.")
        }
    }

    private var localInfoSection: some View {
        Section {
            Toggle(
                "Show local info",
                isOn: settingsStore.locationAwareBinding(\.localInfoEnabled, snapshotStore: snapshotStore, locationStore: locationStore)
            )
            .id(SettingsFocusTarget.localInfo.rawValue)

            TextField("HUD USER API token (US rent in Local Info)", text: settingsStore.binding(\.hudUserAPIToken))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .hudUserAPIToken)

            if let hudUserConfigurationMessage {
                Text(hudUserConfigurationMessage)
                    .font(.caption)
                    .foregroundStyle(hudUserConfigurationWarning ? .orange : .secondary)
            }

            Link("Get a HUD USER API token", destination: URL(string: "https://www.huduser.gov/portal/dataset/fmr-api.html")!)
                .font(.caption)
        } header: {
            Text("Local Info")
        } footer: {
            Text("Local Info combines location context, public holiday data, best-effort school holiday data, and local price signals. Price signals use official public datasets: Eurostat for country-level European price context and, when configured, HUD USER plus the US Census Geocoder for the US 1-bedroom rent benchmark.")
        }
    }

    private var fuelPricesSection: some View {
        Section {
            Toggle(
                "Show nearby fuel prices",
                isOn: settingsStore.locationAwareBinding(\.fuelPricesEnabled, snapshotStore: snapshotStore, locationStore: locationStore)
            )
            .id(SettingsFocusTarget.fuelPrices.rawValue)

            TextField("Tankerkönig API key (Germany only)", text: settingsStore.binding(\.tankerkonigAPIKey))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .tankerkonigAPIKey)

            if let tankerkonigConfigurationMessage {
                Text(tankerkonigConfigurationMessage)
                    .font(.caption)
                    .foregroundStyle(tankerkonigConfigurationWarning ? .orange : .secondary)
            }

            Link("Get a Tankerkönig API key", destination: URL(string: "https://creativecommons.tankerkoenig.de/")!)
                .font(.caption)
        } header: {
            Text("Fuel prices")
        } footer: {
            Text("Fuel price support is country-dependent and currently best in Spain, France, Italy, and Germany. Germany requires your own Tankerkönig API key, while Spain, France, and Italy work without one.")
        }
    }

    private var weatherLocationBinding: Binding<Bool> {
        settingsStore.locationAwareBinding(\.useCurrentLocationForWeather, snapshotStore: snapshotStore, locationStore: locationStore)
    }

    private var tankerkonigConfigurationWarning: Bool {
        guard let diagnostics = snapshotStore.snapshot.fuelDiagnostics else {
            return false
        }

        return diagnostics.status == .configurationRequired && diagnostics.countryCode == "DE"
    }

    private var hudUserConfigurationWarning: Bool {
        snapshotStore.snapshot.localInfo?.localPriceLevel?.status == .configurationRequired
            && snapshotStore.snapshot.localInfo?.localPriceLevel?.countryCode == "US"
    }

    private var hudUserConfigurationMessage: String? {
        if hudUserConfigurationWarning {
            return "US 1BR rent inside Local Info needs a valid HUD USER API token. Add it here, then refresh."
        }

        if settingsStore.settings.hudUserAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Only needed for the optional US 1-bedroom rent row inside Local Info. Europe price signals work without it."
        }

        return "Stored locally in app settings and used only for HUD 1-bedroom rent lookups on this Mac."
    }

    private var tankerkonigConfigurationMessage: String? {
        if tankerkonigConfigurationWarning {
            return "Germany fuel prices need your Tankerkönig API key. Add it here, then refresh."
        }

        if settingsStore.settings.tankerkonigAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Only needed for Germany. Leave blank unless you want Germany fuel prices."
        }

        return "Stored locally in app settings and used only for Germany fuel lookups on this Mac."
    }
}
