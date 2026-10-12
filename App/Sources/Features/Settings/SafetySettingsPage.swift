import NomadCore
import NomadUI
import SwiftUI

struct SafetySettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var locationStore: CurrentLocationStore
    @ObservedObject var navigationController: SettingsNavigationController

    var body: some View {
        SettingsPageForm(page: .safety, navigationController: navigationController) {
            travelAlertsSection
            emergencyCareSection
            embassySection
        }
    }

    /// Travel alert sources. New safety toggles belong in this group or a sibling.
    private var travelAlertsSection: some View {
        Section {
            Toggle("Travel advisory", isOn: settingsStore.binding(\.travelAdvisoryEnabled))
                .id(SettingsFocusTarget.travelAlerts.rawValue)
            Toggle(
                "Weather alerts",
                isOn: settingsStore.locationAwareBinding(\.travelWeatherAlertsEnabled, snapshotStore: snapshotStore, locationStore: locationStore)
            )
            Toggle("Regional security", isOn: settingsStore.binding(\.regionalSecurityEnabled))
        } header: {
            Text("Travel alerts")
        } footer: {
            Text("Travel advisory uses Smartraveller by default and starts enabled. Regional security uses ReliefWeb, and weather alerts use WeatherKit. Advisory and security check your current country plus bordering countries; weather alerts use your current location when available.")
        }
    }

    private var emergencyCareSection: some View {
        Section {
            Toggle(
                "Show nearby emergency hospitals",
                isOn: settingsStore.locationAwareBinding(\.emergencyCareEnabled, snapshotStore: snapshotStore, locationStore: locationStore)
            )
            .id(SettingsFocusTarget.emergencyCare.rawValue)
        } header: {
            Text("Emergency care")
        } footer: {
            Text("Emergency numbers are bundled with the app and shown offline. Nearby hospitals use Apple Maps hospital points of interest and open selected hospitals in maps.")
        }
    }

    /// Where the embassy data comes from. The citizenship itself is chosen under General › Home.
    private var embassySection: some View {
        Section {
            Text(CitizenshipSettingsPresentation.embassyStatus(forCitizenships: settingsStore.settings.citizenshipCountryCodes))

            Button(CitizenshipSettingsPresentation.pickerTitle) {
                navigationController.focus(.citizenship)
            }
        } header: {
            Text("Your embassy")
        } footer: {
            Text(CitizenshipSettingsPresentation.embassySectionFooter)
        }
    }
}
