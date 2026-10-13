import Foundation
import NomadCore

/// The map of a trip: the destination country framed from its bundled bounds, with the traveller's embassy
/// or consulate locations on it. Everything is decided from bundled data on this Mac; only the map tiles for
/// the framed area are loaded by Apple Maps when the view is shown.
struct TripMapPresentation: Equatable {
    /// Where the camera looks, in degrees.
    struct Camera: Equatable {
        let centerLatitude: Double
        /// -180...180.
        let centerLongitude: Double
        let latitudeSpan: Double
        let longitudeSpan: Double
    }

    struct Pin: Identifiable, Equatable {
        /// The Wikidata id of the mission.
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        /// True when the coordinate is the city centre rather than the building: the map draws an area and
        /// a label instead of a precise pin.
        let isApproximate: Bool
        /// Apple Maps, searching for the mission (the link of the Your Embassy card).
        let mapsURL: URL?
    }

    static let title = "Map"
    static let openInMapsTitle = "Open in Maps"
    static let offlineNote = "Map needs a connection"
    static let captionWithMissions = "Map © Apple · embassy locations from Wikidata, approximate where marked"
    static let captionWithoutMissions = "Map © Apple"
    /// Radius of the area drawn around an approximate location, about a city centre.
    static let approximateRadiusMeters = 3_000.0

    /// The country (or the missions, when its bounds are unknown) plus a little room around.
    static let regionPadding = 1.15
    /// Room around missions that are framed on their own: they are points, so the margin is wider.
    static let missionPadding = 1.6
    /// Neither span goes below this many degrees (about 11 km of latitude), so a single mission or a tiny
    /// country still shows its surroundings.
    static let minimumSpan = 0.1
    static let maximumLatitudeSpan = 170.0
    static let maximumLongitudeSpan = 359.0

    let camera: Camera
    let pins: [Pin]
    let caption: String
    /// Apple Maps, searching for the destination country; the map itself does not pan or zoom inside the
    /// scrolling preview, so this is how to look around.
    let openInMapsURL: URL?
    /// Set when the Mac is offline and the tiles cannot load.
    let offlineNote: String?
    /// For VoiceOver: "Map of Morocco with 2 embassy locations".
    let accessibilityLabel: String

    /// Changes with what the map shows, so the view starts over when a trip moves to another country.
    var identity: String {
        "\(camera.centerLatitude),\(camera.centerLongitude),\(camera.latitudeSpan),\(camera.longitudeSpan)|\(pins.map(\.id).joined(separator: ","))"
    }

    /// Nil when there is nothing to frame: the country has no bounds and no mission is known.
    init?(preview: TripPreview, policy: DashboardResourcePolicy) {
        let embassy = preview.embassy
        let matches = embassy.map { $0.ownMissions.isEmpty ? $0.fallbackMissions : $0.ownMissions } ?? []
        var seen = Set<String>()
        let pins = matches.map(\.mission).filter { seen.insert($0.id).inserted }.map {
            Pin(
                id: $0.id,
                name: $0.name,
                latitude: $0.latitude,
                longitude: $0.longitude,
                isApproximate: $0.isApproximateLocation,
                mapsURL: EmbassyMapsLink.url(for: $0)
            )
        }

        if let region = CountryGeometry.boundingRegion(forCountryCode: preview.countryCode) {
            camera = Self.camera(for: region)
        } else if pins.isEmpty == false {
            camera = Self.camera(framing: pins.map { (latitude: $0.latitude, longitude: $0.longitude) })
        } else {
            return nil
        }

        self.pins = pins
        openInMapsURL = EmbassyMapsLink.url(forPlaceNamed: preview.countryName)
        caption = pins.isEmpty ? Self.captionWithoutMissions : Self.captionWithMissions
        offlineNote = policy.isOffline ? Self.offlineNote : nil
        accessibilityLabel = pins.isEmpty
            ? "Map of \(preview.countryName)"
            : "Map of \(preview.countryName) with \(pins.count) embassy \(pins.count == 1 ? "location" : "locations")"
    }

    // MARK: Framing

    /// The centre and span of the bounds with a little padding. A box across the antimeridian already
    /// reports its centre within -180...180 and its span as the real distance, so Fiji and Russia are
    /// framed on the right side of the world.
    static func camera(for region: CountryBoundingRegion) -> Camera {
        Camera(
            centerLatitude: region.centerLatitude,
            centerLongitude: region.centerLongitude,
            latitudeSpan: clamped(region.latitudeSpan * regionPadding, maximum: maximumLatitudeSpan),
            longitudeSpan: clamped(region.longitudeSpan * regionPadding, maximum: maximumLongitudeSpan)
        )
    }

    /// A box around the points, across the antimeridian when they lie on both sides of it.
    static func camera(framing coordinates: [(latitude: Double, longitude: Double)]) -> Camera {
        let latitudes = coordinates.map(\.latitude)
        var longitudes = coordinates.map(\.longitude)
        if let first = longitudes.min(), let last = longitudes.max(), last - first > 180 {
            longitudes = longitudes.map { $0 < 0 ? $0 + 360 : $0 }
        }

        let latitudeRange = (latitudes.min() ?? 0, latitudes.max() ?? 0)
        let longitudeRange = (longitudes.min() ?? 0, longitudes.max() ?? 0)
        let centerLongitude = (longitudeRange.0 + longitudeRange.1) / 2
        return Camera(
            centerLatitude: (latitudeRange.0 + latitudeRange.1) / 2,
            centerLongitude: centerLongitude > 180 ? centerLongitude - 360 : centerLongitude,
            latitudeSpan: clamped((latitudeRange.1 - latitudeRange.0) * missionPadding, maximum: maximumLatitudeSpan),
            longitudeSpan: clamped((longitudeRange.1 - longitudeRange.0) * missionPadding, maximum: maximumLongitudeSpan)
        )
    }

    private static func clamped(_ span: Double, maximum: Double) -> Double {
        min(max(span, minimumSpan), maximum)
    }
}
