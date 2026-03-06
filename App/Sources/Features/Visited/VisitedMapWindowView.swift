import NomadCore
import NomadUI
import SwiftUI

struct VisitedMapWindowView: View {
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var settingsStore: AppSettingsStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            NomadTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if settingsStore.settings.visitedPlacesEnabled == false {
                        disabledState
                    } else if places.isEmpty {
                        emptyState
                    } else {
                        metrics
                        mapCard
                        guidanceCard
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 940, minHeight: 720)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Visited Map")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                actionButton(
                    title: "Settings",
                    systemImage: "slider.horizontal.3",
                    action: { openAndActivateWindow(.settings, with: openWindow) }
                )

                actionButton(
                    title: "Clear History",
                    systemImage: "trash",
                    role: .destructive,
                    isEnabled: places.isEmpty == false
                ) {
                    snapshotStore.clearVisitedPlaces()
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metricCard(title: "Cities", value: "\(snapshotStore.visitedPlaceSummary.citiesVisited)", tint: NomadTheme.teal)
            metricCard(title: "Countries", value: "\(snapshotStore.visitedPlaceSummary.countriesVisited)", tint: NomadTheme.sand)
            metricCard(title: "Sources", value: trackingModeLabel, tint: NomadTheme.coral)
        }
    }

    private var mapCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("World Footprint")
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText)

                        Text("Drag, zoom, and inspect the saved cities. Countries with at least one saved place are tinted.")
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                    Spacer()

                    legend
                }

                VisitedWorldMapView(places: places)
                    .frame(minHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                    )
            }
        }
    }

    private var guidanceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Label("How capture works", systemImage: "location.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Text("Pins appear as locations are saved locally from your enabled location sources. Device-derived places are typically more precise than IP-derived places.")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disabledState: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Visited history is off", systemImage: "globe.badge.chevron.backward")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Text("Turn on local visited-place storage in Settings to start building your travel map on this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                actionButton(
                    title: "Open Settings",
                    systemImage: "slider.horizontal.3",
                    action: { openAndActivateWindow(.settings, with: openWindow) }
                )
            }
        }
    }

    private var emptyState: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Label("No saved places yet", systemImage: "mappin.slash")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Text("Saved cities will appear here after location updates are recorded. Keep external IP location or current location enabled, then refresh once you have a place to save.")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    actionButton(
                        title: "Open Settings",
                        systemImage: "slider.horizontal.3",
                        action: { openAndActivateWindow(.settings, with: openWindow) }
                    )

                    actionButton(
                        title: "Refresh Dashboard",
                        systemImage: "arrow.clockwise",
                        action: {
                            Task {
                                await snapshotStore.refresh(manual: true)
                            }
                        }
                    )
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(title: "Visited Country", tint: NomadTheme.teal)
            legendItem(title: "Saved City", tint: NomadTheme.coral)
        }
    }

    private func legendItem(title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.secondaryText)
        }
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.secondaryText)

                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                Capsule(style: .continuous)
                    .fill(tint.opacity(0.22))
                    .frame(width: 58, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(role == .destructive ? NomadTheme.coral : NomadTheme.teal)
        .disabled(isEnabled == false)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(NomadTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
            )
    }

    private var places: [VisitedPlace] {
        snapshotStore.visitedPlaces
    }

    private var visitedCountryCodes: Set<String> {
        Set(places.compactMap { $0.countryCode?.uppercased() })
    }

    private var headerSubtitle: String {
        if settingsStore.settings.visitedPlacesEnabled == false {
            return "Local place history is currently disabled."
        }

        if places.isEmpty {
            return "Your saved travel footprint will appear here."
        }

        return "\(snapshotStore.visitedPlaceSummary.citiesVisited) saved cities across \(snapshotStore.visitedPlaceSummary.countriesVisited) countries."
    }

    private var trackingModeLabel: String {
        let sources = [
            settingsStore.settings.publicIPGeolocationEnabled ? "IP" : nil,
            settingsStore.settings.usesDeviceLocation ? "Device" : nil
        ].compactMap { $0 }

        if sources.isEmpty {
            return "None"
        }

        return sources.joined(separator: " + ")
    }
}
