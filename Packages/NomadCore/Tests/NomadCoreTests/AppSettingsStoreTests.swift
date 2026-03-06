import Foundation
import NomadCore
import Testing

@MainActor
struct AppSettingsStoreTests {
    @Test
    func freshStoresEnablePublicIPLocationByDefault() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)

        #expect(store.settings.publicIPGeolocationEnabled == true)
    }

    @Test
    func persistsChangesToUserDefaults() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.settings.publicIPGeolocationEnabled = true

        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.settings.publicIPGeolocationEnabled == true)
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
}
