import Foundation

public struct NomadLifePreferences: Codable, Equatable, Sendable {
    public var isAutomaticCollectionEnabled: Bool
    public var homeTimeZoneIdentifier: String
    public var areQuietAlertsEnabled: Bool
    public var quietHoursStart: Int
    public var quietHoursEnd: Int

    public init(
        isAutomaticCollectionEnabled: Bool = true,
        homeTimeZoneIdentifier: String = TimeZone.current.identifier,
        areQuietAlertsEnabled: Bool = false,
        quietHoursStart: Int = 22,
        quietHoursEnd: Int = 8
    ) {
        self.isAutomaticCollectionEnabled = isAutomaticCollectionEnabled
        self.homeTimeZoneIdentifier = TimeZone(identifier: homeTimeZoneIdentifier)?.identifier ?? TimeZone.current.identifier
        self.areQuietAlertsEnabled = areQuietAlertsEnabled
        self.quietHoursStart = quietHoursStart.clamped(to: 0...23)
        self.quietHoursEnd = quietHoursEnd.clamped(to: 0...23)
    }
}

public enum NomadLifeVenueConfidence: String, Codable, Sendable {
    case suggested
    case confirmed
}

public struct NomadLifeConnectionDiaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var latitude: Double
    public var longitude: Double
    public var suggestedName: String
    public var name: String?
    public var note: String?
    public var confidence: NomadLifeVenueConfidence
    public var sampleCount: Int
    public var averageLatencyMilliseconds: Double?
    public var disconnectCount: Int
    public var source: String

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, latitude: Double, longitude: Double, suggestedName: String, name: String? = nil, note: String? = nil, confidence: NomadLifeVenueConfidence = .suggested, sampleCount: Int, averageLatencyMilliseconds: Double?, disconnectCount: Int, source: String = "Device location") {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.latitude = latitude
        self.longitude = longitude
        self.suggestedName = suggestedName
        self.name = name
        self.note = note
        self.confidence = confidence
        self.sampleCount = sampleCount
        self.averageLatencyMilliseconds = averageLatencyMilliseconds
        self.disconnectCount = disconnectCount
        self.source = source
    }

    public var displayName: String {
        name?.isEmpty == false ? name! : suggestedName
    }
}

public struct NomadLifeTimeZonePresentation: Equatable, Sendable {
    public let homeLabel: String
    public let currentLabel: String
    public let relativeDayDescription: String

    public init(homeTimeZoneIdentifier: String, currentTimeZoneIdentifier: String, date: Date = .now) {
        let home = TimeZone(identifier: homeTimeZoneIdentifier) ?? .current
        let current = TimeZone(identifier: currentTimeZoneIdentifier) ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = home
        homeLabel = "Home \(formatter.string(from: date))"
        formatter.timeZone = current
        currentLabel = "Here \(formatter.string(from: date))"
        let homeDay = Self.utcDayComponents(for: date, zone: home)
        let currentDay = Self.utcDayComponents(for: date, zone: current)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let difference = utc.dateComponents([.day], from: utc.date(from: homeDay) ?? date, to: utc.date(from: currentDay) ?? date).day ?? 0
        relativeDayDescription = difference == 0 ? "Same day at home" : (difference > 0 ? "Tomorrow at home" : "Yesterday at home")
    }

    private static func utcDayComponents(for date: Date, zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let value = calendar.dateComponents([.year, .month, .day], from: date)
        return DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: value.year, month: value.month, day: value.day)
    }
}

public enum NomadLifeQuietAlertKind: String, Codable, Equatable, Sendable { case disconnected, recovered, vpnChanged, weakCharging }

public struct NomadLifeQuietAlert: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let kind: NomadLifeQuietAlertKind
    public let title: String
    public let body: String
}

private extension Int { func clamped(to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
} }
