import NomadCore
import NomadUI
import SwiftUI

struct GeneralSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    @ObservedObject var lifeController: NomadLifeController
    @ObservedObject var navigationController: SettingsNavigationController
    let updatesEnabled: Bool

    @State private var showingTimeZonePicker = false
    @State private var showingCitizenshipPicker = false

    var body: some View {
        SettingsPageForm(page: .general, navigationController: navigationController) {
            introSection
            travelProfileSection
            homeSection
            citizenshipSection
            appearanceAndStartupSection
            menuBarSection
            dashboardLayoutSection
        }
        .sheet(isPresented: $showingTimeZonePicker) {
            HomeTimeZonePicker(selection: $lifeController.preferences.homeTimeZoneIdentifier)
        }
        .sheet(isPresented: $showingCitizenshipPicker) {
            CitizenshipCountryPicker(chosen: citizenshipCodes, onSelect: addCitizenship)
        }
    }

    private var introSection: some View {
        Section {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppRuntimeInfo.appName)
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
        }
    }

    private var travelProfileSection: some View {
        Section {
            Picker("Travel profile", selection: travelProfileBinding) {
                ForEach(TravelProfile.allCases, id: \.self) { profile in
                    Text(profile.title)
                        .tag(profile)
                }
            }
            .pickerStyle(.segmented)

            if travelProfilePresentation.offersRecommendedOrder {
                Button(TravelProfileSettingsPresentation.useRecommendedOrderTitle) {
                    settingsStore.settings.dashboardCardOrder = travelProfilePresentation.recommendedOrder
                }
            }
        } header: {
            Text("Travel profile")
        } footer: {
            Text(travelProfilePresentation.footer)
        }
    }

    /// Where the traveler's home is. Home-related settings (such as citizenship) belong in this group.
    private var homeSection: some View {
        Section {
            LabeledContent("Home time zone") {
                Button(homeTimeZoneName) { showingTimeZonePicker = true }
            }
            .id(SettingsFocusTarget.homeTimeZone.rawValue)

            LabeledContent("Home", value: lifeController.timeZones.homeLabel)
            LabeledContent("Current", value: lifeController.timeZones.currentLabel)

            Text(lifeController.timeZones.relativeDayDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Home")
        }
    }

    /// Citizenship belongs to the traveler's home. It drives the Your Embassy card and stays on this Mac.
    private var citizenshipSection: some View {
        Section {
            if citizenshipCodes.isEmpty {
                Text("No citizenship chosen")
                    .foregroundStyle(.secondary)
                    .id(SettingsFocusTarget.citizenship.rawValue)
            } else {
                ForEach(Array(citizenshipCodes.enumerated()), id: \.element) { offset, code in
                    LabeledContent(CitizenshipSettingsPresentation.countryName(for: code)) {
                        Button {
                            removeCitizenship(code)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(CitizenshipSettingsPresentation.countryName(for: code))")
                        .accessibilityLabel("Remove \(CitizenshipSettingsPresentation.countryName(for: code))")
                    }
                    .id(offset == 0 ? SettingsFocusTarget.citizenship.rawValue : code)
                }
            }

            Button(CitizenshipSettingsPresentation.addCountryTitle) {
                showingCitizenshipPicker = true
            }
            .disabled(CitizenshipSettingsPresentation.canAddCountry(to: citizenshipCodes) == false)

            if CitizenshipSettingsPresentation.canAddCountry(to: citizenshipCodes) == false {
                Text(CitizenshipSettingsPresentation.limitText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Citizenship")
        } footer: {
            Text(CitizenshipSettingsPresentation.sectionFooter)
        }
    }

    private var citizenshipCodes: [String] {
        settingsStore.settings.citizenshipCountryCodes
    }

    private func addCitizenship(_ code: String) {
        settingsStore.settings.citizenshipCountryCodes = AppSettings.sanitizedCitizenshipCodes(citizenshipCodes + [code])
    }

    private func removeCitizenship(_ code: String) {
        settingsStore.settings.citizenshipCountryCodes = citizenshipCodes.filter { $0 != code }
    }

    private var appearanceAndStartupSection: some View {
        Section {
            Picker("Appearance", selection: settingsStore.binding(\.appearanceMode)) {
                ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Launch at login", isOn: launchAtLoginBinding)

            if updatesEnabled {
                Toggle("Check for updates automatically", isOn: settingsStore.binding(\.automaticUpdateChecksEnabled))
            } else {
                LabeledContent("Updates") {
                    Text("Paused")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Appearance & startup")
        } footer: {
            Text(updatesEnabled ? "System follows your macOS appearance. The dashboard header menu flips quickly between dark and light, and all preferences stay across relaunches." : "System follows your macOS appearance. The dashboard header menu flips quickly between dark and light, and all preferences stay across relaunches. In-app update checks only become available in signed release builds that include Sparkle metadata.")
        }
    }

    private var menuBarSection: some View {
        Section {
            Toggle(TravelProfileSettingsPresentation.menuBarHeadsUpTitle, isOn: settingsStore.binding(\.menuBarShowsHeadsUp))
            Text(TravelProfileSettingsPresentation.menuBarHeadsUpFooter)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Show usage in menu bar when monitoring", isOn: settingsStore.binding(\.showMeteredUsageInMenuBar))
        } header: {
            Text("Menu bar")
        } footer: {
            Text("Usage appears in the menu bar while Data Guard is monitoring the connection.")
        }
    }

    private var dashboardLayoutSection: some View {
        Section {
            Button("Reset Dashboard Layout") {
                settingsStore.settings.dashboardCardOrder = DashboardCardID.defaultOrder(for: settingsStore.settings.travelProfile)
                settingsStore.settings.dashboardCardWidthModes = DashboardCardID.defaultWidthModes
                settingsStore.settings.dashboardCollapsedCards = []
            }
        } header: {
            Text("Dashboard layout")
        }
    }

    private var homeTimeZoneName: String {
        lifeController.preferences.homeTimeZoneIdentifier.replacingOccurrences(of: "_", with: " ")
    }

    private var travelProfileBinding: Binding<TravelProfile> {
        Binding(
            get: { settingsStore.settings.travelProfile },
            set: { settingsStore.settings.applyTravelProfile($0) }
        )
    }

    private var travelProfilePresentation: TravelProfileSettingsPresentation {
        TravelProfileSettingsPresentation(
            profile: settingsStore.settings.travelProfile,
            isUsingRecommendedOrder: settingsStore.settings.isUsingRecommendedOrder
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
}
