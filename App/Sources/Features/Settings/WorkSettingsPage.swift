import NomadCore
import NomadUI
import SwiftUI

struct WorkSettingsPage: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var timeTrackingController: ProjectTimeTrackingController
    @ObservedObject var lifeController: NomadLifeController
    @ObservedObject var navigationController: SettingsNavigationController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsPageForm(page: .work, navigationController: navigationController) {
            projectTimeTrackingSection
            workplaceDiarySection
        }
    }

    private var projectTimeTrackingSection: some View {
        Section {
            Toggle("Enable project time tracking", isOn: settingsStore.binding(\.projectTimeTrackingEnabled))
                .id(SettingsFocusTarget.timeTracking.rawValue)

            if settingsStore.settings.projectTimeTrackingEnabled {
                LabeledContent("Status") {
                    Text(timeTrackingStatusLabel)
                        .foregroundStyle(.secondary)
                }
            }

            if activeTimeTrackingProjectIndices.isEmpty {
                Text("No active projects yet. Add projects here, then allocate today’s pending time from the dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeTimeTrackingProjectIndices, id: \.self) { index in
                    HStack(spacing: 10) {
                        TextField("Project name", text: timeTrackingProjectNameBinding(for: index))
                            .textFieldStyle(.roundedBorder)

                        Button("Archive") {
                            settingsStore.settings.timeTrackingProjects[index].isArchived = true
                        }
                    }
                }
            }

            Button("Add Project") {
                settingsStore.settings.timeTrackingProjects.append(
                    TimeTrackingProject(name: nextProjectName)
                )
            }

            if archivedTimeTrackingProjectIndices.isEmpty == false {
                DisclosureGroup("Archived Projects") {
                    ForEach(archivedTimeTrackingProjectIndices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text(settingsStore.settings.timeTrackingProjects[index].trimmedName.nilIfEmpty ?? "Untitled Project")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Restore") {
                                settingsStore.settings.timeTrackingProjects[index].isArchived = false
                            }
                        }
                    }
                }
            }

            if settingsStore.settings.projectTimeTrackingEnabled {
                Button("Open Time Tracking") {
                    openAndActivateWindow(.timeTracking, with: openWindow)
                }
            }
        } header: {
            Text("Project time tracking")
        } footer: {
            SettingsFooter("Project time tracking stays local to this Mac. The app tracks awake time only while Nomad Dashboard is running, keeps exact timings, and lets you assign today’s pending time into projects or Other from the dashboard.")
        }
    }

    private var workplaceDiarySection: some View {
        Section {
            Toggle("Automatically collect stationary workplace visits", isOn: $lifeController.preferences.isAutomaticCollectionEnabled)
                .id(SettingsFocusTarget.workplaceDiary.rawValue)

            Button("Open Workplace Diary") {
                openAndActivateWindow(.workplaceDiary, with: openWindow)
            }
        } header: {
            Text("Workplace diary")
        } footer: {
            SettingsFooter("Uses authorized device location only. Nomad groups stationary samples locally and suggests “Near X” until you confirm a venue. It does not use IP address or VPN state to identify places.")
        }
    }

    private var activeTimeTrackingProjectIndices: [Int] {
        settingsStore.settings.timeTrackingProjects.indices.filter { settingsStore.settings.timeTrackingProjects[$0].isArchived == false }
    }

    private var archivedTimeTrackingProjectIndices: [Int] {
        settingsStore.settings.timeTrackingProjects.indices.filter { settingsStore.settings.timeTrackingProjects[$0].isArchived }
    }

    private var timeTrackingStatusLabel: String {
        switch timeTrackingController.runtimeState.activityState {
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .stopped:
            "Stopped"
        }
    }

    private var nextProjectName: String {
        "Project \(settingsStore.settings.timeTrackingProjects.count + 1)"
    }

    private func timeTrackingProjectNameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { settingsStore.settings.timeTrackingProjects[index].name },
            set: { settingsStore.settings.timeTrackingProjects[index].name = $0 }
        )
    }
}
