import MapKit
import NomadCore
import SwiftUI

/// A compact map of the destination with the traveller's embassy locations. A precise location is a marker;
/// an approximate one (a city centre) is an area with a label, since a pin would point at the wrong street.
/// Tapping either opens Apple Maps with the same search as the Your Embassy card. The map does not pan or
/// zoom: it sits in a scrolling preview, where it would trap the scroll, so "Open in Maps" is the way to look around.
struct TripMapView: View {
    let map: TripMapPresentation
    let openURLAction: (URL) -> Void

    @State private var selection: String?

    static let height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Map(initialPosition: .region(region), interactionModes: [], selection: $selection) {
                ForEach(map.pins) { pin in
                    if pin.isApproximate {
                        MapCircle(center: pin.coordinate, radius: TripMapPresentation.approximateRadiusMeters)
                            .foregroundStyle(NomadTheme.teal.opacity(0.2))
                            .stroke(NomadTheme.teal.opacity(0.7), lineWidth: 1)

                        Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                            Button {
                                open(pin)
                            } label: {
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(NomadTheme.teal))
                            }
                            .buttonStyle(.plain)
                            .help("Search for \(pin.name) in Apple Maps")
                        }
                    } else {
                        Marker(pin.name, systemImage: "building.columns.fill", coordinate: pin.coordinate)
                            .tint(NomadTheme.teal)
                            .tag(pin.id)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
            )
            .id(map.identity)
            .accessibilityLabel(map.accessibilityLabel)
            .onChange(of: selection) { _, id in
                guard let id else { return }
                selection = nil
                if let pin = map.pins.first(where: { $0.id == id }) {
                    open(pin)
                }
            }

            if let url = map.openInMapsURL {
                Button(TripMapPresentation.openInMapsTitle) { openURLAction(url) }
                    .buttonStyle(.dashboardInline(isCompact: true))
                    .help("Search for the destination in Apple Maps")
            }

            if let note = map.offlineNote {
                Label(note, systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
            }

            Text(map.caption)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: map.camera.centerLatitude, longitude: map.camera.centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: map.camera.latitudeSpan, longitudeDelta: map.camera.longitudeSpan)
        )
    }

    private func open(_ pin: TripMapPresentation.Pin) {
        if let url = pin.mapsURL {
            openURLAction(url)
        }
    }
}

private extension TripMapPresentation.Pin {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
