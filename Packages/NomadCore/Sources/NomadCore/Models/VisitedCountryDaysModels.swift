import Foundation

public struct VisitedCountryDayStamp: Codable, Equatable, Hashable, Sendable, Comparable, Identifiable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1_970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    public var id: String {
        key
    }

    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: VisitedCountryDayStamp, rhs: VisitedCountryDayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct VisitedCountryDayInput: Equatable, Sendable {
    public let day: VisitedCountryDayStamp
    public let country: String
    public let countryCode: String?
    public let source: VisitedPlaceSource
    public let observedAt: Date

    public init(
        day: VisitedCountryDayStamp,
        country: String,
        countryCode: String?,
        source: VisitedPlaceSource,
        observedAt: Date
    ) {
        self.day = day
        self.country = country
        self.countryCode = countryCode
        self.source = source
        self.observedAt = observedAt
    }
}

public struct VisitedCountryDay: Codable, Equatable, Sendable, Identifiable {
    public let day: VisitedCountryDayStamp
    public let country: String
    public let countryCode: String?
    public let source: VisitedPlaceSource
    public let isInferred: Bool
    public let isManual: Bool

    public init(
        day: VisitedCountryDayStamp,
        country: String,
        countryCode: String?,
        source: VisitedPlaceSource,
        isInferred: Bool,
        isManual: Bool = false
    ) {
        self.day = day
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = Self.normalizedCountryCode(countryCode)
        self.source = source
        self.isInferred = isInferred
        self.isManual = isManual
    }

    public var id: String {
        day.id
    }

    public var origin: VisitedCountryDayOrigin {
        if isManual {
            return .manual
        }
        return isInferred ? .inferred : .observed
    }

    private enum CodingKeys: String, CodingKey {
        case day, country, countryCode, source, isInferred, isManual
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(VisitedCountryDayStamp.self, forKey: .day)
        country = try container.decode(String.self, forKey: .country).trimmingCharacters(in: .whitespacesAndNewlines)
        countryCode = try Self.normalizedCountryCode(container.decodeIfPresent(String.self, forKey: .countryCode))
        source = try container.decode(VisitedPlaceSource.self, forKey: .source)
        isInferred = try container.decode(Bool.self, forKey: .isInferred)
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
    }

    func replacing(with input: VisitedCountryDayInput, isInferred: Bool = false) -> VisitedCountryDay {
        VisitedCountryDay(
            day: input.day,
            country: input.country,
            countryCode: input.countryCode,
            source: input.source,
            isInferred: isInferred
        )
    }

    static func from(_ input: VisitedCountryDayInput, isInferred: Bool = false) -> VisitedCountryDay? {
        let normalizedCountry = input.country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCountry.isEmpty == false else {
            return nil
        }

        return VisitedCountryDay(
            day: input.day,
            country: normalizedCountry,
            countryCode: input.countryCode,
            source: input.source,
            isInferred: isInferred
        )
    }

    private static func normalizedCountryCode(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue.uppercased()
    }
}

public enum VisitedCountryDayOrigin: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case observed
    case inferred
    case manual

    public var displayName: String {
        switch self {
        case .observed: "Observed"
        case .inferred: "Estimated"
        case .manual: "Manual"
        }
    }
}

public struct VisitedCountryDayOverride: Codable, Equatable, Sendable, Identifiable {
    public let day: VisitedCountryDayStamp
    public let country: String
    public let countryCode: String?
    public let source: VisitedCountryDayOrigin

    public init(
        day: VisitedCountryDayStamp,
        country: String,
        countryCode: String?,
        source: VisitedCountryDayOrigin = .manual
    ) {
        self.day = day
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.source = source
    }

    public var id: String {
        day.id
    }
}

public enum VisitedCountryDayStoreError: LocalizedError, Equatable, Sendable {
    case invalidDay(VisitedCountryDayStamp)
    case missingCountry
    case invalidCountryCode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDay: "Choose a valid calendar day."
        case .missingCountry: "Choose a country before saving."
        case let .invalidCountryCode(code): "\(code) is not a valid two-letter country code."
        }
    }
}

public struct VisitedCountryDaySummaryItem: Equatable, Sendable, Identifiable {
    public let country: String
    public let countryCode: String?
    public let dayCount: Int
    public let percentage: Double

    public init(country: String, countryCode: String?, dayCount: Int, percentage: Double) {
        self.country = country
        self.countryCode = countryCode
        self.dayCount = dayCount
        self.percentage = percentage
    }

    public var id: String {
        if let countryCode, countryCode.isEmpty == false {
            return countryCode
        }

        return country
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

public struct VisitedCountryDayYearSummary: Equatable, Sendable {
    public let year: Int
    public let totalTrackedDays: Int
    public let items: [VisitedCountryDaySummaryItem]

    public init(year: Int, totalTrackedDays: Int, items: [VisitedCountryDaySummaryItem]) {
        self.year = year
        self.totalTrackedDays = totalTrackedDays
        self.items = items
    }
}

public struct VisitedCountryDayMonthSummary: Equatable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let totalTrackedDays: Int
    public let items: [VisitedCountryDaySummaryItem]
    public let days: [VisitedCountryDay]

    public init(
        year: Int,
        month: Int,
        totalTrackedDays: Int,
        items: [VisitedCountryDaySummaryItem],
        days: [VisitedCountryDay]
    ) {
        self.year = year
        self.month = month
        self.totalTrackedDays = totalTrackedDays
        self.items = items
        self.days = days.sorted { $0.day < $1.day }
    }

    public var id: String {
        "\(year)-\(month)"
    }
}

public extension [VisitedCountryDay] {
    var availableYears: [Int] {
        Set(map(\.day.year)).sorted(by: >)
    }

    func yearSummary(for year: Int) -> VisitedCountryDayYearSummary? {
        let entries = filter { $0.day.year == year }
        guard entries.isEmpty == false else {
            return nil
        }

        let totalTrackedDays = entries.count
        let items = summaryItems(for: entries)

        return VisitedCountryDayYearSummary(year: year, totalTrackedDays: totalTrackedDays, items: items)
    }

    func monthlySummaries(for year: Int) -> [VisitedCountryDayMonthSummary] {
        let entries = filter { $0.day.year == year }
        guard entries.isEmpty == false else {
            return []
        }

        let entriesByMonth = Dictionary(grouping: entries, by: { $0.day.month })

        return entriesByMonth.keys.sorted(by: >).compactMap { month in
            guard let monthEntries = entriesByMonth[month] else {
                return nil
            }

            return VisitedCountryDayMonthSummary(
                year: year,
                month: month,
                totalTrackedDays: monthEntries.count,
                items: summaryItems(for: monthEntries),
                days: monthEntries
            )
        }
    }

    private func summaryItems(for entries: [VisitedCountryDay]) -> [VisitedCountryDaySummaryItem] {
        let totalTrackedDays = entries.count
        let groupedEntries = Dictionary(grouping: entries, by: SummaryKey.init(entry:))

        return groupedEntries.map { key, entries in
            let dayCount = entries.count
            return VisitedCountryDaySummaryItem(
                country: key.country,
                countryCode: key.countryCode,
                dayCount: dayCount,
                percentage: Double(dayCount) / Double(totalTrackedDays)
            )
        }
        .sorted { lhs, rhs in
            if lhs.dayCount == rhs.dayCount {
                return lhs.country.localizedCaseInsensitiveCompare(rhs.country) == .orderedAscending
            }

            return lhs.dayCount > rhs.dayCount
        }
    }
}

private struct SummaryKey: Hashable {
    let country: String
    let countryCode: String?

    init(entry: VisitedCountryDay) {
        country = entry.country
        countryCode = entry.countryCode
    }
}
