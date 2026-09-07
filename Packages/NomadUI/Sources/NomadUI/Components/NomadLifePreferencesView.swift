import NomadCore
import SwiftUI

public struct NomadLifePreferencesView: View {
    @ObservedObject private var controller: NomadLifeController
    @State private var showingTimeZonePicker = false
    public init(controller: NomadLifeController) {
        self.controller = controller
    }

    public var body: some View {
        Form {
            Section("Workplace connection diary") {
                Toggle("Automatically collect stationary workplace visits", isOn: $controller.preferences.isAutomaticCollectionEnabled)
                Text("Uses authorized device location only. Nomad groups stationary samples locally and suggests “Near X” until you confirm a venue. It does not use IP address or VPN state to identify places.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Time zones") {
                Button(controller.preferences.homeTimeZoneIdentifier.replacingOccurrences(of: "_", with: " ")) { showingTimeZonePicker = true }
                LabeledContent("Home", value: controller.timeZones.homeLabel)
                LabeledContent("Current", value: controller.timeZones.currentLabel)
                Text(controller.timeZones.relativeDayDescription).font(.caption).foregroundStyle(.secondary)
            }
            Section("Quiet contextual alerts") {
                Toggle("Allow quiet connection alerts", isOn: $controller.preferences.areQuietAlertsEnabled)
                Text("Alerts use sustained state changes, cooldowns, and quiet hours. They never include a location or IP address.").font(.caption).foregroundStyle(.secondary)
                Stepper("Quiet hours start: \(controller.preferences.quietHoursStart):00", value: $controller.preferences.quietHoursStart, in: 0...23)
                Stepper("Quiet hours end: \(controller.preferences.quietHoursEnd):00", value: $controller.preferences.quietHoursEnd, in: 0...23)
            }
        }.formStyle(.grouped).padding().frame(minWidth: 520, minHeight: 420)
            .sheet(isPresented: $showingTimeZonePicker) { HomeTimeZonePicker(selection: $controller.preferences.homeTimeZoneIdentifier) }
    }
}

private struct HomeTimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var zones: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose home time zone").font(.headline).padding()
            TextField("Search region or city", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
            List(zones, id: \.self) { id in
                Button { selection = id
                    dismiss()
                } label: { HStack { Text(id.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    Text(time(in: id)).foregroundStyle(.secondary)
                    if id == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }.contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            HStack { Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
        }.frame(width: 460, height: 520)
    }

    private func time(in id: String) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: id)
        return formatter.string(from: .now)
    }
}
