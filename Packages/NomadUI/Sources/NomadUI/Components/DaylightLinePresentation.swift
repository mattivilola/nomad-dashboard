import Foundation
import NomadCore

/// The compact "Sunrise 07:45 · Sunset 18:12" line under the weather conditions, computed on the Mac
/// from the device or IP location and shown in the location's time zone.
struct DaylightLinePresentation: Equatable {
    struct Segment: Equatable, Identifiable {
        let symbolName: String
        let text: String

        var id: String { symbolName }
    }

    let segments: [Segment]

    /// Nil when there is no location with coordinates, so the line stays hidden.
    init?(travelContext: TravelContextSnapshot, now: Date, locale: Locale = .autoupdatingCurrent) {
        guard let reference = DaylightReference(travelContext: travelContext) else {
            return nil
        }

        let day = reference.solarDay(on: now)
        if day.isPolarDay {
            segments = [Segment(symbolName: "sun.max", text: "Midnight sun")]
        } else if day.isPolarNight {
            segments = [Segment(symbolName: "moon.stars", text: "Polar night")]
        } else {
            segments = [
                day.sunrise.map { Segment(symbolName: "sunrise", text: "Sunrise \(reference.clockTime($0, locale: locale))") },
                day.sunset.map { Segment(symbolName: "sunset", text: "Sunset \(reference.clockTime($0, locale: locale))") }
            ].compactMap { $0 }
        }

        guard segments.isEmpty == false else {
            return nil
        }
    }

    /// "Sunrise 07:45 · Sunset 18:12", for accessibility.
    var summary: String {
        segments.map(\.text).joined(separator: " \u{B7} ")
    }
}
