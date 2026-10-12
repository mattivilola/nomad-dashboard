import Foundation
import Testing
@testable import NomadCore

/// Reference: today is Mon 2026-10-12 (Paris). Schengen limit: more than 90 days in any 180-day window.
struct StayProjectionTests {
    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 14:00 Paris

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
    }

    private func trip(_ code: String, _ from: (Int, Int, Int), _ to: (Int, Int, Int)) -> PlannedTrip {
        PlannedTrip(
            countryCode: code,
            startDate: day(from.0, from.1, from.2),
            endDate: day(to.0, to.1, to.2)
        )
    }

    /// One record per day from `from` through `to`.
    private func recorded(_ code: String, _ from: (Int, Int, Int), _ to: (Int, Int, Int)) -> [VisitedCountryDay] {
        let start = day(from.0, from.1, from.2)
        let count = calendar.dateComponents([.day], from: start, to: day(to.0, to.1, to.2)).day! + 1
        return (0..<count).map { offset in
            VisitedCountryDay(
                day: VisitedCountryDayStamp(date: calendar.date(byAdding: .day, value: offset, to: start)!, calendar: calendar),
                country: code,
                countryCode: code,
                source: .deviceLocation,
                isInferred: false
            )
        }
    }

    private func outlook(
        _ trip: PlannedTrip,
        among trips: [PlannedTrip]? = nil,
        recorded days: [VisitedCountryDay] = [],
        live: String? = nil,
        settings: AppSettings = AppSettings(citizenshipCountryCodes: ["US"])
    ) -> TripVisaOutlook {
        StayCalculator(days: days, now: now, calendar: calendar, liveCountryCode: live)
            .outlook(for: trip, among: trips ?? [trip], settings: settings)
    }

    private func window(_ outlook: TripVisaOutlook, sourceLocation: SourceLocation = #_sourceLocation) throws -> SchengenTripWindow {
        try #require(outlook.schengen?.window, sourceLocation: sourceLocation)
    }

    // MARK: - Schengen

    @Test
    func aTripInSchengenCountsItsDaysOnTopOfNothing() throws {
        let result = try window(outlook(trip("FR", (2026, 11, 1), (2026, 11, 30))))

        #expect(result.tripSchengenDays == 30)
        #expect(result.usedDaysBeforeTrip == 0)
        #expect(result.peakUsedDays == 30)
        #expect(result.peakDay == day(2026, 11, 30))
        #expect(result.firstExceededOn == nil)
        #expect(result.remainingDaysAtPeak == 60)
        #expect(result.exceedsLimit == false)
        #expect(outlook(trip("FR", (2026, 11, 1), (2026, 11, 30))).schengen == .counting(result))
    }

    // Recorded FR 2026-07-25 ... 2026-10-12 is 80 days. A trip from 20 Oct adds one day per day: 81 on the
    // 20th, 90 on the 29th and 91 on the 30th, the first day over the limit.
    @Test
    func theFirstDayOverTheLimitIsFoundOnTopOfRecordedDays() throws {
        let history = recorded("FR", (2026, 7, 25), (2026, 10, 12))

        let within = try window(outlook(trip("ES", (2026, 10, 20), (2026, 10, 29)), recorded: history))
        #expect(within.usedDaysBeforeTrip == 80)
        #expect(within.peakUsedDays == 90)
        #expect(within.firstExceededOn == nil)

        let over = try window(outlook(trip("ES", (2026, 10, 20), (2026, 10, 30)), recorded: history))
        #expect(over.usedDaysBeforeTrip == 80)
        #expect(over.tripSchengenDays == 11)
        #expect(over.peakUsedDays == 91)
        #expect(over.peakDay == day(2026, 10, 30))
        #expect(over.firstExceededOn == day(2026, 10, 30))
        #expect(over.remainingDaysAtPeak == 0)
    }

    @Test
    func recordedDaysLeaveTheWindowDuringALongTrip() throws {
        // 90 recorded days, 1 Mar - 29 May 2026. On 4 Nov the window starts on 9 May, so only 21 of them are
        // left. Each trip day adds one and drops one: 21 on 5 Nov (10 May start: 20 + 1) and 21 on 10 Nov
        // (15 May start: 15 + 6), never more.
        let history = recorded("FR", (2026, 3, 1), (2026, 5, 29))

        let result = try window(outlook(trip("IT", (2026, 11, 5), (2026, 11, 10)), recorded: history))

        #expect(result.usedDaysBeforeTrip == 21)
        #expect(result.peakUsedDays == 21)
        #expect(result.peakDay == day(2026, 11, 5))
        #expect(result.firstExceededOn == nil)
    }

    @Test
    func plannedTripsBuildOnEachOtherInOrder() throws {
        let november = trip("FR", (2026, 11, 1), (2026, 11, 30))
        let winter = trip("IT", (2026, 12, 20), (2027, 1, 20))
        let plan = [winter, november] // in any order: they apply by start date

        let result = try window(outlook(winter, among: plan))

        // 30 days in November are in the window on 19 Dec; the winter trip is 32 days (it crosses the new year).
        #expect(result.usedDaysBeforeTrip == 30)
        #expect(result.tripSchengenDays == 32)
        #expect(result.peakUsedDays == 62)
        #expect(result.peakDay == day(2027, 1, 20))
        #expect(result.firstExceededOn == nil)

        let first = try window(outlook(november, among: plan))
        #expect(first.usedDaysBeforeTrip == 0)
        #expect(first.peakUsedDays == 30)
    }

    @Test
    func aPlanCanBreakTheLimitInTheLaterTrip() throws {
        let spring = trip("ES", (2026, 11, 1), (2027, 1, 15)) // 76 days
        let summer = trip("PT", (2027, 2, 1), (2027, 2, 20)) // 20 more: 96
        let plan = [spring, summer]

        let first = try window(outlook(spring, among: plan))
        #expect(first.peakUsedDays == 76)
        #expect(first.firstExceededOn == nil)

        let second = try window(outlook(summer, among: plan))
        #expect(second.usedDaysBeforeTrip == 76)
        // 76 + 15 = 91 on 15 Feb.
        #expect(second.firstExceededOn == day(2027, 2, 15))
        #expect(second.peakUsedDays == 96)
    }

    @Test
    func daysBetweenTripsOutsideSchengenDoNotCountButLeavingDoesNotResetTheWindow() throws {
        let first = trip("FR", (2026, 11, 1), (2026, 11, 20)) // 20
        let morocco = trip("MA", (2026, 11, 21), (2026, 12, 10))
        let second = trip("DE", (2026, 12, 11), (2026, 12, 20)) // 10 more
        let plan = [first, morocco, second]

        let result = try window(outlook(second, among: plan))

        #expect(result.usedDaysBeforeTrip == 20)
        #expect(result.peakUsedDays == 30)
        #expect(outlook(morocco, among: plan).schengen == nil)
    }

    @Test
    func overlappingTripsCountTheOverlapOnceInTheLaterTripsCountry() throws {
        // Spain 1-10 Nov and France 6-15 Nov overlap on 6-10 Nov: 15 Schengen days, not 20.
        let spain = trip("ES", (2026, 11, 1), (2026, 11, 10))
        let france = trip("FR", (2026, 11, 6), (2026, 11, 15))

        let second = try window(outlook(france, among: [spain, france]))
        #expect(second.usedDaysBeforeTrip == 5)
        #expect(second.tripSchengenDays == 10)
        #expect(second.peakUsedDays == 15)

        // The same Schengen days when the later trip leaves Schengen: Spain keeps 1-5 Nov only.
        let morocco = trip("MA", (2026, 11, 6), (2026, 11, 15))
        let shortened = try window(outlook(spain, among: [spain, morocco]))
        #expect(shortened.tripSchengenDays == 5)
        #expect(shortened.peakUsedDays == 5)
        #expect(outlook(morocco, among: [spain, morocco]).schengen == nil)
    }

    @Test
    func tripsWithTheSameStartApplyTheLongerOneLast() throws {
        let short = trip("MA", (2026, 11, 1), (2026, 11, 5))
        let long = trip("ES", (2026, 11, 1), (2026, 11, 10))

        // The longer trip is applied later, so it owns the shared days, whatever order they are listed in.
        #expect(try window(outlook(long, among: [short, long])).tripSchengenDays == 10)
        #expect(try window(outlook(long, among: [long, short])).tripSchengenDays == 10)
        // Every day of the shorter trip is Spain's, so Morocco adds nothing and the days it spans are Schengen days.
        #expect(try window(outlook(short, among: [long, short])).tripSchengenDays == 5)
    }

    @Test
    func plannedDaysBeforeTodayAreIgnoredAndTodayIsNotCountedTwice() throws {
        // Recorded FR on 10-12 Oct, planned FR 10-14 Oct: 3 recorded plus 2 planned days, today only once.
        let history = recorded("FR", (2026, 10, 10), (2026, 10, 12))
        let ongoing = try window(outlook(trip("FR", (2026, 10, 10), (2026, 10, 14)), recorded: history))
        #expect(ongoing.tripSchengenDays == 5)
        #expect(ongoing.peakUsedDays == 5)

        // A trip entirely in the past that was never recorded does not make up days.
        #expect(outlook(trip("FR", (2026, 10, 1), (2026, 10, 5))).schengen == nil)
    }

    @Test
    func theDayATripStartsCountsForTheCountryTheTravellerIsStillIn() throws {
        // Today the Mac is still in Morocco, and the trip to Spain starts today: both count, like a border day.
        let history = recorded("MA", (2026, 10, 1), (2026, 10, 12))
        let result = try window(outlook(trip("ES", (2026, 10, 12), (2026, 10, 14)), recorded: history))

        #expect(result.tripSchengenDays == 3)
        #expect(result.peakUsedDays == 3)
    }

    @Test
    func theLiveCountryCoversATodayThatIsNotRecorded() throws {
        let result = try window(outlook(trip("FR", (2026, 10, 12), (2026, 10, 12)), live: "FR"))

        #expect(result.tripSchengenDays == 1)
    }

    @Test
    func aTripOutsideSchengenHasNoProjection() {
        #expect(outlook(trip("MA", (2026, 11, 1), (2026, 11, 30))).schengen == nil)
        #expect(outlook(trip("GB", (2026, 11, 1), (2026, 11, 30))).schengen == nil)
        // Ireland and Cyprus are in the EU but not in Schengen.
        #expect(outlook(trip("IE", (2026, 11, 1), (2026, 11, 30))).schengen == nil)
    }

    @Test
    func citizensWithFreeMovementAreExempt() {
        let finn = AppSettings(citizenshipCountryCodes: ["FI"])
        let dualCitizen = AppSettings(citizenshipCountryCodes: ["US", "DE"])

        #expect(outlook(trip("FR", (2026, 11, 1), (2027, 3, 30)), settings: finn).schengen == .exempt)
        #expect(outlook(trip("FR", (2026, 11, 1), (2027, 3, 30)), settings: dualCitizen).schengen == .exempt)
        // Nothing to say about a trip that never touches Schengen, exempt or not.
        #expect(outlook(trip("MA", (2026, 11, 1), (2026, 11, 30)), settings: finn).schengen == nil)
        #expect(SchengenProjection.exempt.window == nil)
    }

    @Test
    func withoutACitizenshipTheCountsAreGivenAsUnknown() throws {
        let result = outlook(trip("FR", (2026, 11, 1), (2026, 11, 30)), settings: AppSettings())

        guard case let .unknownCitizenship(window) = try #require(result.schengen) else {
            Issue.record("Expected an unknown citizenship projection")
            return
        }
        #expect(window.peakUsedDays == 30)
    }

    @Test
    func theSchengenCounterSwitchTurnsTheProjectionOff() {
        let off = AppSettings(citizenshipCountryCodes: ["US"], schengenCounterEnabled: false)

        #expect(outlook(trip("FR", (2026, 11, 1), (2026, 11, 30)), settings: off).schengen == nil)
    }

    @Test
    func aTripThatIsNotListedInThePlanIsStillPartOfIt() throws {
        let unlisted = trip("FR", (2026, 11, 1), (2026, 11, 30))

        #expect(try window(outlook(unlisted, among: [])).peakUsedDays == 30)
    }

    // MARK: - Allowance

    @Test
    func aTripWithinTheAllowanceHasDaysLeft() throws {
        let settings = AppSettings(stayAllowances: ["TH": 30])
        let allowance = try #require(outlook(trip("TH", (2026, 11, 1), (2026, 11, 22)), settings: settings).allowance)

        #expect(allowance.countryCode == "TH")
        #expect(allowance.allowanceDays == 30)
        #expect(allowance.tripDays == 22)
        #expect(allowance.remainingDays == 8)
        #expect(allowance.overstayDays == 0)
        #expect(allowance.lastPermittedDay == day(2026, 11, 30))
    }

    @Test
    func aTripOverTheAllowanceOverstaysAndNamesTheLastPermittedDay() throws {
        let settings = AppSettings(stayAllowances: ["TH": 30])
        let allowance = try #require(outlook(trip("TH", (2026, 11, 1), (2026, 12, 10)), settings: settings).allowance)

        #expect(allowance.tripDays == 40)
        #expect(allowance.remainingDays == 0)
        #expect(allowance.overstayDays == 10)
        #expect(allowance.lastPermittedDay == day(2026, 11, 30))
    }

    @Test
    func aTripExactlyAsLongAsTheAllowanceHasNothingLeft() throws {
        let settings = AppSettings(stayAllowances: ["TH": 30])
        let allowance = try #require(outlook(trip("TH", (2026, 11, 1), (2026, 11, 30)), settings: settings).allowance)

        #expect(allowance.remainingDays == 0)
        #expect(allowance.overstayDays == 0)
    }

    @Test
    func theAllowanceIsPerDestinationAndOptional() {
        #expect(outlook(trip("TH", (2026, 11, 1), (2026, 11, 22))).allowance == nil)
        #expect(outlook(trip("TH", (2026, 11, 1), (2026, 11, 22)), settings: AppSettings(stayAllowances: ["VN": 45])).allowance == nil)
    }

    // MARK: - Tax year

    @Test
    func aTripOverTheNewYearReportsEachYearOnItsOwn() throws {
        // Recorded TH 1 Sep - 12 Oct 2026 is 42 days; the trip adds 20-31 Dec (12 days) and 1-10 Jan (10 days).
        let history = recorded("TH", (2026, 9, 1), (2026, 10, 12))
        let settings = AppSettings(taxResidenceThresholdDays: 50)
        let result = outlook(trip("TH", (2026, 12, 20), (2027, 1, 10)), recorded: history, settings: settings)

        let years = result.taxYears
        #expect(years.map(\.year) == [2026, 2027])
        #expect(years[0].recordedDays == 42)
        #expect(years[0].plannedDays == 12)
        #expect(years[0].totalDays == 54)
        #expect(years[0].reachesThreshold)
        // Day 43 is 20 Dec, so the 50th day is 27 Dec.
        #expect(years[0].thresholdReachedOn == day(2026, 12, 27))
        #expect(years[1].recordedDays == 0)
        #expect(years[1].plannedDays == 10)
        #expect(years[1].reachesThreshold == false)
        #expect(years[1].thresholdReachedOn == nil)
        #expect(years[1].thresholdDays == 50)
    }

    @Test
    func thePlannedDaysOfTheDestinationCountOnTopOfTheRecordedOnesOnlyOnce() throws {
        // Recorded TH 10-12 Oct, trip TH 10-14 Oct: today is both recorded and planned.
        let history = recorded("TH", (2026, 10, 10), (2026, 10, 12))
        let year = try #require(outlook(trip("TH", (2026, 10, 10), (2026, 10, 14)), recorded: history).taxYears.first)

        #expect(year.recordedDays == 3)
        #expect(year.plannedDays == 2)
    }

    @Test
    func onlyDaysInTheDestinationCount() throws {
        let history = recorded("VN", (2026, 1, 1), (2026, 10, 12))
        let year = try #require(outlook(trip("TH", (2026, 11, 1), (2026, 11, 10)), recorded: history).taxYears.first)

        #expect(year.recordedDays == 0)
        #expect(year.plannedDays == 10)
    }

    @Test
    func overlappingTripsGiveTheSharedDaysToTheLaterTripsCountry() throws {
        let thailand = trip("TH", (2026, 11, 1), (2026, 11, 10))
        let vietnam = trip("VN", (2026, 11, 6), (2026, 11, 20))

        #expect(try #require(outlook(thailand, among: [thailand, vietnam]).taxYears.first).plannedDays == 5)
        #expect(try #require(outlook(vietnam, among: [thailand, vietnam]).taxYears.first).plannedDays == 15)
    }

    @Test
    func theThresholdCanBeReachedOnTheFirstPlannedDay() throws {
        let history = recorded("TH", (2026, 4, 15), (2026, 10, 12)) // 181 days
        let settings = AppSettings()
        let year = try #require(outlook(trip("TH", (2026, 10, 13), (2026, 10, 20)), recorded: history, settings: settings).taxYears.first)

        #expect(year.recordedDays == 181)
        #expect(year.thresholdDays == 183)
        // 182 on 13 Oct, 183 on 14 Oct.
        #expect(year.thresholdReachedOn == day(2026, 10, 14))
    }

    @Test
    func theTaxResidenceSwitchTurnsTheYearsOff() {
        let off = AppSettings(taxResidenceDaysEnabled: false)

        #expect(outlook(trip("TH", (2026, 11, 1), (2026, 11, 10)), settings: off).taxYears.isEmpty)
    }

    // MARK: - Whole outlook

    @Test
    func anOutlookIsEmptyWhenNothingApplies() {
        let settings = AppSettings(schengenCounterEnabled: false, taxResidenceDaysEnabled: false)

        #expect(outlook(trip("MA", (2026, 11, 1), (2026, 11, 10)), settings: settings).isEmpty)
        #expect(outlook(trip("MA", (2026, 11, 1), (2026, 11, 10))).isEmpty == false)
    }
}
