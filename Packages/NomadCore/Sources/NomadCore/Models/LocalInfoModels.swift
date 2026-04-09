import CoreLocation
import Foundation

public enum LocalInfoStatus: String, Codable, Equatable, Sendable {
    case ready
    case partial
    case locationRequired
    case unsupported
    case unavailable
}

public enum LocalHolidayState: String, Codable, Equatable, Sendable {
    case current
    case tomorrow
    case upcoming
    case unavailable
    case unsupported
}

public struct HolidaySourceAttribution: Equatable, Sendable, Hashable {
    public let name: String
    public let url: URL?

    public init(name: String, url: URL?) {
        self.name = name
        self.url = url
    }
}

public struct HolidayPeriodSnapshot: Equatable, Sendable {
    public let name: String
    public let startDate: Date
    public let endDate: Date

    public init(name: String, startDate: Date, endDate: Date) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct LocalHolidayStatus: Equatable, Sendable {
    public let state: LocalHolidayState
    public let currentPeriod: HolidayPeriodSnapshot?
    public let nextPeriod: HolidayPeriodSnapshot?
    public let note: String?

    public init(
        state: LocalHolidayState,
        currentPeriod: HolidayPeriodSnapshot?,
        nextPeriod: HolidayPeriodSnapshot?,
        note: String?
    ) {
        self.state = state
        self.currentPeriod = currentPeriod
        self.nextPeriod = nextPeriod
        self.note = note
    }
}

public struct LocalInfoRequest: Equatable, Sendable {
    public let coordinate: CLLocationCoordinate2D?
    public let countryCode: String
    public let countryName: String?
    public let locality: String?
    public let administrativeRegion: String?
    public let timeZoneIdentifier: String?

    public init(
        coordinate: CLLocationCoordinate2D?,
        countryCode: String,
        countryName: String?,
        locality: String?,
        administrativeRegion: String?,
        timeZoneIdentifier: String?
    ) {
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.countryName = countryName
        self.locality = locality
        self.administrativeRegion = administrativeRegion
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static func == (lhs: LocalInfoRequest, rhs: LocalInfoRequest) -> Bool {
        lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
            && lhs.countryCode == rhs.countryCode
            && lhs.countryName == rhs.countryName
            && lhs.locality == rhs.locality
            && lhs.administrativeRegion == rhs.administrativeRegion
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
    }
}

public struct LocalInfoSnapshot: Equatable, Sendable {
    public let status: LocalInfoStatus
    public let locality: String?
    public let administrativeRegion: String?
    public let countryCode: String?
    public let countryName: String?
    public let timeZoneIdentifier: String?
    public let subdivisionCode: String?
    public let publicHolidayStatus: LocalHolidayStatus
    public let schoolHolidayStatus: LocalHolidayStatus?
    public let localPriceLevel: LocalPriceLevelSnapshot?
    public let sources: [HolidaySourceAttribution]
    public let fetchedAt: Date?
    public let detail: String?
    public let note: String?

    public init(
        status: LocalInfoStatus,
        locality: String?,
        administrativeRegion: String?,
        countryCode: String?,
        countryName: String?,
        timeZoneIdentifier: String?,
        subdivisionCode: String?,
        publicHolidayStatus: LocalHolidayStatus,
        schoolHolidayStatus: LocalHolidayStatus?,
        localPriceLevel: LocalPriceLevelSnapshot?,
        sources: [HolidaySourceAttribution],
        fetchedAt: Date?,
        detail: String?,
        note: String?
    ) {
        self.status = status
        self.locality = locality
        self.administrativeRegion = administrativeRegion
        self.countryCode = countryCode
        self.countryName = countryName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.subdivisionCode = subdivisionCode
        self.publicHolidayStatus = publicHolidayStatus
        self.schoolHolidayStatus = schoolHolidayStatus
        self.localPriceLevel = localPriceLevel
        self.sources = sources
        self.fetchedAt = fetchedAt
        self.detail = detail
        self.note = note
    }
}
