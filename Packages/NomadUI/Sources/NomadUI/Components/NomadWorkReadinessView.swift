import NomadCore
import SwiftUI

/// The first glance stays small: a decision, essential local signals, and two useful clocks.
public struct NomadWorkReadinessView: View {
    let snapshot: DashboardSnapshot
    let policy: DashboardResourcePolicy
    let homeTimeZoneIdentifier: String
    let dataUsageMode: DataUsageMode
    let changeDataUsage: (DataUsageMode) -> Void
    let openDiary: () -> Void
    let openPreferences: () -> Void
    let openOfflineEssentials: () -> Void

    public init(
        snapshot: DashboardSnapshot,
        policy: DashboardResourcePolicy,
        homeTimeZoneIdentifier: String,
        dataUsageMode: DataUsageMode,
        changeDataUsage: @escaping (DataUsageMode) -> Void,
        openDiary: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        openOfflineEssentials: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.policy = policy
        self.homeTimeZoneIdentifier = homeTimeZoneIdentifier
        self.dataUsageMode = dataUsageMode
        self.changeDataUsage = changeDataUsage
        self.openDiary = openDiary
        self.openPreferences = openPreferences
        self.openOfflineEssentials = openOfflineEssentials
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusSymbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(isOffline ? NomadTheme.sand : NomadTheme.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.headline)
                    Text(statusDetail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu {
                    Picker("Data usage", selection: Binding(get: { dataUsageMode }, set: changeDataUsage)) {
                        ForEach(DataUsageMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(policy.isLowData ? "Low Data" : dataUsageMode == .standard ? "Normal" : "Auto", systemImage: policy.isLowData ? "leaf" : "network")
                        .font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(policy.reason ?? "Choose how Nomad uses your connection")
                .accessibilityLabel("Data usage: \(dataUsageMode.title)")
            }

            HStack(spacing: 14) {
                Label(latencyText, systemImage: "waveform.path.ecg")
                Label(vpnText, systemImage: snapshot.travelContext.vpn?.isActive == true ? "lock.shield" : "shield")
                if let charge = snapshot.power.snapshot?.chargePercent {
                    Label("\(Int((charge * 100).rounded()))%", systemImage: snapshot.power.snapshot?.state == .charging ? "battery.100percent.bolt" : "battery.75percent")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            Divider()
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let zones = NomadLifeTimeZonePresentation(
                    homeTimeZoneIdentifier: homeTimeZoneIdentifier,
                    currentTimeZoneIdentifier: snapshot.travelContext.timeZoneIdentifier,
                    date: timeline.date
                )
                HStack(alignment: .top) {
                    clock(title: "Here", identifier: snapshot.travelContext.timeZoneIdentifier, date: timeline.date)
                    Spacer()
                    clock(title: "Home", identifier: homeTimeZoneIdentifier, date: timeline.date)
                    Button(action: openPreferences) { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Set your home time zone").accessibilityLabel("Set home time zone")
                }
                if !zones.relativeDayDescription.isEmpty {
                    Text(zones.relativeDayDescription).font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                Button(action: openDiary) { Label("Workplaces", systemImage: "mappin.and.ellipse") }
                Button(action: openOfflineEssentials) { Label(isOffline ? "Offline essentials" : "Saved essentials", systemImage: "tray.and.arrow.down") }
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(NomadTheme.teal)
        }
        .padding(14)
        .background(NomadTheme.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NomadTheme.teal.opacity(0.16)))
    }

    private var isOffline: Bool {
        policy.isOffline || snapshot.network.connectivity.internetState == .offline
    }

    private var statusTitle: String {
        if isOffline {
            return "You're offline"
        }
        if snapshot.network.connectivity.internetState == .checking {
            return "Checking your connection"
        }
        if let latency = snapshot.network.latency,
           Date().timeIntervalSince(latency.collectedAt) < 180,
           latency.milliseconds > 250
        {
            return "Connected, with some delay"
        }
        if let battery = snapshot.power.snapshot, battery.state == .battery, (battery.chargePercent ?? 1) < 0.15 {
            return "Connected — battery is low"
        }
        return "Connected and ready"
    }

    private var statusSymbol: String {
        if isOffline {
            return "wifi.slash"
        }
        return snapshot.network.connectivity.internetState == .checking ? "network" : "checkmark.circle"
    }

    private var statusDetail: String {
        if isOffline {
            return "Your saved travel information and local tools are still available."
        }
        if let reason = policy.reason {
            return reason
        }
        return "Your connection is responding. Check latency and power before settling in."
    }

    private var latencyText: String {
        guard !isOffline, let latency = snapshot.network.latency,
              Date().timeIntervalSince(latency.collectedAt) < 180 else { return "Latency pending" }
        return "\(Int(latency.milliseconds.rounded())) ms latency"
    }

    private var vpnText: String {
        guard let vpn = snapshot.travelContext.vpn else { return "VPN checking" }
        return vpn.isActive ? "VPN on" : "VPN off"
    }

    private func clock(title: String, identifier: String, date: Date) -> some View {
        let zone = TimeZone(identifier: identifier) ?? .current
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(title).font(.caption.weight(.medium))
                Text(identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? identifier)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
        }
    }
}

public struct DashboardCardRefreshFooter: View {
    let section: DashboardDataSection
    let state: DashboardSectionActivity
    let isOffline: Bool
    let retry: () -> Void
    public init(section: DashboardDataSection, state: DashboardSectionActivity, isOffline: Bool, retry: @escaping () -> Void) {
        self.section = section
        self.state = state
        self.isOffline = isOffline
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(label, systemImage: isOffline || state.isSaved ? "clock.arrow.circlepath" : state.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark")
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(state.message == nil ? "Refresh" : "Retry", action: retry)
                .buttonStyle(.plain).foregroundStyle(NomadTheme.teal)
                .disabled(isOffline || state.isRefreshing)
                .help("Refresh only \(section.title.lowercased())")
        }
        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 3)
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        if state.isRefreshing {
            return state.lastSuccessAt == nil ? "Updating…" : "Updating · saved information stays available"
        }
        if let date = state.lastSuccessAt {
            let prefix = isOffline ? "Offline · saved" : state.message != nil || state.isSaved ? "Saved" : "Updated"
            return "\(prefix) \(date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened))"
        }
        if isOffline {
            return "Available when you're online"
        }
        return state.message ?? "Waiting for first update"
    }
}
