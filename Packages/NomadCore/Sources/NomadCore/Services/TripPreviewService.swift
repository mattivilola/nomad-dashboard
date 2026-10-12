import Foundation

/// The network-backed parts of a trip preview: public holidays on the days of the trip and the current
/// travel advisory for the destination.
///
/// - Privacy: only the destination country code is sent (the holiday source also gets the year). Trip dates,
///   notes and the user's location never leave the Mac; holidays are filtered to the trip locally.
/// - Providers: public holidays come from the same source and cache as the Local Info card
///   (`PublicHolidayProvider`), the advisory from the dashboard's `TravelAdvisoryProvider`, asked for the
///   destination country alone rather than the bordering-countries scope the Travel Alerts card uses.
/// - Resource policy: offline or in Low Data mode nothing is requested and the saved answer, if any, is
///   returned. Otherwise a small `ProviderRequestBudget` bounds the requests, and each one has a deadline.
public actor LiveTripPreviewService: TripPreviewService {
    /// How long a saved answer is used without asking again. A manual refresh ignores it.
    static let holidayFreshness: TimeInterval = 6 * 3_600
    static let advisoryFreshness: TimeInterval = 12 * 3_600

    private struct Saved<Value: Sendable>: Sendable {
        let value: Value
        let fetchedAt: Date
    }

    private let holidayProvider: any PublicHolidayProvider
    private let advisoryProvider: any TravelAdvisoryProvider
    private let nowProvider: @Sendable () -> Date
    private var savedHolidays: [String: Saved<[HolidayPeriodSnapshot]>] = [:]
    private var savedAdvisories: [String: Saved<TravelAlertSignalSnapshot>] = [:]

    public init(
        holidayProvider: any PublicHolidayProvider,
        advisoryProvider: any TravelAdvisoryProvider,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.holidayProvider = holidayProvider
        self.advisoryProvider = advisoryProvider
        self.nowProvider = nowProvider
    }

    public func online(
        for trip: PlannedTrip,
        settings: AppSettings,
        policy: DashboardResourcePolicy,
        forceRefresh: Bool,
        calendar: Calendar
    ) async -> TripPreviewOnline? {
        guard let code = AppSettings.normalizedCountryCode(trip.countryCode) else {
            return nil
        }

        let mayRequest = policy.isOffline == false && policy.isLowData == false
        let budget = ProviderRequestBudget(limit: policy.reducesBackgroundWork ? 1 : 3)

        async let holidays = holidays(
            during: trip,
            countryCode: code,
            mayRequest: mayRequest,
            forceRefresh: forceRefresh,
            budget: budget,
            calendar: calendar
        )
        async let advisory = settings.travelAdvisoryEnabled
            ? advisory(
                countryCode: code,
                mayRequest: mayRequest,
                forceRefresh: forceRefresh,
                budget: budget
            )
            : nil

        let (holidayResult, advisoryResult) = await (holidays, advisory)
        guard holidayResult != nil || advisoryResult != nil else {
            return nil
        }

        let fetchedAt = [holidayResult?.fetchedAt, advisoryResult?.fetchedAt].compactMap(\.self).min() ?? nowProvider()
        return TripPreviewOnline(
            holidays: holidayResult?.value,
            advisory: advisoryResult?.value,
            fetchedAt: fetchedAt
        )
    }

    // MARK: Holidays

    private func holidays(
        during trip: PlannedTrip,
        countryCode: String,
        mayRequest: Bool,
        forceRefresh: Bool,
        budget: ProviderRequestBudget,
        calendar: Calendar
    ) async -> Saved<[HolidayPeriodSnapshot]>? {
        let first = trip.firstDay(calendar: calendar)
        let last = trip.lastDay(calendar: calendar)
        let years = calendar.component(.year, from: first)...calendar.component(.year, from: last)

        var periods: [HolidayPeriodSnapshot] = []
        var oldest: Date?
        for year in years {
            guard let saved = await holidaysOfYear(
                year,
                countryCode: countryCode,
                mayRequest: mayRequest,
                forceRefresh: forceRefresh,
                budget: budget,
                timeZone: calendar.timeZone
            ) else {
                // One missing year would hide holidays of the trip silently, so the whole answer is unavailable.
                return nil
            }
            periods += saved.value
            oldest = min(oldest ?? saved.fetchedAt, saved.fetchedAt)
        }

        var seen = Set<String>()
        let overlapping = periods
            .filter { period in
                calendar.startOfDay(for: period.endDate) >= first && calendar.startOfDay(for: period.startDate) <= last
            }
            .sorted { $0.startDate < $1.startDate }
            .filter { seen.insert("\($0.name)|\($0.startDate.timeIntervalSince1970)").inserted }
        return Saved(value: overlapping, fetchedAt: oldest ?? nowProvider())
    }

    private func holidaysOfYear(
        _ year: Int,
        countryCode: String,
        mayRequest: Bool,
        forceRefresh: Bool,
        budget: ProviderRequestBudget,
        timeZone: TimeZone
    ) async -> Saved<[HolidayPeriodSnapshot]>? {
        let key = "\(countryCode)|\(year)|\(timeZone.identifier)"
        let saved = savedHolidays[key]
        if let saved, mayRequest == false || (forceRefresh == false && isFresh(saved.fetchedAt, within: Self.holidayFreshness)) {
            return saved
        }
        guard mayRequest else {
            return nil
        }

        let provider = holidayProvider
        do {
            let periods = try await budget.run {
                try await withProviderDeadline {
                    try await provider.publicHolidays(
                        inCountry: countryCode,
                        year: year,
                        timeZone: timeZone,
                        forceRefresh: forceRefresh
                    )
                }
            }
            let fresh = Saved(value: periods, fetchedAt: nowProvider())
            savedHolidays[key] = fresh
            return fresh
        } catch {
            // A saved answer, however old, is better than none.
            return saved
        }
    }

    // MARK: Advisory

    private func advisory(
        countryCode: String,
        mayRequest: Bool,
        forceRefresh: Bool,
        budget: ProviderRequestBudget
    ) async -> Saved<TravelAlertSignalSnapshot>? {
        let saved = savedAdvisories[countryCode]
        if let saved, mayRequest == false || (forceRefresh == false && isFresh(saved.fetchedAt, within: Self.advisoryFreshness)) {
            return saved
        }
        guard mayRequest else {
            return nil
        }

        let provider = advisoryProvider
        do {
            let signal = try await budget.run {
                try await withProviderDeadline {
                    // The destination alone: no neighbouring countries, no location.
                    try await provider.advisory(for: [countryCode], primaryCountryCode: countryCode, forceRefresh: forceRefresh)
                }
            }
            let fresh = Saved(value: signal, fetchedAt: nowProvider())
            savedAdvisories[countryCode] = fresh
            return fresh
        } catch {
            return saved
        }
    }

    private func isFresh(_ fetchedAt: Date, within interval: TimeInterval) -> Bool {
        abs(nowProvider().timeIntervalSince(fetchedAt)) < interval
    }
}
