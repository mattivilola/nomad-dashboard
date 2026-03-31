import Foundation

public actor FileVisitedCountryDaysStore: VisitedCountryDaysStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dayCalendar: Calendar

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        dayCalendar = Self.defaultDayCalendar()
    }

    init(fileURL: URL, dayCalendar: Calendar) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        self.dayCalendar = dayCalendar
    }

    public func loadAll() async throws -> [VisitedCountryDay] {
        try loadPersistedDays().sorted { $0.day < $1.day }
    }

    public func record(_ input: VisitedCountryDayInput) async throws {
        guard let entry = VisitedCountryDay.from(input) else {
            return
        }

        var entries = try loadPersistedDays().sorted { $0.day < $1.day }

        if let existingIndex = entries.firstIndex(where: { $0.day == entry.day }) {
            let existingEntry = entries[existingIndex]
            guard shouldReplace(existing: existingEntry, with: entry) else {
                return
            }

            entries[existingIndex] = entry
        } else {
            entries.append(entry)
        }

        try persist(rebuiltEntries(from: entries))
    }

    public func reset() async throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func shouldReplace(existing: VisitedCountryDay, with newEntry: VisitedCountryDay) -> Bool {
        if existing.isInferred {
            return true
        }

        if existing.source == .publicIPGeolocation, newEntry.source == .deviceLocation {
            return true
        }

        return false
    }

    private func inferredDays(
        between previousEntry: VisitedCountryDay,
        and currentEntry: VisitedCountryDay,
        gapDays: Int
    ) -> [VisitedCountryDay] {
        guard gapDays > 0 else {
            return []
        }

        let usesSameCountry = previousEntry.countryCode == currentEntry.countryCode
            || (
                previousEntry.countryCode == nil
                    && currentEntry.countryCode == nil
                    && previousEntry.country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        == currentEntry.country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            )

        let previousCountryCount = usesSameCountry ? gapDays : (gapDays + 1) / 2

        return (1...gapDays).compactMap { offset in
            guard let day = offsetDay(previousEntry.day, by: offset) else {
                return nil
            }

            let template = offset <= previousCountryCount ? previousEntry : currentEntry
            return VisitedCountryDay(
                day: day,
                country: template.country,
                countryCode: template.countryCode,
                source: template.source,
                isInferred: true
            )
        }
    }

    private func rebuiltEntries(from entries: [VisitedCountryDay]) -> [VisitedCountryDay] {
        let observedEntries = entries
            .filter { $0.isInferred == false }
            .sorted { $0.day < $1.day }

        guard let firstEntry = observedEntries.first else {
            return []
        }

        var rebuiltEntries = [firstEntry]

        for index in observedEntries.indices.dropFirst() {
            let previousEntry = observedEntries[index - 1]
            let currentEntry = observedEntries[index]
            let gapDays = dayDistance(from: previousEntry.day, to: currentEntry.day) - 1

            if gapDays > 0 {
                rebuiltEntries.append(
                    contentsOf: inferredDays(
                        between: previousEntry,
                        and: currentEntry,
                        gapDays: gapDays
                    )
                )
            }

            rebuiltEntries.append(currentEntry)
        }

        return rebuiltEntries
    }

    private func dayDistance(from start: VisitedCountryDayStamp, to end: VisitedCountryDayStamp) -> Int {
        guard
            let startDate = date(for: start),
            let endDate = date(for: end)
        else {
            return 0
        }

        return dayCalendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    private func offsetDay(_ day: VisitedCountryDayStamp, by value: Int) -> VisitedCountryDayStamp? {
        guard
            let date = date(for: day),
            let offsetDate = dayCalendar.date(byAdding: .day, value: value, to: date)
        else {
            return nil
        }

        return VisitedCountryDayStamp(date: offsetDate, calendar: dayCalendar)
    }

    private func date(for day: VisitedCountryDayStamp) -> Date? {
        dayCalendar.date(from: DateComponents(
            calendar: dayCalendar,
            timeZone: dayCalendar.timeZone,
            year: day.year,
            month: day.month,
            day: day.day,
            hour: 12
        ))
    }

    private func persist(_ entries: [VisitedCountryDay]) throws {
        try ensureDirectory()
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func loadPersistedDays() throws -> [VisitedCountryDay] {
        try ensureDirectory()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([VisitedCountryDay].self, from: data)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func defaultDayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
