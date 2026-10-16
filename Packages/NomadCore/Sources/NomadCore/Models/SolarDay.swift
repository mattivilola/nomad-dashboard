import Foundation

/// Sunrise, sunset and civil twilight for one calendar day at one place.
///
/// Computed entirely on the Mac with the NOAA solar calculator equations (Jean Meeus, "Astronomical
/// Algorithms"): no network, no WeatherKit. Accurate to about a minute outside the polar circles.
///
/// `civilDawn` is the morning civil twilight start and `civilDusk` is the evening civil twilight end
/// that follows the day's sunset, so near the summer solstice at high latitudes it can fall after
/// midnight on the next calendar day.
public struct SolarDay: Equatable, Sendable {
    public let sunrise: Date?
    public let sunset: Date?
    public let civilDawn: Date?
    public let civilDusk: Date?
    /// The sun stays above the horizon all day (midnight sun).
    public let isPolarDay: Bool
    /// The sun stays below the horizon all day.
    public let isPolarNight: Bool

    public init(
        sunrise: Date?,
        sunset: Date?,
        civilDawn: Date?,
        civilDusk: Date?,
        isPolarDay: Bool,
        isPolarNight: Bool
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.civilDawn = civilDawn
        self.civilDusk = civilDusk
        self.isPolarDay = isPolarDay
        self.isPolarNight = isPolarNight
    }

    /// The solar day for the calendar day that contains `date` in `timeZone`.
    ///
    /// - Parameters:
    ///   - latitude: Degrees north, -90...90.
    ///   - longitude: Degrees east, -180...180.
    public static func compute(latitude: Double, longitude: Double, date: Date, timeZone: TimeZone) -> SolarDay {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else {
            return SolarDay(sunrise: nil, sunset: nil, civilDawn: nil, civilDusk: nil, isPolarDay: false, isPolarNight: false)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let localNoon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? date

        let observer = Observer(latitude: latitude, longitude: longitude)
        // Solar noon nearest to local noon: the UTC day it falls in is the base for every event of this day.
        let noon = observer.solarNoon(near: localNoon)

        let horizon = observer.hourAngle(zenith: Observer.horizonZenith, at: noon.parameters)
        let isPolarDay = horizon == .alwaysUp
        let isPolarNight = horizon == .alwaysDown

        let rise = observer.event(zenith: Observer.horizonZenith, rising: true, base: noon)
        let set = observer.event(zenith: Observer.horizonZenith, rising: false, base: noon)
        let dawn = observer.event(zenith: Observer.civilZenith, rising: true, base: noon)
        let dusk = observer.event(zenith: Observer.civilZenith, rising: false, base: noon)

        return SolarDay(
            sunrise: isPolarDay || isPolarNight ? nil : rise,
            sunset: isPolarDay || isPolarNight ? nil : set,
            civilDawn: dawn,
            civilDusk: dusk,
            isPolarDay: isPolarDay,
            isPolarNight: isPolarNight
        )
    }
}

// MARK: - NOAA solar position

private struct Observer {
    /// 90.833 degrees: the sun's centre at the horizon including refraction and the solar radius.
    static let horizonZenith = 90.833
    /// 96 degrees: the sun's centre 6 degrees below the horizon.
    static let civilZenith = 96.0

    let latitude: Double
    let longitude: Double

    struct SolarParameters {
        /// Equation of time in minutes.
        let equationOfTime: Double
        /// Solar declination in degrees.
        let declination: Double
    }

    struct NoonBase {
        /// Unix time of UTC midnight that starts the UTC day containing the solar noon.
        let utcMidnight: TimeInterval
        let instant: Date
        let parameters: SolarParameters
    }

    enum HourAngle: Equatable {
        case degrees(Double)
        case alwaysUp
        case alwaysDown
    }

    func solarNoon(near anchor: Date) -> NoonBase {
        var instant = anchor
        var utcMidnight = Self.utcMidnight(of: anchor)
        var parameters = Self.parameters(at: anchor)

        for _ in 0..<3 {
            parameters = Self.parameters(at: instant)
            var candidate = utcMidnight + (720 - 4 * longitude - parameters.equationOfTime) * 60
            // Keep the solar noon that is closest to the local noon anchor.
            while candidate - anchor.timeIntervalSince1970 > 43_200 {
                utcMidnight -= 86_400
                candidate -= 86_400
            }
            while anchor.timeIntervalSince1970 - candidate > 43_200 {
                utcMidnight += 86_400
                candidate += 86_400
            }
            instant = Date(timeIntervalSince1970: candidate)
        }

        return NoonBase(utcMidnight: utcMidnight, instant: instant, parameters: Self.parameters(at: instant))
    }

    /// The rising or setting instant at `zenith`, refined at the event time as the NOAA calculator does.
    /// Nil when the sun never crosses that zenith on this day.
    func event(zenith: Double, rising: Bool, base: NoonBase) -> Date? {
        var parameters = base.parameters
        var instant: Date?

        for _ in 0..<3 {
            guard case let .degrees(angle) = hourAngle(zenith: zenith, at: parameters) else {
                break
            }
            let minutes = 720 - 4 * (longitude + (rising ? angle : -angle)) - parameters.equationOfTime
            let refined = Date(timeIntervalSince1970: base.utcMidnight + minutes * 60)
            instant = refined
            parameters = Self.parameters(at: refined)
        }
        return instant
    }

    func hourAngle(zenith: Double, at parameters: SolarParameters) -> HourAngle {
        let latitudeRadians = Self.radians(latitude)
        let declinationRadians = Self.radians(parameters.declination)
        let cosine = cos(Self.radians(zenith)) / (cos(latitudeRadians) * cos(declinationRadians))
            - tan(latitudeRadians) * tan(declinationRadians)

        if cosine > 1 {
            return .alwaysDown
        }
        if cosine < -1 {
            return .alwaysUp
        }
        return .degrees(Self.degrees(acos(cosine)))
    }

    static func parameters(at date: Date) -> SolarParameters {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        let anomalyRadians = radians(meanAnomaly)
        let centre = sin(anomalyRadians) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * anomalyRadians) * (0.019993 - 0.000101 * t)
            + sin(3 * anomalyRadians) * 0.000289

        let trueLongitude = meanLongitude + centre
        let omega = 125.04 - 1_934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(radians(omega))

        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(radians(omega))

        let declination = degrees(asin(sin(radians(obliquity)) * sin(radians(apparentLongitude))))

        let y = pow(tan(radians(obliquity) / 2), 2)
        let longitudeRadians = radians(meanLongitude)
        let equationOfTime = 4 * degrees(
            y * sin(2 * longitudeRadians)
                - 2 * eccentricity * sin(anomalyRadians)
                + 4 * eccentricity * y * sin(anomalyRadians) * cos(2 * longitudeRadians)
                - 0.5 * y * y * sin(4 * longitudeRadians)
                - 1.25 * eccentricity * eccentricity * sin(2 * anomalyRadians)
        )

        return SolarParameters(equationOfTime: equationOfTime, declination: declination)
    }

    private static func utcMidnight(of date: Date) -> TimeInterval {
        (date.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }
}

// MARK: - Snapshot location

/// Where and in which time zone to read the day's light for a dashboard snapshot.
public struct DaylightReference: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timeZone: TimeZone

    public init(latitude: Double, longitude: Double, timeZone: TimeZone) {
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
    }

    /// The device location first, else the IP location; nil when neither has coordinates.
    ///
    /// The time zone is the chosen location's own, then the snapshot's time zone, then the current one.
    /// (The snapshot's time zone follows the device location only, so an IP-only location needs its own.)
    public init?(travelContext: TravelContextSnapshot) {
        guard let source = [travelContext.deviceLocation, travelContext.location]
            .compactMap(\.self)
            .first(where: { $0.latitude != nil && $0.longitude != nil }),
            let latitude = source.latitude,
            let longitude = source.longitude,
            latitude.isFinite, longitude.isFinite,
            abs(latitude) <= 90, abs(longitude) <= 180
        else {
            return nil
        }

        self.init(
            latitude: latitude,
            longitude: longitude,
            timeZone: source.timeZone.flatMap(TimeZone.init(identifier:))
                ?? TimeZone(identifier: travelContext.timeZoneIdentifier)
                ?? .current
        )
    }

    public func solarDay(on date: Date) -> SolarDay {
        SolarDay.compute(latitude: latitude, longitude: longitude, date: date, timeZone: timeZone)
    }

    /// A short clock time (for example "18:12" or "6:12 PM") in the location's time zone.
    public func clockTime(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
