import AppKit
import CoreLocation
import NomadCore
import NomadUI
import SwiftUI

struct WorkplaceDiaryWindow: View {
    @ObservedObject var controller: NomadLifeController
    @ObservedObject var locationStore: CurrentLocationStore

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            Divider()
            NomadLifeDiaryView(controller: controller)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if controller.preferences.isAutomaticCollectionEnabled == false {
            banner(
                title: "Workplace collection is off",
                detail: "Enable it to save stationary workplace visits locally when location access is available.",
                systemImage: "briefcase",
                actionTitle: "Enable Collection"
            ) {
                controller.preferences.isAutomaticCollectionEnabled = true
            }
        } else if locationStore.diagnostics.isLocationServicesEnabled == false {
            banner(
                title: "Location Services are off",
                detail: "Turn on Location Services in macOS to collect workplace visits.",
                systemImage: "location.slash",
                actionTitle: "Open Location Settings",
                action: openLocationSettings
            )
        } else {
            switch locationStore.authorizationStatus {
            case .notDetermined:
                banner(
                    title: "Location access is needed",
                    detail: "Workplace visits use authorized device location only.",
                    systemImage: "location.circle",
                    actionTitle: "Allow Location"
                ) {
                    locationStore.requestAuthorization()
                }
            case .denied, .restricted:
                banner(
                    title: "Location access is unavailable",
                    detail: "Allow Nomad Dashboard in macOS Location Services to collect workplace visits.",
                    systemImage: "location.slash",
                    actionTitle: "Open Location Settings",
                    action: openLocationSettings
                )
            case .authorizedAlways, .authorizedWhenInUse:
                if locationStore.currentLocation == nil {
                    banner(
                        title: "Waiting for a location fix",
                        detail: locationStore.diagnostics.detailText ?? "Refresh your location to begin collecting workplace visits.",
                        systemImage: "location.magnifyingglass",
                        actionTitle: "Refresh Location"
                    ) {
                        locationStore.refreshLocation()
                    }
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    private func banner(
        title: String,
        detail: String,
        systemImage: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(NomadTheme.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(actionTitle, action: action).buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(NomadTheme.cardBackground)
    }

    private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
