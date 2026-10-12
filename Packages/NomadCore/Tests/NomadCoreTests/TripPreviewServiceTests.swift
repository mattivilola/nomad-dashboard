import Foundation
import Testing
@testable import NomadCore

/// A service that has nothing to add; for tests that build dashboard dependencies.
struct FixedTripPreviewService: TripPreviewService {
    var result: TripPreviewOnline?

    func online(
        for trip: PlannedTrip,
        settings: AppSettings,
        policy: DashboardResourcePolicy,
        forceRefresh: Bool,
        calendar: Calendar
    ) async -> TripPreviewOnline? {
        result
    }
}

struct TripPreviewServiceTests {
    // 2026-10-12 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_806_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func trip(_ code: String = "MA", from start: Date, to end: Date) -> PlannedTrip {
        PlannedTrip(countryCode: code, startDate: start, endDate: end)
    }

    private func holiday(_ name: String, _ date: Date) -> HolidayPeriodSnapshot {
        HolidayPeriodSnapshot(name: name, startDate: date, endDate: date)
    }

    private func makeService(
        holidays: StubHolidayProvider = StubHolidayProvider(),
        advisories: StubAdvisoryProvider = StubAdvisoryProvider(),
        clock: TestClock = TestClock(Date(timeIntervalSince1970: 1_791_806_400))
    ) -> LiveTripPreviewService {
        LiveTripPreviewService(holidayProvider: holidays, advisoryProvider: advisories, nowProvider: { clock.now })
    }

    private var normal: DashboardResourcePolicy {
        .normal
    }

    private var offline: DashboardResourcePolicy {
        DashboardResourcePolicy(mode: .automatic, conditions: ResourceConditions(pathAvailable: false))
    }

    private var lowData: DashboardResourcePolicy {
        DashboardResourcePolicy(mode: .lowData, conditions: ResourceConditions())
    }

    // MARK: - Content

    @Test
    func keepsOnlyTheHolidaysOnDaysOfTheTripInOrderAndFetchesAdvisoryForTheDestinationAlone() async throws {
        let holidays = StubHolidayProvider(years: [
            2026: [
                holiday("Revolution Day", day(2026, 11, 6)),
                holiday("Independence Day", day(2026, 11, 18)),
                holiday("Before", day(2026, 10, 30)),
                holiday("After", day(2026, 11, 20))
            ]
        ])
        let advisories = StubAdvisoryProvider()
        let service = makeService(holidays: holidays, advisories: advisories)
        let trip = trip(from: day(2026, 11, 1), to: day(2026, 11, 18))

        let online = try #require(await service.online(
            for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        ))

        #expect(online.holidays?.map(\.name) == ["Revolution Day", "Independence Day"])
        #expect(online.advisory?.severity == .caution)
        #expect(online.fetchedAt == now)
        #expect(await holidays.requests == [HolidayRequest(country: "MA", year: 2026, zone: "Europe/Helsinki")])
        #expect(await advisories.requests == [AdvisoryRequest(countries: ["MA"], primary: "MA")])
    }

    @Test
    func aTripOverTheNewYearAsksForBothYears() async throws {
        let holidays = StubHolidayProvider(years: [
            2026: [holiday("Christmas", day(2026, 12, 25))],
            2027: [holiday("New Year", day(2027, 1, 1)), holiday("Epiphany", day(2027, 1, 6))]
        ])
        let service = makeService(holidays: holidays)

        let online = try #require(await service.online(
            for: trip("PT", from: day(2026, 12, 20), to: day(2027, 1, 3)),
            settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        ))

        #expect(online.holidays?.map(\.name) == ["Christmas", "New Year"])
        #expect(Set(await holidays.requests.map(\.year)) == [2026, 2027])
        #expect(Set(await holidays.requests.map(\.country)) == ["PT"])
    }

    @Test
    func aTripWithoutHolidaysHasAnEmptyListNotAMissingOne() async throws {
        let service = makeService(holidays: StubHolidayProvider(years: [2026: []]))

        let online = try #require(await service.online(
            for: trip(from: day(2026, 11, 1), to: day(2026, 11, 5)),
            settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        ))

        #expect(online.holidays == [])
    }

    @Test
    func theAdvisoryIsLeftOutWhenTheUserTurnedAdvisoriesOff() async throws {
        let advisories = StubAdvisoryProvider()
        let service = makeService(holidays: StubHolidayProvider(years: [2026: []]), advisories: advisories)

        let online = try #require(await service.online(
            for: trip(from: day(2026, 11, 1), to: day(2026, 11, 5)),
            settings: AppSettings(travelAdvisoryEnabled: false), policy: normal, forceRefresh: false, calendar: calendar
        ))

        #expect(online.advisory == nil)
        #expect(await advisories.requests.isEmpty)
    }

    @Test
    func anInvalidDestinationAsksForNothing() async {
        let holidays = StubHolidayProvider()
        let service = makeService(holidays: holidays)

        let online = await service.online(
            for: trip("Morocco", from: day(2026, 11, 1), to: day(2026, 11, 5)),
            settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        )

        #expect(online == nil)
        #expect(await holidays.requests.isEmpty)
    }

    // MARK: - Failures

    @Test
    func aFailingPartIsUnavailableWhileTheOtherStillArrives() async throws {
        let service = makeService(
            holidays: StubHolidayProvider(failure: ProviderError.missingCountryCode),
            advisories: StubAdvisoryProvider()
        )

        let online = try #require(await service.online(
            for: trip(from: day(2026, 11, 1), to: day(2026, 11, 5)),
            settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        ))

        #expect(online.holidays == nil)
        #expect(online.advisory != nil)
    }

    @Test
    func nothingAtAllIsNil() async {
        let service = makeService(
            holidays: StubHolidayProvider(failure: ProviderError.invalidResponse),
            advisories: StubAdvisoryProvider(failure: ProviderError.invalidResponse)
        )

        let online = await service.online(
            for: trip(from: day(2026, 11, 1), to: day(2026, 11, 5)),
            settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        )

        #expect(online == nil)
    }

    @Test
    func aSavedAnswerCoversAFailedRefresh() async throws {
        let holidays = StubHolidayProvider(years: [2026: [holiday("Revolution Day", day(2026, 11, 6))]])
        let advisories = StubAdvisoryProvider()
        let clock = TestClock(now)
        let service = makeService(holidays: holidays, advisories: advisories, clock: clock)
        let trip = trip(from: day(2026, 11, 1), to: day(2026, 11, 8))
        _ = await service.online(for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar)

        await holidays.fail(with: ProviderError.invalidResponse)
        await advisories.fail(with: ProviderError.invalidResponse)
        let later = now.addingTimeInterval(2 * 86_400)
        clock.now = later
        let online = try #require(await service.online(
            for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar
        ))

        #expect(online.holidays?.map(\.name) == ["Revolution Day"])
        #expect(online.advisory != nil)
        #expect(online.fetchedAt == now)
    }

    // MARK: - Caching

    @Test
    func aFreshSavedAnswerIsNotRequestedAgainUnlessRefreshed() async {
        let holidays = StubHolidayProvider(years: [2026: []])
        let advisories = StubAdvisoryProvider()
        let clock = TestClock(now)
        let service = makeService(holidays: holidays, advisories: advisories, clock: clock)
        let trip = trip(from: day(2026, 11, 1), to: day(2026, 11, 8))

        _ = await service.online(for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar)
        clock.now = now.addingTimeInterval(3_600)
        _ = await service.online(for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar)
        #expect(await holidays.requests.count == 1)
        #expect(await advisories.requests.count == 1)

        _ = await service.online(for: trip, settings: AppSettings(), policy: normal, forceRefresh: true, calendar: calendar)
        #expect(await holidays.requests.count == 2)
        #expect(await advisories.requests.count == 2)

        clock.now = now.addingTimeInterval(13 * 3_600)
        _ = await service.online(for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar)
        #expect(await holidays.requests.count == 3)
        #expect(await advisories.requests.count == 3)
    }

    // MARK: - Resource policy

    @Test
    func offlineAndLowDataNeverRequestAndFallBackToWhatIsSaved() async throws {
        for policy in [offline, lowData] {
            let holidays = StubHolidayProvider(years: [2026: [holiday("Revolution Day", day(2026, 11, 6))]])
            let advisories = StubAdvisoryProvider()
            let service = makeService(holidays: holidays, advisories: advisories)
            let trip = trip(from: day(2026, 11, 1), to: day(2026, 11, 8))

            let nothingSaved = await service.online(
                for: trip, settings: AppSettings(), policy: policy, forceRefresh: true, calendar: calendar
            )
            #expect(nothingSaved == nil)
            #expect(await holidays.requests.isEmpty)
            #expect(await advisories.requests.isEmpty)

            _ = await service.online(for: trip, settings: AppSettings(), policy: normal, forceRefresh: false, calendar: calendar)
            let requestsWhenOnline = await holidays.requests.count + advisories.requests.count
            let saved = try #require(await service.online(
                for: trip, settings: AppSettings(), policy: policy, forceRefresh: true, calendar: calendar
            ))

            #expect(saved.holidays?.map(\.name) == ["Revolution Day"])
            #expect(saved.advisory != nil)
            #expect(await holidays.requests.count + advisories.requests.count == requestsWhenOnline)
        }
    }

    @Test
    func reducedBackgroundWorkLimitsTheRequestsInFlightToOne() async throws {
        let policy = DashboardResourcePolicy(
            mode: .standard,
            conditions: ResourceConditions(isLowPowerModeEnabled: true)
        )
        #expect(policy.reducesBackgroundWork)
        #expect(policy.isLowData == false)
        let flights = FlightGroup()
        let holidays = StubHolidayProvider(years: [2026: [], 2027: []], delay: .milliseconds(30), flights: flights)
        let advisories = StubAdvisoryProvider(delay: .milliseconds(30), flights: flights)
        let service = makeService(holidays: holidays, advisories: advisories)

        let online = await service.online(
            for: trip(from: day(2026, 12, 28), to: day(2027, 1, 3)),
            settings: AppSettings(), policy: policy, forceRefresh: false, calendar: calendar
        )

        #expect(online?.holidays == [])
        #expect(online?.advisory != nil)
        #expect(flights.peak == 1)
    }
}

@Suite(.serialized)
struct TripHolidaySourceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test
    func theLocalInfoProviderServesPublicHolidaysForTheTripWithoutSubdivisionsOrLocation() async throws {
        let requests = RequestLog()
        let session = makeTripMockSession { request in
            await requests.record(request)
            let path = try #require(request.url?.path)
            guard path == "/api/v3/publicholidays/2026/MA" else {
                return (404, "[]")
            }
            return (200, """
            [{"date":"2026-11-06","localName":"Green March","name":"Green March Day","counties":null},
             {"date":"2026-11-18","localName":"Independence Day","name":"Independence Day","counties":["MA-01"]}]
            """)
        }
        let info = LiveLocalInfoProvider(session: session, localPriceLevelProvider: UnusedPriceProvider())
        let service = LiveTripPreviewService(holidayProvider: info, advisoryProvider: StubAdvisoryProvider())

        let online = try #require(await service.online(
            for: PlannedTrip(countryCode: "MA", startDate: day(2026, 11, 1), endDate: day(2026, 11, 30)),
            settings: AppSettings(), policy: .normal, forceRefresh: false, calendar: calendar
        ))

        // Only the nationwide holiday: a destination without a region has no county to match.
        #expect(online.holidays?.map(\.name) == ["Green March"])
        let urls = await requests.urls
        #expect(urls == ["https://date.nager.at/api/v3/publicholidays/2026/MA"])
    }

    @Test
    func anUnsupportedCountryIsUnavailableNotEmpty() async throws {
        let session = makeTripMockSession { _ in (404, "[]") }
        let info = LiveLocalInfoProvider(session: session, localPriceLevelProvider: UnusedPriceProvider())

        await #expect(throws: ProviderError.self) {
            try await info.publicHolidays(inCountry: "ZZ", year: 2026, timeZone: .gmt, forceRefresh: true)
        }
    }
}

// MARK: - Test doubles

private struct HolidayRequest: Equatable {
    let country: String
    let year: Int
    let zone: String
}

private struct AdvisoryRequest: Equatable {
    let countries: [String]
    let primary: String
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// Counts how many calls are in flight at once.
private final class FlightGroup: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var highest = 0

    var peak: Int {
        lock.withLock { highest }
    }

    func enter() {
        lock.withLock {
            current += 1
            highest = max(highest, current)
        }
    }

    func leave() {
        lock.withLock { current -= 1 }
    }
}

private actor StubHolidayProvider: PublicHolidayProvider {
    private let years: [Int: [HolidayPeriodSnapshot]]
    private var failure: (any Error)?
    private let delay: Duration?
    private(set) var requests: [HolidayRequest] = []
    nonisolated let flights: FlightGroup

    init(
        years: [Int: [HolidayPeriodSnapshot]] = [:],
        failure: (any Error)? = nil,
        delay: Duration? = nil,
        flights: FlightGroup = FlightGroup()
    ) {
        self.years = years
        self.failure = failure
        self.delay = delay
        self.flights = flights
    }

    func fail(with error: any Error) {
        failure = error
    }

    func publicHolidays(
        inCountry countryCode: String,
        year: Int,
        timeZone: TimeZone,
        forceRefresh: Bool
    ) async throws -> [HolidayPeriodSnapshot] {
        flights.enter()
        defer { flights.leave() }
        requests.append(HolidayRequest(country: countryCode, year: year, zone: timeZone.identifier))
        if let delay {
            try await Task.sleep(for: delay)
        }
        if let failure {
            throw failure
        }
        return years[year] ?? []
    }
}

private actor StubAdvisoryProvider: TravelAdvisoryProvider {
    nonisolated let sourceDescriptor = TravelAlertSourceDescriptor(name: "Smartraveller", url: nil)
    private var failure: (any Error)?
    private let delay: Duration?
    private(set) var requests: [AdvisoryRequest] = []
    nonisolated let flights: FlightGroup

    init(failure: (any Error)? = nil, delay: Duration? = nil, flights: FlightGroup = FlightGroup()) {
        self.failure = failure
        self.delay = delay
        self.flights = flights
    }

    func fail(with error: any Error) {
        failure = error
    }

    func advisory(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        flights.enter()
        defer { flights.leave() }
        requests.append(AdvisoryRequest(countries: countryCodes, primary: primaryCountryCode))
        if let delay {
            try await Task.sleep(for: delay)
        }
        if let failure {
            throw failure
        }
        return TravelAlertSignalSnapshot(
            kind: .advisory,
            severity: .caution,
            title: "Travel advisory",
            summary: "Exercise a high degree of caution.",
            sourceName: "Smartraveller",
            sourceURL: nil,
            updatedAt: Date(timeIntervalSince1970: 1_791_806_400),
            affectedCountryCodes: countryCodes
        )
    }
}

private struct UnusedPriceProvider: LocalPriceLevelProvider {
    func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot {
        throw ProviderError.invalidResponse
    }
}

private actor RequestLog {
    private(set) var urls: [String] = []

    func record(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
    }
}

private func makeTripMockSession(
    handler: @escaping @Sendable (URLRequest) async throws -> (Int, String)
) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TripMockURLProtocol.self]
    TripMockURLProtocol.handler = handler
    return URLSession(configuration: configuration)
}

private final class TripMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Task { @Sendable [self, request = request] in
            do {
                let (statusCode, body) = try await handler(request)
                let response = try HTTPURLResponse(
                    url: #require(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}
