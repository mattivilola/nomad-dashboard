import AppKit
import NomadCore
import NomadUI
import SwiftUI

struct AdvancedSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var navigationController: SettingsNavigationController
    let updatesEnabled: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsPageForm(page: .advanced, navigationController: navigationController) {
            refreshAndHistorySection
            fuelDiagnosticsSection
            aboutSection
        }
    }

    private var refreshAndHistorySection: some View {
        Section {
            Stepper(value: fastRefreshBinding, in: Int(AppSettings.minimumRefreshIntervalSeconds)...Int(AppSettings.maximumRefreshIntervalSeconds), step: 5) {
                LabeledContent("Fast refresh") {
                    Text(refreshDurationText(fastRefreshValue))
                        .monospacedDigit()
                }
            }

            Stepper(value: slowRefreshBinding, in: Int(AppSettings.minimumSlowRefreshIntervalSeconds)...Int(AppSettings.maximumSlowRefreshIntervalSeconds), step: 60) {
                LabeledContent("Slow refresh") {
                    Text(refreshDurationText(slowRefreshValue))
                        .monospacedDigit()
                }
            }

            Stepper(value: settingsStore.binding(\.historyRetentionHours), in: 6...72) {
                LabeledContent("Metric retention") {
                    Text("\(settingsStore.settings.historyRetentionHours) hours")
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Refresh & history")
        } footer: {
            Text("Fast refresh controls lightweight polling while the dashboard is open. Hidden background refreshes are automatically slowed to reduce battery use. Slow refresh covers heavier network, power, location, and weather lookups.")
        }
    }

    private var fuelDiagnosticsSection: some View {
        Section {
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
        }
    }

    private var aboutSection: some View {
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
        } header: {
            Text("About")
        }
    }

    private var fastRefreshBinding: Binding<Int> {
        Binding(
            get: { fastRefreshValue },
            set: { settingsStore.settings.refreshIntervalSeconds = AppSettings.sanitizedRefreshInterval(Double($0)) }
        )
    }

    private var slowRefreshBinding: Binding<Int> {
        Binding(
            get: { slowRefreshValue },
            set: { settingsStore.settings.slowRefreshIntervalSeconds = AppSettings.sanitizedSlowRefreshInterval(Double($0)) }
        )
    }

    private var fastRefreshValue: Int {
        Int(settingsStore.settings.refreshIntervalSeconds)
    }

    private var slowRefreshValue: Int {
        Int(settingsStore.settings.slowRefreshIntervalSeconds)
    }

    private func refreshDurationText(_ seconds: Int) -> String {
        if seconds >= 60, seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }

        return seconds == 1 ? "1 second" : "\(seconds) seconds"
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
