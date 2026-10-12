import NomadCore
import NomadUI
import SwiftUI

/// Stays & Visas: the Schengen counter, per-country stay allowances and the tax residence day count.
/// All of it is computed locally from the days recorded on this Mac.
struct StaysSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var navigationController: SettingsNavigationController

    @Environment(\.openWindow) private var openWindow
    @State private var showingAllowancePicker = false

    var body: some View {
        SettingsPageForm(page: .stays, navigationController: navigationController) {
            schengenSection
            allowancesSection
            taxResidenceSection
            dataSection
        }
        .sheet(isPresented: $showingAllowancePicker) {
            CitizenshipCountryPicker(
                title: StaySettingsPresentation.allowancePickerTitle,
                chosen: Array(settingsStore.settings.stayAllowances.keys),
                onSelect: addAllowance
            )
        }
    }

    private var schengenSection: some View {
        Section {
            Toggle(StaySettingsPresentation.schengenToggleTitle, isOn: settingsStore.binding(\.schengenCounterEnabled))
                .id(SettingsFocusTarget.stays.rawValue)
        } header: {
            Text("Schengen counter")
        } footer: {
            SettingsFooter(StaySettingsPresentation.schengenFooter)
        }
    }

    private var allowancesSection: some View {
        Section {
            let rows = StaySettingsPresentation.allowanceRows(settingsStore.settings.stayAllowances)
            if rows.isEmpty {
                Text("No allowances set")
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                LabeledContent(row.countryName) {
                    HStack(spacing: 10) {
                        Stepper(
                            StaySettingsPresentation.daysText(row.days),
                            value: allowanceBinding(for: row.countryCode),
                            in: 1...AppSettings.maximumStayAllowanceDays
                        )

                        Button {
                            removeAllowance(row.countryCode)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(row.countryName)")
                        .accessibilityLabel("Remove \(row.countryName) allowance")
                    }
                }
            }

            Button(StaySettingsPresentation.addAllowanceTitle) {
                showingAllowancePicker = true
            }
        } header: {
            Text(StaySettingsPresentation.allowancesTitle)
        } footer: {
            SettingsFooter(StaySettingsPresentation.allowancesFooter)
        }
    }

    private var taxResidenceSection: some View {
        Section {
            Toggle(StaySettingsPresentation.taxToggleTitle, isOn: settingsStore.binding(\.taxResidenceDaysEnabled))

            Stepper(
                value: settingsStore.binding(\.taxResidenceThresholdDays),
                in: AppSettings.minimumTaxResidenceThresholdDays...AppSettings.maximumTaxResidenceThresholdDays
            ) {
                LabeledContent(
                    StaySettingsPresentation.taxThresholdTitle,
                    value: StaySettingsPresentation.daysText(settingsStore.settings.taxResidenceThresholdDays)
                )
            }
            .disabled(settingsStore.settings.taxResidenceDaysEnabled == false)
        } header: {
            Text("Tax residence days")
        } footer: {
            SettingsFooter(StaySettingsPresentation.taxFooter)
        }
    }

    private var dataSection: some View {
        Section {
            if settingsStore.settings.visitedPlacesEnabled == false {
                Label(StaySettingsPresentation.visitedPlacesOffNotice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(StaySettingsPresentation.openVisitedMapTitle) {
                openAndActivateWindow(.visitedMap, with: openWindow)
            }

            Button(StaySettingsPresentation.visitedPlacesPointerTitle) {
                navigationController.focus(.visitedPlaces)
            }
        } header: {
            Text(StaySettingsPresentation.dataTitle)
        } footer: {
            SettingsFooter(StaySettingsPresentation.dataFooter)
        }
    }

    private func allowanceBinding(for countryCode: String) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings.stayAllowances[countryCode] ?? StaySettingsPresentation.defaultAllowanceDays },
            set: { setAllowance($0, for: countryCode) }
        )
    }

    private func addAllowance(_ countryCode: String) {
        setAllowance(StaySettingsPresentation.defaultAllowanceDays, for: countryCode)
    }

    private func setAllowance(_ days: Int, for countryCode: String) {
        settingsStore.settings.stayAllowances = StaySettingsPresentation.settingAllowance(
            days,
            for: countryCode,
            in: settingsStore.settings.stayAllowances
        )
    }

    private func removeAllowance(_ countryCode: String) {
        settingsStore.settings.stayAllowances = StaySettingsPresentation.removingAllowance(
            for: countryCode,
            from: settingsStore.settings.stayAllowances
        )
    }
}
