import Foundation
import Testing
@testable import NomadCore

struct StayInsightTests {
    // MARK: - Stay allowance

    // Reference: MA 2026-07-27 ... 2026-10-12 is 5 + 31 + 30 + 12 = 78 days of 90: 12 left, last day 24 Oct.
    @Test
    func allowanceWithTwoWeeksOrLessLeftIsACaution() throws {
        let insight = try #require(stayInsights(
            days: run(2026, 7, 27, through: (2026, 10, 12), "MA"),
            settings: AppSettings(stayAllowances: ["MA": 90]),
            current: "MA"
        ).first)

        #expect(insight.kind == .stayAllowance)
        #expect(insight.severity == .caution)
        #expect(insight.title == "Morocco: 12 days left")
        #expect(insight.detail == "Allowance 90 days · leave by 24 Oct")
        #expect(insight.menuBarText == "12 days left")
        #expect(insight.symbolName == "calendar.badge.clock")
        #expect(insight.relatedCard == .stays)
    }

    @Test
    func allowanceSeverityAndWordingFollowTheDaysLeft() throws {
        func insight(usedDays: Int) -> DashboardInsight? {
            stayInsights(
                days: trailingDays(usedDays, "MA"),
                settings: AppSettings(stayAllowances: ["MA": 90]),
                current: "MA"
            ).first
        }

        #expect(insight(usedDays: 75) == nil) // 15 left
        #expect(insight(usedDays: 76)?.severity == .caution) // 14 left
        #expect(insight(usedDays: 86)?.severity == .caution) // 4 left
        #expect(insight(usedDays: 87)?.severity == .attention) // 3 left
        #expect(try #require(insight(usedDays: 89)).title == "Morocco: 1 day left")
        #expect(try #require(insight(usedDays: 90)).title == "Morocco: last day")
        #expect(try #require(insight(usedDays: 90)).menuBarText == "Last day")
        let over = try #require(insight(usedDays: 92))
        #expect(over.severity == .attention)
        #expect(over.title == "Morocco: 2 days over")
        #expect(over.menuBarText == "2 days over")
        #expect(over.detail == "Allowance 90 days · ended 10 Oct")
    }

    @Test
    func allowanceNeedsAnAllowanceForTheCurrentCountry() {
        let days = trailingDays(80, "MA")

        #expect(stayInsights(days: days, settings: AppSettings(stayAllowances: ["ES": 90]), current: "MA").isEmpty)
        #expect(stayInsights(days: days, settings: AppSettings(), current: "MA").isEmpty)
        #expect(stayInsights(days: days, settings: AppSettings(stayAllowances: ["MA": 90]), current: nil).isEmpty)
        #expect(stayInsights(days: days, settings: AppSettings(stayAllowances: ["MA": 90]), current: "ES").isEmpty)
    }

    @Test
    func theLiveCountryCoversATodayThatIsNotRecordedYet() throws {
        let throughYesterday = trailingDays(80, "MA").filter { $0.day != stamp(2026, 10, 12) }
        let insight = try #require(stayInsights(
            days: throughYesterday,
            settings: AppSettings(stayAllowances: ["MA": 90]),
            current: "ma"
        ).first)

        #expect(insight.title == "Morocco: 10 days left")
    }

    // MARK: - Schengen

    // Reference: FR for the last 80 days up to 2026-10-12: used 80, 10 left, last day 22 Oct.
    @Test
    func schengenWithTwoWeeksOrLessLeftIsACaution() throws {
        let insight = try #require(stayInsights(
            days: trailingDays(80, "FR"),
            settings: AppSettings(citizenshipCountryCodes: ["US"]),
            current: "FR"
        ).first)

        #expect(insight.kind == .schengenLimit)
        #expect(insight.severity == .caution)
        #expect(insight.title == "Schengen: 10 of 90 days left")
        #expect(insight.detail == "Leave by 22 Oct")
        #expect(insight.menuBarText == "Schengen 10d")
        #expect(insight.symbolName == "globe.europe.africa")
        #expect(insight.relatedCard == .stays)
    }

    @Test
    func schengenSeverityFollowsTheDaysLeft() {
        func insight(usedDays: Int) -> DashboardInsight? {
            stayInsights(
                days: trailingDays(usedDays, "FR"),
                settings: AppSettings(citizenshipCountryCodes: ["US"]),
                current: "FR"
            ).first
        }

        #expect(insight(usedDays: 75) == nil) // 15 left
        #expect(insight(usedDays: 76)?.severity == .caution) // 14 left
        #expect(insight(usedDays: 87)?.severity == .attention) // 3 left
        #expect(insight(usedDays: 90)?.title == "Schengen: 0 of 90 days left")
        #expect(insight(usedDays: 93)?.detail == "Over the limit by 3 days")
        #expect(insight(usedDays: 93)?.severity == .attention)
    }

    @Test
    func schengenStaysQuietWhenItDoesNotApplyOrIsSwitchedOff() {
        let days = trailingDays(85, "FR")

        #expect(stayInsights(days: days, settings: AppSettings(citizenshipCountryCodes: ["FI"]), current: "FR").isEmpty)
        #expect(stayInsights(days: days, settings: AppSettings(citizenshipCountryCodes: ["US", "DE"]), current: "FR").isEmpty)
        // No citizenship: the card says it may not apply, the heads-up stays silent.
        #expect(stayInsights(days: days, settings: AppSettings(), current: "FR").isEmpty)
        #expect(stayInsights(
            days: days,
            settings: AppSettings(citizenshipCountryCodes: ["US"], schengenCounterEnabled: false),
            current: "FR"
        ).isEmpty)
        // Not in Schengen today: there is nothing to leave.
        let abroad = trailingDays(85, "FR").filter { $0.day != stamp(2026, 10, 12) } + [stay(2026, 10, 12, "GB")]
        #expect(stayInsights(days: abroad, settings: AppSettings(citizenshipCountryCodes: ["US"]), current: "GB").isEmpty)
    }

    // MARK: - Tax residence days

    // Reference: ES on 160 days of 2026 (159 recorded 01-01 ... 06-08, plus today from the live location).
    @Test
    func taxResidenceDaysAppearAMonthBeforeTheThreshold() throws {
        let insight = try #require(stayInsights(
            days: yearStart(count: 159, "ES"),
            settings: AppSettings(),
            current: "ES"
        ).first)

        #expect(insight.kind == .taxResidenceDays)
        #expect(insight.severity == .info)
        #expect(insight.title == "Spain: 160 days this year")
        #expect(insight.detail == "183-day tax residence threshold · not tax advice")
        #expect(insight.menuBarText == "160 days")
        #expect(insight.symbolName == "building.columns")
        #expect(insight.relatedCard == .stays)
    }

    @Test
    func taxResidenceSeverityFollowsTheThreshold() {
        func insight(days: Int, threshold: Int = 183) -> DashboardInsight? {
            stayInsights(
                days: yearStart(count: days - 1, "ES"),
                settings: AppSettings(taxResidenceThresholdDays: threshold),
                current: "ES"
            ).first
        }

        #expect(insight(days: 152) == nil)
        #expect(insight(days: 153)?.severity == .info)
        #expect(insight(days: 175)?.severity == .info)
        #expect(insight(days: 176)?.severity == .caution)
        #expect(insight(days: 190)?.severity == .caution)
        #expect(insight(days: 70, threshold: 100)?.severity == .info)
        #expect(insight(days: 69, threshold: 100) == nil)
        #expect(insight(days: 93, threshold: 100)?.severity == .caution)
        #expect(insight(days: 70, threshold: 100)?.detail == "100-day tax residence threshold · not tax advice")
    }

    @Test
    func taxResidenceIsAboutTheCurrentCountryThisYearOnly() {
        let spainLastYear = run(2025, 1, 1, through: (2025, 12, 31), "ES")
        let spainEarlier = yearStart(count: 170, "ES")
        let settings = AppSettings()

        #expect(stayInsights(days: spainLastYear, settings: settings, current: "ES").isEmpty)
        #expect(stayInsights(days: spainEarlier, settings: settings, current: "PT").isEmpty)
        #expect(stayInsights(days: spainEarlier, settings: settings, current: nil).isEmpty)
        #expect(stayInsights(days: spainEarlier, settings: AppSettings(taxResidenceDaysEnabled: false), current: "ES").isEmpty)
    }

    // MARK: - Engine integration

    @Test
    func noStayInputMeansNoStayInsights() {
        let all = DashboardInsightEngine.insights(for: .placeholder, now: now, calendar: calendar, limit: 20)

        #expect(all.isEmpty)
    }

    @Test
    func staysAreSilentWhenTheStaysCardIsOff() {
        var settings = AppSettings(stayAllowances: ["MA": 90])
        settings.visitedPlacesEnabled = false

        #expect(stayInsights(days: trailingDays(85, "MA"), settings: settings, current: "MA").isEmpty)
    }

    @Test
    func stayInsightsRankRightAfterTheDataCapForBothProfiles() {
        let nomad = DashboardInsightKind.tieBreakOrder(for: .nomad)
        let roadTrip = DashboardInsightKind.tieBreakOrder(for: .roadTrip)

        for order in [nomad, roadTrip] {
            let dataCap = order.firstIndex(of: .dataCap)
            #expect(order.firstIndex(of: .stayAllowance) == dataCap.map { $0 + 1 })
            #expect(order.firstIndex(of: .schengenLimit) == dataCap.map { $0 + 2 })
            #expect(order.firstIndex(of: .taxResidenceDays) == dataCap.map { $0 + 3 })
        }
    }

    @Test
    func attentionOutranksCautionAcrossStayAndOtherInsights() {
        // Schengen has 2 days left (attention) while the allowance has 12 (caution) and tax days are info.
        let settings = AppSettings(
            citizenshipCountryCodes: ["US"],
            stayAllowances: ["FR": 100]
        )
        let insights = stayInsights(days: trailingDays(88, "FR"), settings: settings, current: "FR")

        #expect(insights.map(\.kind) == [.schengenLimit, .stayAllowance])
        #expect(insights.map(\.severity) == [.attention, .caution])
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_791_806_400) // 2026-10-12 14:00 Paris

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func stayInsights(days: [VisitedCountryDay], settings: AppSettings, current: String?) -> [DashboardInsight] {
        DashboardInsightEngine.insights(
            for: .placeholder,
            now: now,
            calendar: calendar,
            limit: 20,
            stays: StayInsightInput(countryDays: days, settings: settings, currentCountryCode: current)
        )
    }

    private func stamp(_ year: Int, _ month: Int, _ day: Int) -> VisitedCountryDayStamp {
        VisitedCountryDayStamp(year: year, month: month, day: day)
    }

    private func stay(_ year: Int, _ month: Int, _ day: Int, _ code: String) -> VisitedCountryDay {
        VisitedCountryDay(day: stamp(year, month, day), country: code, countryCode: code, source: .deviceLocation, isInferred: false)
    }

    /// One record per day, `count` days ending today (2026-10-12).
    private func trailingDays(_ count: Int, _ code: String) -> [VisitedCountryDay] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today)!
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        return run(parts.year!, parts.month!, parts.day!, through: (2026, 10, 12), code)
    }

    /// The first `count` days of 2026.
    private func yearStart(count: Int, _ code: String) -> [VisitedCountryDay] {
        let start = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
        let end = calendar.date(byAdding: .day, value: count - 1, to: start)!
        let parts = calendar.dateComponents([.year, .month, .day], from: end)
        return run(2026, 1, 1, through: (parts.year!, parts.month!, parts.day!), code)
    }

    private func run(_ year: Int, _ month: Int, _ day: Int, through end: (Int, Int, Int), _ code: String) -> [VisitedCountryDay] {
        let start = calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
        let last = calendar.startOfDay(for: calendar.date(from: DateComponents(year: end.0, month: end.1, day: end.2, hour: 12))!)
        let count = calendar.dateComponents([.day], from: start, to: last).day! + 1
        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return VisitedCountryDay(
                day: VisitedCountryDayStamp(date: date, calendar: calendar),
                country: code,
                countryCode: code,
                source: .deviceLocation,
                isInferred: false
            )
        }
    }
}
