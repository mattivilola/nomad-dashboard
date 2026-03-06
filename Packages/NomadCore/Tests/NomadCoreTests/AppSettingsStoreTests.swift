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
        #expect(store.settings.publicIPGeolocationEnabled == true)
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
        #expect(store.settings.refreshIntervalSeconds == 5)
        #expect(store.settings.slowRefreshIntervalSeconds == 120)
        #expect(store.settings.historyRetentionHours == 36)
        #expect(store.settings.publicIPGeolocationEnabled == false)
        #expect(store.settings.automaticUpdateChecksEnabled == false)
        #expect(store.settings.launchAtLoginEnabled == true)
        #expect(store.settings.useCurrentLocationForWeather == false)
        #expect(store.settings.latencyHosts == ["example.com:443"])
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
