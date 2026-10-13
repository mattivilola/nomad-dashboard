import Foundation

// Bundled, offline bounding boxes of countries, so a planned trip can be framed on a map without loading
// the country shapes in the UI first.
//
// Source: the Natural Earth 1:110m admin-0 countries (public domain) that the visited-places map draws, reduced
// to one box per country by `scripts/update-country-bounds.sh` into `Resources/country-bounds.json`; small
// states that the 1:110m data omits (Singapore, Malta, Mauritius, ...) have hand-entered approximate extents.
// Nothing is fetched at runtime.
//
// What a box covers: the main landmass plus every part within 4 degrees of it, so island groups (Indonesia,
// Japan, Fiji) are whole while far-flung territories (French Guiana, Alaska and Hawaii, Greenland, the
// Canary Islands) are left out. The shapes show de facto borders, so Morocco's box includes the Western
// Sahara. A country the data does not cover has no box.

/// The smallest latitude/longitude box around a country (see `CountryGeometry`).
public struct CountryBoundingRegion: Equatable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    /// West edge in degrees, -180...180.
    public let minLongitude: Double
    /// East edge in degrees. Above 180 when the box crosses the antimeridian (Fiji, Russia): subtract 360
    /// for the real longitude. Never below `minLongitude`.
    public let maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    public var crossesAntimeridian: Bool {
        maxLongitude > 180
    }

    public var latitudeSpan: Double {
        maxLatitude - minLatitude
    }

    /// Degrees of longitude from the west to the east edge, across the antimeridian if the box crosses it.
    public var longitudeSpan: Double {
        maxLongitude - minLongitude
    }

    public var centerLatitude: Double {
        (minLatitude + maxLatitude) / 2
    }

    /// The middle of the box, -180...180.
    public var centerLongitude: Double {
        let center = (minLongitude + maxLongitude) / 2
        return center > 180 ? center - 360 : center
    }
}

public enum CountryGeometry {
    /// The box around the country with the given ISO 3166-1 alpha-2 code (case-insensitive), or nil when the
    /// bundled data does not cover it.
    public static func boundingRegion(forCountryCode code: String?) -> CountryBoundingRegion? {
        guard let code else { return nil }
        return regions[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    private struct Dataset: Decodable {
        let bounds: [String: [Double]]
    }

    /// Decoded once on first use. An unreadable resource yields no boxes rather than a crash.
    private static let regions: [String: CountryBoundingRegion] = {
        guard
            let url = Bundle.module.url(forResource: "country-bounds", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let dataset = try? JSONDecoder().decode(Dataset.self, from: data)
        else {
            return [:]
        }

        return dataset.bounds.compactMapValues { values in
            guard values.count == 4 else { return nil }
            return CountryBoundingRegion(
                minLatitude: values[0],
                maxLatitude: values[1],
                minLongitude: values[2],
                maxLongitude: values[3]
            )
        }
    }()
}
