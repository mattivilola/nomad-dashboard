import NomadCore
import NomadUI
import SwiftUI

struct OfflineEssentialsView: View {
    @ObservedObject var store: DashboardSnapshotStore
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Offline essentials", systemImage: "tray.and.arrow.down.fill").font(.title2.weight(.semibold))
                    Text("Saved automatically as your enabled cards update. No preparation needed.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let place = store.snapshot.travelContext.deviceLocation ?? store.snapshot.travelContext.location {
                Label([place.city, place.country].compactMap(\.self).joined(separator: ", "), systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.medium))
            }
            if let numbers = OfflineEssentialsPresentation.emergencyNumbers(for: store.snapshot) {
                emergencyNumbersRow(numbers)
            }
            if let embassy = OfflineEssentialsPresentation.embassy(settings: settings, snapshot: store.snapshot) {
                embassyRow(embassy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(DashboardDataSection.allCases.filter { $0 != .publicIP && $0 != .location }) { section in
                        if let state = store.sectionActivity[section] {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label(section.title, systemImage: state.lastSuccessAt == nil ? "clock" : "checkmark.circle")
                                        .font(.headline)
                                    Spacer()
                                    if let date = state.lastSuccessAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text(summary(section)).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if state.lastSuccessAt == nil {
                                    Text("Will save after the first successful update.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            if let error = store.offlineCacheError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Text("Saved information may be out of date. Maps, directions, and source websites need a connection. Work time and your travel diary stay available locally.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 510, height: 570)
    }

    private func emergencyNumbersRow(_ numbers: EmergencyNumbers) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(numbers.headline, systemImage: "phone.arrow.up.right.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            if let others = numbers.othersText {
                Text(others).font(.subheadline).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func embassyRow(_ embassy: EmbassyEssentials) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Your embassy", systemImage: "building.columns")
                .font(.headline)
            if let mission = embassy.nearestMission {
                Text(mission).font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(embassy.hotlines, id: \.phone) { hotline in
                Text("\(hotline.title) · \(hotline.phone)").font(.subheadline).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summary(_ section: DashboardDataSection) -> String {
        let snapshot = store.snapshot
        switch section {
        case .weather:
            guard let weather = snapshot.weather else { return "Current weather and your forecast." }
            return OfflineEssentialsPresentation.weatherSummary(weather)
        case .localInfo:
            return snapshot.localInfo?.detail ?? "Local holidays and useful country context."
        case .fuel:
            let stations = [snapshot.fuelPrices?.diesel, snapshot.fuelPrices?.gasoline].compactMap(\.self)
            return stations.isEmpty ? snapshot.fuelPrices?.detail ?? "Fuel prices have not been saved yet." : stations.map { OfflineEssentialsPresentation.fuelLine($0) }.joined(separator: "\n")
        case .emergencyCare:
            let hospitals = snapshot.emergencyCare?.hospitals ?? []
            return hospitals.isEmpty ? "Nearby hospital references, once this card is enabled and updated." : hospitals.map { [$0.name, $0.address].compactMap(\.self).joined(separator: " — ") }.joined(separator: "\n")
        case .airQuality:
            return snapshot.airQuality.map(OfflineEssentialsPresentation.airQualitySummary) ?? "Air quality for your weather location."
        case .marine: return snapshot.marine.map { "\($0.spotName) · saved surf forecast" } ?? "Forecast for your saved surf spot."
        case .travelAlerts: return snapshot.travelAlerts?.states.compactMap { $0.resolvedSignal?.summary }.joined(separator: "\n") ?? "Source-linked destination advisories."
        default: return ""
        }
    }
}
