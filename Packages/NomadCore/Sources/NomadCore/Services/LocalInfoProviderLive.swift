import Foundation

public actor LiveLocalInfoProvider: LocalInfoProvider, LocalPriceLevelProviderConfigurationUpdating {
    private let session: URLSession
    private let ttl: TimeInterval
    private let localPriceLevelProvider: any LocalPriceLevelProvider
    private let nowProvider: @Sendable () -> Date
    private var publicHolidayCache: [String: CachedValue<[NagerHoliday]>] = [:]
    private var schoolHolidayCache: [String: CachedValue<[OpenHolidayEntry]>] = [:]
    private var subdivisionCache: [String: CachedValue<[OpenSubdivisionNode]>] = [:]

    private static let nagerDateSource = HolidaySourceAttribution(
        name: "Nager.Date",
        url: URL(string: "https://date.nager.at/")
    )
    private static let openHolidaysSource = HolidaySourceAttribution(
        name: "OpenHolidays",
        url: URL(string: "https://openholidaysapi.org/")
    )

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 21_600,
        localPriceLevelProvider: any LocalPriceLevelProvider,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.ttl = ttl
        self.localPriceLevelProvider = localPriceLevelProvider
        self.nowProvider = nowProvider
    }

    public func setHUDUserAPIToken(_ token: String?) async {
        if let configurableProvider = localPriceLevelProvider as? LocalPriceLevelProviderConfigurationUpdating {
            await configurableProvider.setHUDUserAPIToken(token)
        }
    }

    public func info(for request: LocalInfoRequest, forceRefresh: Bool) async throws -> LocalInfoSnapshot {
        let countryCode = request.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard countryCode.isEmpty == false else {
            return LocalInfoSnapshot(
                status: .locationRequired,
                locality: normalizedValue(request.locality),
                administrativeRegion: normalizedValue(request.administrativeRegion),
                countryCode: nil,
                countryName: normalizedValue(request.countryName),
                timeZoneIdentifier: normalizedValue(request.timeZoneIdentifier),
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Country information is unavailable."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: nil,
                detail: "Allow current location or external IP location to estimate local info.",
                note: nil
            )
        }

        let timeZone = resolvedTimeZone(identifier: request.timeZoneIdentifier)
        let calendar = gregorianCalendar(timeZone: timeZone)
        let today = calendar.startOfDay(for: nowProvider())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let countryName = normalizedValue(request.countryName)
        let locality = normalizedValue(request.locality)
        let administrativeRegion = normalizedValue(request.administrativeRegion)

        async let matchedSubdivisionTask = matchedSubdivision(
            countryCode: countryCode,
            administrativeRegion: administrativeRegion,
            locality: locality,
            forceRefresh: forceRefresh
        )
        async let localPriceTask = localPriceLevelSnapshot(for: request, forceRefresh: forceRefresh)

        let matchedSubdivision = await matchedSubdivisionTask
        let localPriceLevel = await localPriceTask

        let publicHolidayResult = await resolvePublicHolidayStatus(
            countryCode: countryCode,
            subdivisionCode: matchedSubdivision?.code,
            calendar: calendar,
            today: today,
            tomorrow: tomorrow,
            forceRefresh: forceRefresh
        )
        let publicHolidayStatus = publicHolidayResult.status ?? LocalHolidayStatus(
            state: .unavailable,
            currentPeriod: nil,
            nextPeriod: nil,
            note: "Public holidays are unavailable right now."
        )
        let schoolHolidayResult = await resolveSchoolHolidayStatus(
            countryCode: countryCode,
            subdivisionCode: matchedSubdivision?.code,
            calendar: calendar,
            today: today,
            tomorrow: tomorrow,
            forceRefresh: forceRefresh
        )

        let priceRowsAvailable = localPriceLevel?.rows.isEmpty == false
        let schoolHolidayStatus = schoolHolidayResult.status
        let hasSchoolRow = schoolHolidayStatus != nil
        let publicHolidayReady = publicHolidayStatus.state == .current
            || publicHolidayStatus.state == .tomorrow
            || publicHolidayStatus.state == .upcoming

        let status: LocalInfoStatus = if publicHolidayReady, priceRowsAvailable, hasSchoolRow {
            .ready
        } else if publicHolidayReady || priceRowsAvailable || hasSchoolRow {
            .partial
        } else if publicHolidayStatus.state == .unsupported {
            .unsupported
        } else {
            .unavailable
        }

        var noteParts: [String] = []
        if let note = schoolHolidayResult.note {
            noteParts.append(note)
        }
        if let localPriceLevel {
            if localPriceLevel.rows.isEmpty {
                noteParts.append(contentsOf: [localPriceLevel.detail, localPriceLevel.note].compactMap(\.self))
            } else if let note = localPriceLevel.note {
                noteParts.append(note)
            }
        }

        let sources = uniqueSources(
            [Self.nagerDateSource]
                + (schoolHolidayResult.usedSource ? [Self.openHolidaysSource] : [])
                + (localPriceLevel?.sources.map { HolidaySourceAttribution(name: $0.name, url: $0.url) } ?? [])
        )

        let detail: String? = switch status {
        case .ready:
            nil
        case .partial:
            "Some local signals are limited right now."
        case .locationRequired:
            "Allow current location or external IP location to estimate local info."
        case .unsupported:
            publicHolidayStatus.note ?? "Local holiday data is not supported here yet."
        case .unavailable:
            publicHolidayStatus.note ?? "Local info is unavailable right now."
        }

        return LocalInfoSnapshot(
            status: status,
            locality: locality,
            administrativeRegion: administrativeRegion,
            countryCode: countryCode,
            countryName: countryName,
            timeZoneIdentifier: timeZone.identifier,
            subdivisionCode: matchedSubdivision?.code,
            publicHolidayStatus: publicHolidayStatus,
            schoolHolidayStatus: schoolHolidayStatus,
            localPriceLevel: localPriceLevel,
            sources: sources,
            fetchedAt: [publicHolidayResult.fetchedAt, schoolHolidayResult.fetchedAt, localPriceLevel?.fetchedAt]
                .compactMap(\.self)
                .max(),
            detail: detail,
            note: noteParts.joined(separator: " ").nilIfEmpty
        )
    }

    private func localPriceLevelSnapshot(
        for request: LocalInfoRequest,
        forceRefresh: Bool
    ) async -> LocalPriceLevelSnapshot? {
        let priceRequest = LocalPriceSearchRequest(
            coordinate: request.coordinate,
            countryCode: request.countryCode,
            countryName: request.countryName,
            locality: request.locality
        )

        do {
            return try await localPriceLevelProvider.prices(for: priceRequest, forceRefresh: forceRefresh)
        } catch {
            return LocalPriceLevelSnapshot(
                status: .unavailable,
                summaryBand: nil,
                countryCode: request.countryCode,
                countryName: request.countryName,
                rows: [],
                sources: [],
                fetchedAt: Date(),
                detail: "Local price signals are unavailable right now.",
                note: nil
            )
        }
    }

    private func resolvePublicHolidayStatus(
        countryCode: String,
        subdivisionCode: String?,
        calendar: Calendar,
        today: Date,
        tomorrow: Date,
        forceRefresh: Bool
    ) async -> HolidayResolutionResult {
        do {
            var holidays = try await publicHolidays(countryCode: countryCode, year: calendar.component(.year, from: today), forceRefresh: forceRefresh)
            var periods = makePublicHolidayPeriods(
                from: holidays,
                timeZone: calendar.timeZone,
                subdivisionCode: subdivisionCode
            )

            if currentOrUpcomingHoliday(from: periods, calendar: calendar, today: today) == nil {
                let nextYear = calendar.component(.year, from: today) + 1
                holidays += try await publicHolidays(countryCode: countryCode, year: nextYear, forceRefresh: forceRefresh)
                periods = makePublicHolidayPeriods(
                    from: holidays,
                    timeZone: calendar.timeZone,
                    subdivisionCode: subdivisionCode
                )
            }

            let status = holidayStatus(
                from: periods,
                calendar: calendar,
                today: today,
                tomorrow: tomorrow,
                unsupportedMessage: "Public holidays are not available for this country right now."
            )
            return HolidayResolutionResult(status: status, fetchedAt: Date(), note: nil, usedSource: true)
        } catch ProviderError.missingCountryCode {
            return HolidayResolutionResult(
                status: LocalHolidayStatus(
                    state: .unsupported,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Public holidays are not available for this country right now."
                ),
                fetchedAt: nil,
                note: nil,
                usedSource: true
            )
        } catch {
            return HolidayResolutionResult(
                status: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Public holidays are unavailable right now."
                ),
                fetchedAt: nil,
                note: nil,
                usedSource: true
            )
        }
    }

    private func resolveSchoolHolidayStatus(
        countryCode: String,
        subdivisionCode: String?,
        calendar: Calendar,
        today: Date,
        tomorrow: Date,
        forceRefresh: Bool
    ) async -> HolidayResolutionResult {
        guard let subdivisionCode else {
            return HolidayResolutionResult(
                status: nil,
                fetchedAt: nil,
                note: "School holiday coverage needs a confident regional match.",
                usedSource: false
            )
        }

        do {
            let year = calendar.component(.year, from: today)
            var holidays = try await schoolHolidays(countryCode: countryCode, year: year, forceRefresh: forceRefresh)
            var periods = makeSchoolHolidayPeriods(
                from: holidays,
                timeZone: calendar.timeZone,
                subdivisionCode: subdivisionCode
            )

            if currentOrUpcomingHoliday(from: periods, calendar: calendar, today: today) == nil {
                holidays += try await schoolHolidays(countryCode: countryCode, year: year + 1, forceRefresh: forceRefresh)
                periods = makeSchoolHolidayPeriods(
                    from: holidays,
                    timeZone: calendar.timeZone,
                    subdivisionCode: subdivisionCode
                )
            }

            guard periods.isEmpty == false else {
                return HolidayResolutionResult(
                    status: nil,
                    fetchedAt: Date(),
                    note: "Local school-break coverage is unavailable for this area.",
                    usedSource: true
                )
            }

            return HolidayResolutionResult(
                status: holidayStatus(
                    from: periods,
                    calendar: calendar,
                    today: today,
                    tomorrow: tomorrow,
                    unsupportedMessage: "School holiday coverage is not available for this area."
                ),
                fetchedAt: Date(),
                note: nil,
                usedSource: true
            )
        } catch ProviderError.missingCountryCode {
            return HolidayResolutionResult(
                status: nil,
                fetchedAt: nil,
                note: "School holiday coverage is not available for this country.",
                usedSource: true
            )
        } catch {
            return HolidayResolutionResult(
                status: nil,
                fetchedAt: nil,
                note: "School holiday coverage is unavailable right now.",
                usedSource: true
            )
        }
    }

    private func holidayStatus(
        from periods: [HolidayPeriodSnapshot],
        calendar: Calendar,
        today: Date,
        tomorrow: Date,
        unsupportedMessage: String
    ) -> LocalHolidayStatus {
        let sortedPeriods = periods.sorted { $0.startDate < $1.startDate }
        guard let currentOrUpcoming = currentOrUpcomingHoliday(from: sortedPeriods, calendar: calendar, today: today) else {
            return LocalHolidayStatus(
                state: .unsupported,
                currentPeriod: nil,
                nextPeriod: nil,
                note: unsupportedMessage
            )
        }

        if let currentPeriod = currentOrUpcoming.current {
            return LocalHolidayStatus(
                state: .current,
                currentPeriod: currentPeriod,
                nextPeriod: currentOrUpcoming.next,
                note: nil
            )
        }

        if let nextPeriod = currentOrUpcoming.next {
            let state: LocalHolidayState = calendar.isDate(nextPeriod.startDate, inSameDayAs: tomorrow) ? .tomorrow : .upcoming
            return LocalHolidayStatus(
                state: state,
                currentPeriod: nil,
                nextPeriod: nextPeriod,
                note: nil
            )
        }

        return LocalHolidayStatus(
            state: .unsupported,
            currentPeriod: nil,
            nextPeriod: nil,
            note: unsupportedMessage
        )
    }

    private func currentOrUpcomingHoliday(
        from periods: [HolidayPeriodSnapshot],
        calendar: Calendar,
        today: Date
    ) -> (current: HolidayPeriodSnapshot?, next: HolidayPeriodSnapshot?)? {
        let current = periods.first(where: { period in
            periodContainsDay(period, day: today, calendar: calendar)
        })
        let next = periods.first(where: { $0.startDate >= today })

        if current != nil || next != nil {
            return (current, next)
        }

        return nil
    }

    private func matchedSubdivision(
        countryCode: String,
        administrativeRegion: String?,
        locality: String?,
        forceRefresh: Bool
    ) async -> SubdivisionMatch? {
        let subdivisions: [OpenSubdivisionNode]
        do {
            subdivisions = try await subdivisionNodes(countryCode: countryCode, forceRefresh: forceRefresh)
        } catch {
            return nil
        }

        guard subdivisions.isEmpty == false else {
            return nil
        }

        let region = normalizedValue(administrativeRegion).map(normalizedKey(for:))
        let city = normalizedValue(locality).map(normalizedKey(for:))
        let matches = flattenedSubdivisions(from: subdivisions).filter { subdivision in
            let candidates = subdivisionCandidates(for: subdivision)
            if let region, candidates.contains(region) {
                return true
            }
            if let city, candidates.contains(city) {
                return true
            }
            return false
        }

        guard matches.count == 1, let subdivision = matches.first else {
            return nil
        }

        return SubdivisionMatch(code: subdivision.code)
    }

    private func publicHolidays(
        countryCode: String,
        year: Int,
        forceRefresh: Bool
    ) async throws -> [NagerHoliday] {
        let cacheKey = "\(countryCode)|\(year)"
        if !forceRefresh, let cached = publicHolidayCache[cacheKey], isFresh(cached.fetchedAt) {
            return cached.value
        }

        let url = URL(string: "https://date.nager.at/api/v3/publicholidays/\(year)/\(countryCode)")!
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw ProviderError.missingCountryCode
        default:
            throw ProviderError.invalidResponse
        }

        let holidays = try JSONDecoder().decode([NagerHoliday].self, from: data)
        publicHolidayCache[cacheKey] = CachedValue(value: holidays, fetchedAt: Date())
        return holidays
    }

    private func schoolHolidays(
        countryCode: String,
        year: Int,
        forceRefresh: Bool
    ) async throws -> [OpenHolidayEntry] {
        let cacheKey = "\(countryCode)|\(year)"
        if !forceRefresh, let cached = schoolHolidayCache[cacheKey], isFresh(cached.fetchedAt) {
            return cached.value
        }

        var components = URLComponents(string: "https://openholidaysapi.org/SchoolHolidays")!
        components.queryItems = [
            URLQueryItem(name: "countryIsoCode", value: countryCode),
            URLQueryItem(name: "validFrom", value: "\(year)-01-01"),
            URLQueryItem(name: "validTo", value: "\(year)-12-31"),
            URLQueryItem(name: "languageIsoCode", value: "EN")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw ProviderError.missingCountryCode
        default:
            throw ProviderError.invalidResponse
        }

        let holidays = try JSONDecoder().decode([OpenHolidayEntry].self, from: data)
        schoolHolidayCache[cacheKey] = CachedValue(value: holidays, fetchedAt: Date())
        return holidays
    }

    private func subdivisionNodes(
        countryCode: String,
        forceRefresh: Bool
    ) async throws -> [OpenSubdivisionNode] {
        if !forceRefresh, let cached = subdivisionCache[countryCode], isFresh(cached.fetchedAt) {
            return cached.value
        }

        var components = URLComponents(string: "https://openholidaysapi.org/Subdivisions")!
        components.queryItems = [
            URLQueryItem(name: "countryIsoCode", value: countryCode),
            URLQueryItem(name: "languageIsoCode", value: "EN")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ProviderError.invalidResponse
        }

        let subdivisions = try JSONDecoder().decode([OpenSubdivisionNode].self, from: data)
        subdivisionCache[countryCode] = CachedValue(value: subdivisions, fetchedAt: Date())
        return subdivisions
    }

    private func makePublicHolidayPeriods(
        from holidays: [NagerHoliday],
        timeZone: TimeZone,
        subdivisionCode: String?
    ) -> [HolidayPeriodSnapshot] {
        holidays.compactMap { holiday in
            guard matchesSubdivision(holiday.counties, subdivisionCode: subdivisionCode, treatEmptyAsMatch: true) else {
                return nil
            }
            guard let date = makeDate(from: holiday.date, timeZone: timeZone) else {
                return nil
            }
            return HolidayPeriodSnapshot(
                name: normalizedValue(holiday.localName) ?? holiday.name,
                startDate: date,
                endDate: date
            )
        }
    }

    private func makeSchoolHolidayPeriods(
        from holidays: [OpenHolidayEntry],
        timeZone: TimeZone,
        subdivisionCode: String
    ) -> [HolidayPeriodSnapshot] {
        holidays.compactMap { holiday in
            let holidaySubdivisionCodes = holiday.subdivisions?.map(\.code) ?? []
            guard matchesSubdivision(holidaySubdivisionCodes, subdivisionCode: subdivisionCode, treatEmptyAsMatch: holiday.nationwide ?? false) else {
                return nil
            }
            guard let startDate = makeDate(from: holiday.startDate, timeZone: timeZone),
                  let endDate = makeDate(from: holiday.endDate, timeZone: timeZone)
            else {
                return nil
            }
            return HolidayPeriodSnapshot(
                name: localizedText(holiday.name),
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    private func matchesSubdivision(
        _ candidateCodes: [String]?,
        subdivisionCode: String?,
        treatEmptyAsMatch: Bool
    ) -> Bool {
        guard let subdivisionCode else {
            return treatEmptyAsMatch && (candidateCodes?.isEmpty ?? true)
        }

        guard let candidateCodes, candidateCodes.isEmpty == false else {
            return treatEmptyAsMatch
        }

        return candidateCodes.contains { code in
            code == subdivisionCode
                || code.hasPrefix(subdivisionCode + "-")
                || subdivisionCode.hasPrefix(code + "-")
        }
    }

    private func flattenedSubdivisions(from nodes: [OpenSubdivisionNode]) -> [OpenSubdivisionNode] {
        nodes + nodes.flatMap { flattenedSubdivisions(from: $0.children ?? []) }
    }

    private func subdivisionCandidates(for subdivision: OpenSubdivisionNode) -> Set<String> {
        var values: Set<String> = [normalizedKey(for: subdivision.code)]
        if let shortName = normalizedValue(subdivision.shortName) {
            values.insert(normalizedKey(for: shortName))
        }
        if let isoCode = normalizedValue(subdivision.isoCode) {
            values.insert(normalizedKey(for: isoCode))
            if isoCode.contains("-"), let suffix = isoCode.split(separator: "-").last {
                values.insert(normalizedKey(for: String(suffix)))
            }
        }
        subdivision.name.forEach { value in
            values.insert(normalizedKey(for: value.text))
        }
        return values
    }

    private func uniqueSources(_ values: [HolidaySourceAttribution]) -> [HolidaySourceAttribution] {
        var seen: Set<HolidaySourceAttribution> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func resolvedTimeZone(identifier: String?) -> TimeZone {
        if let identifier = normalizedValue(identifier), let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }

        return TimeZone.current
    }

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func isFresh(_ fetchedAt: Date) -> Bool {
        abs(fetchedAt.timeIntervalSinceNow) < ttl
    }

    private func makeDate(from value: String, timeZone: TimeZone) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func periodContainsDay(_ period: HolidayPeriodSnapshot, day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: period.startDate)
        let end = calendar.startOfDay(for: period.endDate)
        let current = calendar.startOfDay(for: day)
        return current >= start && current <= end
    }

    private func localizedText(_ entries: [LocalizedName]) -> String {
        entries.first(where: { $0.language.uppercased() == "EN" })?.text
            ?? entries.first?.text
            ?? "Holiday"
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedKey(for value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "", options: .regularExpression)
            .lowercased()
    }
}

private struct HolidayResolutionResult {
    let status: LocalHolidayStatus?
    let fetchedAt: Date?
    let note: String?
    let usedSource: Bool
}

private struct SubdivisionMatch {
    let code: String
}

private struct CachedValue<Value> {
    let value: Value
    let fetchedAt: Date
}

private struct NagerHoliday: Decodable {
    let date: String
    let localName: String?
    let name: String
    let counties: [String]?
}

private struct OpenHolidayEntry: Decodable {
    let startDate: String
    let endDate: String
    let name: [LocalizedName]
    let nationwide: Bool?
    let subdivisions: [OpenSubdivisionReference]?
}

private struct LocalizedName: Decodable {
    let language: String
    let text: String
}

private struct OpenSubdivisionReference: Decodable {
    let code: String
}

private struct OpenSubdivisionNode: Decodable {
    let code: String
    let isoCode: String?
    let shortName: String?
    let name: [LocalizedName]
    let children: [OpenSubdivisionNode]?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
