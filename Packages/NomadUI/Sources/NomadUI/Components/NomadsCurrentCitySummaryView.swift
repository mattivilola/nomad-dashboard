import NomadCore
import SwiftUI

/// A small automatic city signal; photos are loaded only in the explorer window.
public struct NomadsCurrentCitySummaryView: View {
    @ObservedObject private var controller: NomadsCurrentCityController
    private let openExplorer: () -> Void

    public init(controller: NomadsCurrentCityController, openExplorer: @escaping () -> Void) {
        self.controller = controller
        self.openExplorer = openExplorer
    }

    public var body: some View {
        if controller.enabled, controller.currentLocationName != nil, controller.state != .waitingForLocation {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: openExplorer) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2).foregroundStyle(NomadTheme.coral)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            if controller.isLoading {
                                Text("Checking your current city…").font(.caption).foregroundStyle(.secondary)
                            } else if let city = controller.matchedCity {
                                Text([NomadsCityFormatting.monthlyUSD(city.costForNomadUSDPerMonth), NomadsCityFormatting.internet(city.internetMbps)].joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(controller.errorMessage == nil ? "No listed destination within 50 km." : "City check unavailable. Open to retry.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(NomadTheme.teal)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                HStack {
                    Link("Nomads.com estimates", destination: URL(string: "https://nomads.com")!)
                    Spacer()
                    if let match = controller.match, match.isNearby, let distance = match.distanceKilometers {
                        Text("\(distance.formatted(.number.precision(.fractionLength(0)))) km nearby")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(NomadTheme.coral.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NomadTheme.coral.opacity(0.14), lineWidth: 1))
        }
    }

    private var title: String {
        if let city = controller.matchedCity, !controller.isLoading {
            return controller.match?.isNearby == true ? "Nearby: \(city.name)" : "Your city: \(city.name)"
        }
        return controller.currentLocationName ?? "Your current city"
    }
}
