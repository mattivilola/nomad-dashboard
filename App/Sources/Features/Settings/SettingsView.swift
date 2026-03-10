import AppKit
import CoreLocation
import NomadCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    @ObservedObject var settingsNavigationController: SettingsNavigationController
    let updatesEnabled: Bool

    @State private var surfSpotNameText: String
    @State private var surfSpotLatitudeText: String
    @State private var surfSpotLongitudeText: String
    @State private var pendingSurfSpotFillFromLocation = false

    @FocusState private var focusedField: FocusField?

    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    private enum FocusField: Hashable {
        case surfSpotName
    }

    init(
        settingsStore: AppSettingsStore,
        snapshotStore: DashboardSnapshotStore,
        locationStore: CurrentLocationStore,
        launchAtLoginController: LaunchAtLoginController,
        settingsNavigationController: SettingsNavigationController,
        updatesEnabled: Bool
    ) {
        self.settingsStore = settingsStore
        self.snapshotStore = snapshotStore
        self.locationStore = locationStore
        self.launchAtLoginController = launchAtLoginController
        self.settingsNavigationController = settingsNavigationController
        self.updatesEnabled = updatesEnabled
        _surfSpotNameText = State(initialValue: settingsStore.settings.surfSpotName)
        _surfSpotLatitudeText = State(initialValue: Self.coordinateText(for: settingsStore.settings.surfSpotLatitude))
        _surfSpotLongitudeText = State(initialValue: Self.coordinateText(for: settingsStore.settings.surfSpotLongitude))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))

                    Text("Manage startup behavior, privacy, and refresh cadence for Nomad Dashboard.")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Image(nsImage: AppRuntimeInfo.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                    .accessibilityHidden(true)
            }

            ScrollViewReader { proxy in
                Form {
                    Section {
                        Picker("Appearance", selection: binding(\.appearanceMode)) {
                            ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                                Text(mode.displayName)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Launch at login", isOn: launchAtLoginBinding)

                        if updatesEnabled {
                            Toggle("Check for updates automatically", isOn: binding(\.automaticUpdateChecksEnabled))
                        } else {
                            LabeledContent("Updates") {
                                Text("Paused")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("General")
                    } footer: {
                        Text(updatesEnabled ? "System follows your macOS appearance. The dashboard header button flips quickly between dark and light, and all preferences stay across relaunches." : "System follows your macOS appearance. The dashboard header button flips quickly between dark and light, and all preferences stay across relaunches. In-app update checks only become available in signed release builds that include Sparkle metadata.")
                    }

                    Section {
                        Toggle("Use current location for weather", isOn: weatherLocationBinding)
                        Toggle("Show nearby fuel prices", isOn: fuelPricesBinding)
                        Toggle("Show external IP location", isOn: binding(\.publicIPGeolocationEnabled))
                        Toggle("Save visited places locally", isOn: visitedPlacesBinding)

                        LabeledContent("Location status") {
                            Text(locationStore.authorizationSummary)
                                .foregroundStyle(.secondary)
                        }

                        if let detail = locationStore.diagnostics.detailText {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(locationActionTitle) {
                            handleLocationAction()
                        }
                        .disabled(locationStore.diagnostics.isRequestInProgress)
                    } header: {
                        Text("Privacy & Location")
                    } footer: {
                        Text("Weather, nearby fuel prices, and local weather alerts use device location only when you opt in. Fuel price support is country-dependent and currently best in Spain, France, Italy, and Germany. External IP lookups use a third-party geolocation service to show city and country, and that display is on by default for new installs. Visited places stay on this Mac until you clear them.")
                    }

                    Section {
                        TextField("Spot name", text: surfSpotNameBinding)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .surfSpotName)
                            .id(SettingsFocusTarget.surfSpot.rawValue)

                        HStack(spacing: 12) {
                            TextField("Latitude", text: surfSpotLatitudeBinding)
                                .textFieldStyle(.roundedBorder)

                            TextField("Longitude", text: surfSpotLongitudeBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Spacer()

                            Button("Use Current Location") {
                                useCurrentLocationForSurfSpot()
                            }
                            .disabled(locationStore.diagnostics.isRequestInProgress)
                        }

                        if let surfSpotValidationMessage {
                            Text(surfSpotValidationMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if pendingSurfSpotFillFromLocation, let detail = locationStore.diagnostics.detailText {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Surf Spot")
                    } footer: {
                        Text("Add one surf spot for wave, swell, wind, and sea-surface context. Surf data uses Open-Meteo; local weather and alerts continue to use WeatherKit.")
                    }

                    Section {
                        Toggle("Travel advisory", isOn: binding(\.travelAdvisoryEnabled))
                        Toggle("Weather alerts", isOn: travelWeatherAlertsBinding)
                        Toggle("Regional security", isOn: binding(\.regionalSecurityEnabled))
                    } header: {
                        Text("Travel Alerts")
                    } footer: {
                        Text("Travel advisory uses Smartraveller by default and starts enabled. Regional security uses ReliefWeb, and weather alerts use WeatherKit. Advisory and security check your current country plus bordering countries; weather alerts use your current location when available.")
                    }

                    Section {
                        Stepper(value: fastRefreshBinding, in: 2...10) {
                            LabeledContent("Fast refresh") {
                                Text("\(fastRefreshValue) seconds")
                                    .monospacedDigit()
                            }
                        }

                        Stepper(value: slowRefreshBinding, in: 30...300, step: 15) {
                            LabeledContent("Slow refresh") {
                                Text("\(slowRefreshValue) seconds")
                                    .monospacedDigit()
                            }
                        }

                        Stepper(value: binding(\.historyRetentionHours), in: 6...72) {
                            LabeledContent("Metric retention") {
                                Text("\(settingsStore.settings.historyRetentionHours) hours")
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Refresh & History")
                    } footer: {
                        Text("Fast refresh controls lightweight polling. Slow refresh covers heavier network, power, location, and weather lookups.")
                    }

                    Section {
                        LabeledContent("Version", value: AppRuntimeInfo.versionDescription)

                        if updatesEnabled {
                            Button("Check for Updates") {
                                snapshotStore.checkForUpdates()
                            }
                        } else {
                            Text(UpdateFeatureConfiguration.pausedReason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button("About Nomad Dashboard") {
                            openAndActivateWindow(.about, with: openWindow)
                        }

                        Button("Open Visited Map") {
                            openAndActivateWindow(.visitedMap, with: openWindow)
                        }

                        DisclosureGroup("Fuel Diagnostics") {
                            if let diagnostics = snapshotStore.snapshot.fuelDiagnostics {
                                LabeledContent("Status") {
                                    Text(diagnostics.status.rawValue.capitalized)
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Stage") {
                                    Text(diagnostics.stage.displayName)
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Provider") {
                                    Text(diagnostics.providerName ?? "n/a")
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Country") {
                                    Text(fuelDiagnosticsCountryText(diagnostics))
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Coordinate") {
                                    Text(diagnostics.coordinateDescription)
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Last Attempt") {
                                    Text(fuelDiagnosticsTimestampText(diagnostics.finishedAt))
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Elapsed") {
                                    Text(diagnostics.elapsedMilliseconds.map { "\($0) ms" } ?? "n/a")
                                        .foregroundStyle(.secondary)
                                }

                                LabeledContent("Summary") {
                                    Text(diagnostics.summary)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }

                                if let error = diagnostics.error {
                                    LabeledContent("Failure Kind") {
                                        Text(error.failureKind?.displayName ?? "n/a")
                                            .foregroundStyle(.secondary)
                                    }

                                    LabeledContent("Error") {
                                        Text(fuelDiagnosticsErrorText(error))
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }

                                    if let failingURL = error.failingURL?.absoluteString {
                                        LabeledContent("Failing URL") {
                                            Text(failingURL)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }

                                HStack {
                                    Button("Refresh Fuel Diagnostics") {
                                        Task {
                                            await snapshotStore.refresh(manual: true)
                                        }
                                    }

                                    Button("Copy Fuel Diagnostics") {
                                        copyFuelDiagnostics()
                                    }
                                }
                                .padding(.top, 4)
                            } else {
                                Text("No fuel fetch attempts yet.")
                                    .foregroundStyle(.secondary)

                                Button("Refresh Fuel Diagnostics") {
                                    Task {
                                        await snapshotStore.refresh(manual: true)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Support")
                    }
                }
                .formStyle(.grouped)
                .onReceive(settingsNavigationController.$focusRequest.compactMap(\.self)) { request in
                    guard request.target == .surfSpot else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(SettingsFocusTarget.surfSpot.rawValue, anchor: .top)
                    }

                    DispatchQueue.main.async {
                        focusedField = .surfSpotName
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520, alignment: .topLeading)
        .onAppear {
            syncSurfSpotFields()
        }
        .onReceive(locationStore.$currentLocation) { location in
            snapshotStore.setCurrentLocation(location)

            if pendingSurfSpotFillFromLocation, let location {
                applySurfSpotCoordinate(from: location)
                pendingSurfSpotFillFromLocation = false
            }

            guard settingsStore.settings.usesDeviceLocation else {
                return
            }

            Task {
                await snapshotStore.refresh(manual: true)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginController.isEnabled },
            set: { newValue in
                launchAtLoginController.setEnabled(newValue)
                settingsStore.settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
            }
        )
    }

    private var weatherLocationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.useCurrentLocationForWeather },
            set: { isEnabled in
                settingsStore.settings.useCurrentLocationForWeather = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var travelWeatherAlertsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.travelWeatherAlertsEnabled },
            set: { isEnabled in
                settingsStore.settings.travelWeatherAlertsEnabled = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var fuelPricesBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.fuelPricesEnabled },
            set: { isEnabled in
                settingsStore.settings.fuelPricesEnabled = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var visitedPlacesBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.visitedPlacesEnabled },
            set: { isEnabled in
                settingsStore.settings.visitedPlacesEnabled = isEnabled
                snapshotStore.setCurrentLocation(locationStore.currentLocation)

                if settingsStore.settings.usesDeviceLocation {
                    locationStore.prepareForWeather()
                }
            }
        )
    }

    private var fastRefreshBinding: Binding<Int> {
        Binding(
            get: { fastRefreshValue },
            set: { settingsStore.settings.refreshIntervalSeconds = Double($0) }
        )
    }

    private var slowRefreshBinding: Binding<Int> {
        Binding(
            get: { slowRefreshValue },
            set: { settingsStore.settings.slowRefreshIntervalSeconds = Double($0) }
        )
    }

    private var fastRefreshValue: Int {
        Int(settingsStore.settings.refreshIntervalSeconds)
    }

    private var slowRefreshValue: Int {
        Int(settingsStore.settings.slowRefreshIntervalSeconds)
    }

    private var locationActionTitle: String {
        if locationStore.diagnostics.isRequestInProgress {
            return "Requesting Location…"
        }

        if locationStore.diagnostics.isLocationServicesEnabled == false {
            return "Open Location Settings"
        }

        return switch locationStore.authorizationStatus {
        case .notDetermined:
            "Request Location Access"
        case .denied, .restricted:
            "Open Location Settings"
        case .authorizedAlways, .authorizedWhenInUse:
            "Refresh Current Location"
        @unknown default:
            "Open Location Settings"
        }
    }

    private func handleLocationAction() {
        if locationStore.diagnostics.isLocationServicesEnabled == false {
            openLocationSettings()
            return
        }

        switch locationStore.authorizationStatus {
        case .notDetermined:
            locationStore.requestAuthorization()
        case .denied, .restricted:
            openLocationSettings()
        case .authorizedAlways, .authorizedWhenInUse:
            snapshotStore.setCurrentLocation(locationStore.currentLocation)
            locationStore.requestCurrentLocation()
        @unknown default:
            openLocationSettings()
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }

        openURL(url)
    }

    private var surfSpotNameBinding: Binding<String> {
        Binding(
            get: { surfSpotNameText },
            set: { newValue in
                surfSpotNameText = newValue
                settingsStore.settings.surfSpotName = newValue
            }
        )
    }

    private var surfSpotLatitudeBinding: Binding<String> {
        Binding(
            get: { surfSpotLatitudeText },
            set: { newValue in
                surfSpotLatitudeText = newValue
                settingsStore.settings.surfSpotLatitude = parsedCoordinate(from: newValue)
            }
        )
    }

    private var surfSpotLongitudeBinding: Binding<String> {
        Binding(
            get: { surfSpotLongitudeText },
            set: { newValue in
                surfSpotLongitudeText = newValue
                settingsStore.settings.surfSpotLongitude = parsedCoordinate(from: newValue)
            }
        )
    }

    private var surfSpotValidationMessage: String? {
        let normalizedName = surfSpotNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let latitude = parsedCoordinate(from: surfSpotLatitudeText)
        let longitude = parsedCoordinate(from: surfSpotLongitudeText)
        let hasAnyInput = normalizedName.isEmpty == false
            || surfSpotLatitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || surfSpotLongitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

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

    private func useCurrentLocationForSurfSpot() {
        guard let location = locationStore.currentLocation else {
            snapshotStore.setCurrentLocation(locationStore.currentLocation)
            pendingSurfSpotFillFromLocation = true

            if locationStore.diagnostics.isLocationServicesEnabled == false {
                openLocationSettings()
                return
            }

            switch locationStore.authorizationStatus {
            case .notDetermined:
                locationStore.requestAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationStore.requestCurrentLocation()
            case .denied, .restricted:
                openLocationSettings()
            @unknown default:
                openLocationSettings()
            }

            return
        }

        applySurfSpotCoordinate(from: location)
    }

    private func applySurfSpotCoordinate(from location: CLLocation) {
        if surfSpotNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            surfSpotNameText = "Current Spot"
            settingsStore.settings.surfSpotName = surfSpotNameText
        }

        let latitude = Self.coordinateText(for: location.coordinate.latitude)
        let longitude = Self.coordinateText(for: location.coordinate.longitude)
        surfSpotLatitudeText = latitude
        surfSpotLongitudeText = longitude
        settingsStore.settings.surfSpotLatitude = location.coordinate.latitude
        settingsStore.settings.surfSpotLongitude = location.coordinate.longitude
    }

    private func syncSurfSpotFields() {
        surfSpotNameText = settingsStore.settings.surfSpotName
        surfSpotLatitudeText = Self.coordinateText(for: settingsStore.settings.surfSpotLatitude)
        surfSpotLongitudeText = Self.coordinateText(for: settingsStore.settings.surfSpotLongitude)
    }

    private func parsedCoordinate(from value: String) -> Double? {
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

    private func fuelDiagnosticsCountryText(_ diagnostics: FuelDiagnosticsSnapshot) -> String {
        [diagnostics.countryName, diagnostics.countryCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
            .nilIfEmpty ?? "n/a"
    }

    private func fuelDiagnosticsErrorText(_ error: FuelDiagnosticsError) -> String {
        var components: [String] = []

        if let domain = error.domain {
            if let code = error.code {
                components.append("\(domain) (\(code))")
            } else {
                components.append(domain)
            }
        }

        if let urlErrorSymbol = error.urlErrorSymbol {
            components.append(urlErrorSymbol)
        }

        if let httpStatusCode = error.httpStatusCode {
            components.append("HTTP \(httpStatusCode)")
        }

        components.append(error.localizedDescription)
        return components.joined(separator: " · ")
    }

    private func fuelDiagnosticsTimestampText(_ date: Date?) -> String {
        guard let date else {
            return "n/a"
        }

        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func copyFuelDiagnostics() {
        guard let diagnostics = snapshotStore.snapshot.fuelDiagnostics else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            diagnostics.reportText(fuelPrices: snapshotStore.snapshot.fuelPrices),
            forType: .string
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
