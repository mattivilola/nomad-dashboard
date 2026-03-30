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
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
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

    public init(
        day: VisitedCountryDayStamp,
        country: String,
        countryCode: String?,
        source: VisitedPlaceSource,
        isInferred: Bool
    ) {
        self.day = day
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = Self.normalizedCountryCode(countryCode)
        self.source = source
        self.isInferred = isInferred
    }

    public var id: String {
        day.id
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
        Set(map { $0.day.year }).sorted(by: >)
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
