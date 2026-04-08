import Foundation
import NomadCore
import Testing

@MainActor
struct AppSettingsStoreTests {
    @Test
    func freshStoresUseSystemAppearanceByDefault() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)

        #expect(store.settings.appearanceMode == .system)
        #expect(store.settings.dashboardCardOrder == DashboardCardID.defaultOrder)
        #expect(store.settings.dashboardCardWidthModes == DashboardCardID.defaultWidthModes)
        #expect(store.settings.publicIPGeolocationEnabled == true)
        #expect(store.settings.shareAnonymousAnalytics == true)
        #expect(store.settings.visitedPlacesEnabled == true)
        #expect(store.settings.localPriceLevelEnabled == false)
        #expect(store.settings.fuelPricesEnabled == false)
        #expect(store.settings.emergencyCareEnabled == false)
        #expect(store.settings.travelAdvisoryEnabled == true)
        #expect(store.settings.travelWeatherAlertsEnabled == false)
        #expect(store.settings.regionalSecurityEnabled == false)
        #expect(store.settings.projectTimeTrackingEnabled == false)
        #expect(store.settings.timeTrackingProjects.isEmpty)
        #expect(store.settings.hudUserAPIToken.isEmpty)
        #expect(store.settings.tankerkonigAPIKey.isEmpty)
        #expect(store.settings.surfSpotName.isEmpty)
        #expect(store.settings.surfSpotLatitude == nil)
        #expect(store.settings.surfSpotLongitude == nil)
        #expect(store.settings.weatherForecastExpanded == false)
    }

    @Test
    func persistsAppearanceModeChangesToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)

        for mode in AppAppearanceMode.allCases {
            store.settings.appearanceMode = mode

            let reloaded = AppSettingsStore(defaults: defaults)
            #expect(reloaded.settings.appearanceMode == mode)
        }
    }

    @Test
    func storageNamespacesResolveExpectedLiveAndDevValues() {
        #expect(NomadStorageNamespace.production.settingsKey == "NomadDashboard.AppSettings")
        #expect(NomadStorageNamespace.production.applicationSupportFolderName == "Nomad Dashboard")
        #expect(NomadStorageNamespace.development.settingsKey == "NomadDashboard.Dev.AppSettings")
        #expect(NomadStorageNamespace.development.applicationSupportFolderName == "Nomad Dashboard Dev")
    }

    @Test
    func appSettingsStoreCanPersistToCustomNamespaceKeyWithoutTouchingLegacyKey() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let legacyStore = AppSettingsStore(defaults: defaults)
        let devStore = AppSettingsStore(defaults: defaults, key: NomadStorageNamespace.development.settingsKey)

        legacyStore.settings.projectTimeTrackingEnabled = true
        legacyStore.settings.timeTrackingProjects = [TimeTrackingProject(name: "Live Project")]

        devStore.settings.projectTimeTrackingEnabled = true
        devStore.settings.timeTrackingProjects = [TimeTrackingProject(name: "Dev Project")]

        let reloadedLegacyStore = AppSettingsStore(defaults: defaults)
        let reloadedDevStore = AppSettingsStore(defaults: defaults, key: NomadStorageNamespace.development.settingsKey)

        #expect(reloadedLegacyStore.settings.timeTrackingProjects.map(\.trimmedName) == ["Live Project"])
        #expect(reloadedDevStore.settings.timeTrackingProjects.map(\.trimmedName) == ["Dev Project"])
    }

    @Test
    func fileManagerResolvesSeparateApplicationSupportDirectoriesPerNamespace() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        let liveURL = try FileManager.default.nomadApplicationSupportDirectory(
            namespace: .production,
            baseURL: baseURL
        )
        let devURL = try FileManager.default.nomadApplicationSupportDirectory(
            namespace: .development,
            baseURL: baseURL
        )

        #expect(liveURL.lastPathComponent == "Nomad Dashboard")
        #expect(devURL.lastPathComponent == "Nomad Dashboard Dev")
        #expect(liveURL != devURL)
        #expect(FileManager.default.fileExists(atPath: liveURL.path))
        #expect(FileManager.default.fileExists(atPath: devURL.path))
    }

    @Test
    func persistsDashboardCardOrderChangesToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        let reordered: [DashboardCardID] = [
            .weather,
            .travelAlerts,
            .fuelPrices,
            .emergencyCare,
            .localPriceLevel,
            .travelContext,
            .timeTracking,
            .power,
            .connectivity
        ]

        store.settings.dashboardCardOrder = reordered

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.dashboardCardOrder == reordered)
    }

    @Test
    func persistsDashboardCardWidthModeChangesToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.dashboardCardWidthModes[.connectivity] = .narrow
        store.settings.dashboardCardWidthModes[.weather] = .narrow

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.dashboardCardWidthModes[.connectivity] == .narrow)
        #expect(reloaded.settings.dashboardCardWidthModes[.weather] == .narrow)
        #expect(reloaded.settings.dashboardCardWidthModes[.power] == .wide)
    }

    @Test
    func persistsWeatherForecastDisclosureStateToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.weatherForecastExpanded = true

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.weatherForecastExpanded == true)
    }

    @Test
    func appSettingsDecodingMigratesLegacyWeatherDisclosureFlags() throws {
        let payload = """
        {
          "appearanceMode": "system",
          "dashboardCardOrder": ["travelContext", "connectivity", "power", "weather", "travelAlerts", "fuelPrices", "emergencyCare", "timeTracking"],
          "dashboardCardWidthModes": {
            "travelContext": "wide",
            "connectivity": "wide",
            "power": "wide",
            "weather": "wide",
            "travelAlerts": "wide",
            "fuelPrices": "wide",
            "emergencyCare": "wide",
            "timeTracking": "wide"
          },
          "refreshIntervalSeconds": 2,
          "slowRefreshIntervalSeconds": 60,
          "historyRetentionHours": 24,
          "publicIPGeolocationEnabled": true,
          "shareAnonymousAnalytics": true,
          "automaticUpdateChecksEnabled": true,
          "launchAtLoginEnabled": false,
          "useCurrentLocationForWeather": true,
          "weatherHourlyForecastExpanded": true,
          "weatherDailyForecastExpanded": false,
          "fuelPricesEnabled": false,
          "emergencyCareEnabled": false,
          "visitedPlacesEnabled": true,
          "travelAdvisoryEnabled": true,
          "travelWeatherAlertsEnabled": false,
          "regionalSecurityEnabled": false,
          "projectTimeTrackingEnabled": false,
          "timeTrackingProjects": [],
          "tankerkonigAPIKey": "",
          "surfSpotName": "",
          "latencyHosts": ["1.1.1.1:443", "8.8.8.8:443"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        #expect(decoded.weatherForecastExpanded == true)
    }

    @Test
    func appSettingsDecodingKeepsUnifiedForecastExpandedWhenBothLegacyDisclosuresWereOpen() throws {
        let payload = """
        {
          "appearanceMode": "system",
          "dashboardCardOrder": ["travelContext", "connectivity", "power", "weather", "travelAlerts", "fuelPrices", "emergencyCare", "timeTracking"],
          "dashboardCardWidthModes": {
            "travelContext": "wide",
            "connectivity": "wide",
            "power": "wide",
            "weather": "wide",
            "travelAlerts": "wide",
            "fuelPrices": "wide",
            "emergencyCare": "wide",
            "timeTracking": "wide"
          },
          "refreshIntervalSeconds": 2,
          "slowRefreshIntervalSeconds": 60,
          "historyRetentionHours": 24,
          "publicIPGeolocationEnabled": true,
          "shareAnonymousAnalytics": true,
          "automaticUpdateChecksEnabled": true,
          "launchAtLoginEnabled": false,
          "useCurrentLocationForWeather": true,
          "weatherHourlyForecastExpanded": true,
          "weatherDailyForecastExpanded": true,
          "fuelPricesEnabled": false,
          "emergencyCareEnabled": false,
          "visitedPlacesEnabled": true,
          "travelAdvisoryEnabled": true,
          "travelWeatherAlertsEnabled": false,
          "regionalSecurityEnabled": false,
          "projectTimeTrackingEnabled": false,
          "timeTrackingProjects": [],
          "tankerkonigAPIKey": "",
          "surfSpotName": "",
          "latencyHosts": ["1.1.1.1:443", "8.8.8.8:443"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        #expect(decoded.weatherForecastExpanded == true)
    }

    @Test
    func preservesPersistedDisabledPublicIPLocationPreference() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.publicIPGeolocationEnabled = false

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.publicIPGeolocationEnabled == false)
    }

    @Test
    func preservesPersistedAnonymousAnalyticsPreference() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.shareAnonymousAnalytics = false

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.shareAnonymousAnalytics == false)
    }

    @Test
    func persistsTravelAlertPreferencesToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.travelAdvisoryEnabled = false
        store.settings.travelWeatherAlertsEnabled = true
        store.settings.regionalSecurityEnabled = true

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.travelAdvisoryEnabled == false)
        #expect(reloaded.settings.travelWeatherAlertsEnabled == true)
        #expect(reloaded.settings.regionalSecurityEnabled == true)
    }

    @Test
    func persistsTimeTrackingConfigurationToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        let project = TimeTrackingProject(name: "Client A")
        store.settings.projectTimeTrackingEnabled = true
        store.settings.timeTrackingProjects = [project]

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.projectTimeTrackingEnabled == true)
        #expect(reloaded.settings.timeTrackingProjects == [project])
        #expect(reloaded.settings.activeTimeTrackingProjects == [project])
    }

    @Test
    func persistsSurfSpotToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.surfSpotName = "El Saler"
        store.settings.surfSpotLatitude = 39.355
        store.settings.surfSpotLongitude = -0.314

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.surfSpotName == "El Saler")
        #expect(reloaded.settings.surfSpotLatitude == 39.355)
        #expect(reloaded.settings.surfSpotLongitude == -0.314)
        #expect(reloaded.settings.surfSpotConfiguration.isValid)
    }

    @Test
    func persistsTankerkonigAPIKeyToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.tankerkonigAPIKey = "user-key-123"

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.tankerkonigAPIKey == "user-key-123")
    }

    @Test
    func persistsEmergencyCarePreferenceToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.emergencyCareEnabled = true

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.emergencyCareEnabled == true)
    }

    @Test
    func decodesLegacyPayloadWithoutAppearanceMode() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let legacyPayload = LegacyAppSettingsPayload(
            refreshIntervalSeconds: 5,
            slowRefreshIntervalSeconds: 120,
            historyRetentionHours: 36,
            publicIPGeolocationEnabled: false,
            automaticUpdateChecksEnabled: false,
            launchAtLoginEnabled: true,
            useCurrentLocationForWeather: false,
            latencyHosts: ["example.com:443"]
        )
        let data = try JSONEncoder().encode(legacyPayload)
        defaults.set(data, forKey: "NomadDashboard.AppSettings")

        let store = AppSettingsStore(defaults: defaults)

        #expect(store.settings.appearanceMode == .system)
        #expect(store.settings.dashboardCardOrder == DashboardCardID.defaultOrder)
        #expect(store.settings.dashboardCardWidthModes == DashboardCardID.defaultWidthModes)
        #expect(store.settings.refreshIntervalSeconds == 5)
        #expect(store.settings.slowRefreshIntervalSeconds == 120)
        #expect(store.settings.historyRetentionHours == 36)
        #expect(store.settings.publicIPGeolocationEnabled == false)
        #expect(store.settings.shareAnonymousAnalytics == true)
        #expect(store.settings.automaticUpdateChecksEnabled == false)
        #expect(store.settings.launchAtLoginEnabled == true)
        #expect(store.settings.useCurrentLocationForWeather == false)
        #expect(store.settings.localPriceLevelEnabled == false)
        #expect(store.settings.fuelPricesEnabled == false)
        #expect(store.settings.emergencyCareEnabled == false)
        #expect(store.settings.visitedPlacesEnabled == false)
        #expect(store.settings.travelAdvisoryEnabled == true)
        #expect(store.settings.travelWeatherAlertsEnabled == false)
        #expect(store.settings.regionalSecurityEnabled == false)
        #expect(store.settings.projectTimeTrackingEnabled == false)
        #expect(store.settings.timeTrackingProjects.isEmpty)
        #expect(store.settings.hudUserAPIToken.isEmpty)
        #expect(store.settings.tankerkonigAPIKey.isEmpty)
        #expect(store.settings.surfSpotName.isEmpty)
        #expect(store.settings.surfSpotLatitude == nil)
        #expect(store.settings.surfSpotLongitude == nil)
        #expect(store.settings.weatherForecastExpanded == false)
        #expect(store.settings.latencyHosts == ["example.com:443"])
    }

    @Test
    func sanitizesInvalidPersistedDashboardCardOrder() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let payload = InvalidDashboardCardOrderPayload(
            appearanceMode: .system,
            dashboardCardOrder: [
                DashboardCardID.weather.rawValue,
                "unknown-card",
                DashboardCardID.weather.rawValue,
                DashboardCardID.power.rawValue
            ],
            refreshIntervalSeconds: 5,
            slowRefreshIntervalSeconds: 120,
            historyRetentionHours: 36,
            publicIPGeolocationEnabled: false,
            automaticUpdateChecksEnabled: false,
            launchAtLoginEnabled: true,
            useCurrentLocationForWeather: false,
            latencyHosts: ["example.com:443"]
        )
        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: "NomadDashboard.AppSettings")

        let store = AppSettingsStore(defaults: defaults)
        #expect(store.settings.dashboardCardOrder == [
            .weather,
            .power,
            .connectivity,
            .timeTracking,
            .travelContext,
            .localPriceLevel,
            .fuelPrices,
            .emergencyCare,
            .travelAlerts
        ])
    }

    @Test
    func activeTimeTrackingProjectsExcludeArchivedAndBlankNames() {
        let settings = AppSettings(
            projectTimeTrackingEnabled: true,
            timeTrackingProjects: [
                TimeTrackingProject(name: "Client A"),
                TimeTrackingProject(name: "   "),
                TimeTrackingProject(name: "Archived", isArchived: true)
            ]
        )

        #expect(settings.activeTimeTrackingProjects.map(\.trimmedName) == ["Client A"])
    }

    @Test
    func sanitizesInvalidPersistedDashboardCardWidthModes() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let payload = InvalidDashboardCardWidthModesPayload(
            appearanceMode: .system,
            dashboardCardOrder: DashboardCardID.defaultOrder.map(\.rawValue),
            dashboardCardWidthModes: [
                DashboardCardID.connectivity.rawValue: DashboardCardWidthMode.narrow.rawValue,
                "invalid-card": DashboardCardWidthMode.narrow.rawValue,
                DashboardCardID.travelAlerts.rawValue: "invalid-width"
            ],
            refreshIntervalSeconds: 5,
            slowRefreshIntervalSeconds: 120,
            historyRetentionHours: 36,
            publicIPGeolocationEnabled: false,
            automaticUpdateChecksEnabled: false,
            launchAtLoginEnabled: true,
            useCurrentLocationForWeather: false,
            latencyHosts: ["example.com:443"]
        )
        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: "NomadDashboard.AppSettings")

        let store = AppSettingsStore(defaults: defaults)
        #expect(store.settings.dashboardCardWidthModes[.connectivity] == .narrow)
        #expect(store.settings.dashboardCardWidthModes[.travelAlerts] == .wide)
        #expect(store.settings.dashboardCardWidthModes[.fuelPrices] == .wide)
    }
}

private struct LegacyAppSettingsPayload: Codable {
    let refreshIntervalSeconds: TimeInterval
    let slowRefreshIntervalSeconds: TimeInterval
    let historyRetentionHours: Int
    let publicIPGeolocationEnabled: Bool
    let automaticUpdateChecksEnabled: Bool
    let launchAtLoginEnabled: Bool
    let useCurrentLocationForWeather: Bool
    let latencyHosts: [String]
}

private struct InvalidDashboardCardOrderPayload: Codable {
    let appearanceMode: AppAppearanceMode
    let dashboardCardOrder: [String]
    let refreshIntervalSeconds: TimeInterval
    let slowRefreshIntervalSeconds: TimeInterval
    let historyRetentionHours: Int
    let publicIPGeolocationEnabled: Bool
    let automaticUpdateChecksEnabled: Bool
    let launchAtLoginEnabled: Bool
    let useCurrentLocationForWeather: Bool
    let latencyHosts: [String]
}

private struct InvalidDashboardCardWidthModesPayload: Codable {
    let appearanceMode: AppAppearanceMode
    let dashboardCardOrder: [String]
    let dashboardCardWidthModes: [String: String]
    let refreshIntervalSeconds: TimeInterval
    let slowRefreshIntervalSeconds: TimeInterval
    let historyRetentionHours: Int
    let publicIPGeolocationEnabled: Bool
    let automaticUpdateChecksEnabled: Bool
    let launchAtLoginEnabled: Bool
    let useCurrentLocationForWeather: Bool
    let latencyHosts: [String]
}
