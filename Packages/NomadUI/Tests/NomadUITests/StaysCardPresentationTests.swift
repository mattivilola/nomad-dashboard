import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct StaysCardPresentationTests {
    private typealias Support = StaysTestSupport

    private func card(
        days: [VisitedCountryDay],
        current: String? = "MA",
        settings: AppSettings = AppSettings()
    ) -> StaysCardPresentation {
        StaysCardPresentation(
            settings: settings,
            countryDays: days,
            currentCountryCode: current,
            now: Support.now,
            calendar: Support.calendar,
            locale: Support.locale
        )
    }

    // MARK: Current stay

    @Test
    func currentStayNamesTheCountryDayAndStartDate() throws {
        let stay = try #require(card(days: Support.run(23, "MA")).currentStay)

        #expect(stay.title == "Morocco · day 23")
        #expect(stay.since == "since 20 Sep")
        #expect(stay.gapNote == nil)
    }

    @Test
    func aBridgedGapIsMentioned() throws {
        let days = Support.run(10, "MA").filter { $0.day != Support.stamp(daysBeforeToday: 4) }
        let stay = try #require(card(days: days).currentStay)

        #expect(stay.title == "Morocco · day 10")
        #expect(stay.gapNote == "Includes 1 day without a record, counted as spent here")
    }

    @Test
    func theLiveCountryCountsTodayBeforeItIsRecorded() throws {
        let stay = try #require(card(days: Support.run(5, "MA", endingOffset: 1)).currentStay)
        #expect(stay.title == "Morocco · day 6")
    }

    @Test
    func withoutACurrentCountryThereIsNoStay() {
        let presentation = card(days: Support.run(5, "MA"), current: nil)

        #expect(presentation.currentStay == nil)
        #expect(presentation.allowance == nil)
    }

    // MARK: Allowance

    @Test
    func anAllowanceShowsUsageAndTheLastPermittedDay() throws {
        let presentation = card(days: Support.run(67, "MA"), settings: AppSettings(stayAllowances: ["MA": 90]))
        let allowance = try #require(presentation.allowance)

        #expect(allowance.title == "Morocco allowance")
        #expect(allowance.text == "67 of 90 days · leave by 4 Nov")
        #expect(abs(allowance.progress - 67.0 / 90.0) < 0.0001)
        #expect(allowance.tone == .neutral)
        #expect(presentation.badge.title == "Tracking")
    }

    @Test
    func anAllowanceTurnsSandAtFourteenDaysLeftAndCoralAtThree() throws {
        func allowance(usedDays: Int) throws -> StaysCardPresentation.Allowance {
            try #require(card(days: Support.run(usedDays, "MA"), settings: AppSettings(stayAllowances: ["MA": 90])).allowance)
        }

        #expect(try allowance(usedDays: 75).tone == .neutral)
        #expect(try allowance(usedDays: 76).tone == .caution)
        #expect(try allowance(usedDays: 86).tone == .caution)
        #expect(try allowance(usedDays: 87).tone == .attention)
    }

    @Test
    func theLastDayAndAnOverstayAreWorded() throws {
        let settings = AppSettings(stayAllowances: ["MA": 90])
        let lastDay = try #require(card(days: Support.run(90, "MA"), settings: settings).allowance)
        let over = card(days: Support.run(93, "MA"), settings: settings)

        #expect(lastDay.text == "90 of 90 days · last day today")
        #expect(lastDay.tone == .attention)
        #expect(over.allowance?.text == "93 of 90 days · 3 days over · ended 9 Oct")
        #expect(over.allowance?.tone == .attention)
        #expect(over.badge.title == "Over Limit")
        #expect(over.badge.tint == NomadTheme.coral)
    }

    @Test
    func aSandAllowanceMakesTheBadgeSand() {
        let presentation = card(days: Support.run(80, "MA"), settings: AppSettings(stayAllowances: ["MA": 90]))

        #expect(presentation.badge.title == "Limit Near")
        #expect(presentation.badge.tint == NomadTheme.sand)
    }

    @Test
    func anAllowanceForAnotherCountryDoesNotApply() {
        let presentation = card(days: Support.run(80, "MA"), settings: AppSettings(stayAllowances: ["ES": 90]))
        #expect(presentation.allowance == nil)
    }

    // MARK: Schengen

    @Test
    func anEuCitizenIsToldThereIsNoLimit() throws {
        let presentation = card(
            days: Support.run(100, "ES"),
            current: "ES",
            settings: AppSettings(citizenshipCountryCodes: ["FI"])
        )
        let schengen = try #require(presentation.schengen)

        #expect(schengen.kind == .exempt)
        #expect(schengen.line == "Schengen: no limit for EU/EEA/Swiss citizens")
        #expect(schengen.progress == nil)
        #expect(schengen.tone == .neutral)
        #expect(presentation.badge.title == "Tracking")
    }

    @Test
    func withoutACitizenshipTheCountsComeWithAHint() throws {
        let schengen = try #require(card(days: Support.run(61, "ES"), current: "ES").schengen)

        #expect(schengen.kind == .citizenshipUnknown)
        #expect(schengen.line == "61 of 90 days used (rolling 180 days)")
        #expect(schengen.hint == "Set your citizenship to check if this applies")
        #expect(schengen.tone == .neutral)
    }

    @Test
    func aNonEuCitizenSeesTheBarAndTheLeaveByDate() throws {
        let presentation = card(
            days: Support.run(61, "ES"),
            current: "ES",
            settings: AppSettings(citizenshipCountryCodes: ["US"])
        )
        let schengen = try #require(presentation.schengen)

        #expect(schengen.kind == .counting)
        #expect(schengen.usage == "61 of 90 days used (rolling 180 days)")
        #expect(schengen.deadline?.hasPrefix("leave by ") == true)
        #expect(abs((schengen.progress ?? 0) - 61.0 / 90.0) < 0.0001)
        #expect(schengen.hint == nil)
        #expect(schengen.tone == .neutral)
    }

    @Test
    func schengenGetsUrgentOnlyWhileInSchengen() {
        let settings = AppSettings(citizenshipCountryCodes: ["US"])
        let inside = card(days: Support.run(80, "ES"), current: "ES", settings: settings)
        let outside = card(days: Support.run(80, "ES", endingOffset: 1), current: "MA", settings: settings)

        #expect(inside.schengen?.tone == .caution)
        #expect(inside.badge.title == "Limit Near")
        #expect(outside.schengen?.tone == .neutral)
        #expect(outside.schengen?.deadline == nil)
    }

    @Test
    func schengenIsHiddenWhenTheCounterIsOff() {
        let presentation = card(
            days: Support.run(61, "ES"),
            current: "ES",
            settings: AppSettings(schengenCounterEnabled: false)
        )

        #expect(presentation.schengen == nil)
    }

    // MARK: Tax year

    @Test
    func thisYearsTopFiveCountriesAreListedAgainstTheThreshold() throws {
        // 2026-10-12 is day 285. Spain 97 days, then Portugal 40, Morocco 30, France 20, Italy 10 and Greece 5.
        var days = Support.run(97, "ES")
        days += Support.run(40, "PT", endingOffset: 97)
        days += Support.run(30, "MA", endingOffset: 137)
        days += Support.run(20, "FR", endingOffset: 167)
        days += Support.run(10, "IT", endingOffset: 187)
        days += Support.run(5, "GR", endingOffset: 197)
        let tax = try #require(card(days: days, current: "ES").taxYear)

        #expect(tax.heading == "Days in 2026")
        #expect(tax.thresholdText == "Threshold 183 days")
        #expect(tax.countries.map(\.name) == ["Spain", "Portugal", "Morocco", "France", "Italy"])
        #expect(tax.countries.first?.daysText == "97 days")
        #expect(abs((tax.countries.first?.progress ?? 0) - 97.0 / 183.0) < 0.0001)
        #expect(tax.unrecordedText == "Unrecorded days this year: 83")
        #expect(tax.emptyText == nil)
    }

    @Test
    func aCountryNearTheThresholdTurnsSandButNeverCoral() throws {
        let tax = try #require(card(days: Support.run(176, "ES"), current: "ES").taxYear)
        let below = try #require(card(days: Support.run(175, "ES"), current: "ES").taxYear)
        let over = try #require(card(days: Support.run(200, "ES"), current: "ES").taxYear)

        #expect(tax.countries.first?.tone == .caution)
        #expect(below.countries.first?.tone == .neutral)
        #expect(over.countries.first?.tone == .caution)
        #expect(over.countries.first?.progress ?? 0 > 1)
    }

    @Test
    func theThresholdFollowsTheSetting() throws {
        let tax = try #require(card(
            days: Support.run(60, "ES"),
            current: "ES",
            settings: AppSettings(taxResidenceThresholdDays: 90)
        ).taxYear)

        #expect(tax.thresholdText == "Threshold 90 days")
        #expect(abs((tax.countries.first?.progress ?? 0) - 60.0 / 90.0) < 0.0001)
    }

    @Test
    func aYearWithoutDaysSaysSo() throws {
        let tax = try #require(card(days: [], current: nil).taxYear)

        #expect(tax.countries.isEmpty)
        #expect(tax.emptyText == "No days recorded yet this year")
        #expect(tax.unrecordedText == "Unrecorded days this year: 285")
    }

    @Test
    func taxDaysAreHiddenWhenOff() {
        let presentation = card(days: Support.run(10, "ES"), settings: AppSettings(taxResidenceDaysEnabled: false))
        #expect(presentation.taxYear == nil)
    }

    @Test
    func theTaxFooterDisclaimsAdviceAndTheActionOpensReview() {
        #expect(StaysCardPresentation.taxFooter == "Based on days Nomad recorded on this Mac · not tax or legal advice")
        #expect(StaysCardPresentation.reviewDaysTitle == "Review days")
    }

    // MARK: Off, summary and badge

    @Test
    func theCardIsOffWithoutVisitedPlaces() {
        let presentation = card(days: Support.run(10, "MA"), settings: AppSettings(visitedPlacesEnabled: false))

        #expect(presentation.isEnabled == false)
        #expect(presentation.summary == "Off")
        #expect(presentation.badge.title == "Off")
        #expect(presentation.currentStay == nil)
        #expect(presentation.taxYear == nil)
    }

    @Test
    func theSummaryLeadsWithTheStayAndItsAllowance() {
        let presentation = card(days: Support.run(23, "MA"), settings: AppSettings(stayAllowances: ["MA": 90]))

        #expect(presentation.summary == "Morocco day 23 · 23/90")
        #expect(presentation.summaryHelp.contains("Morocco · day 23 (since 20 Sep)"))
        #expect(presentation.summaryHelp.contains("Morocco allowance: 23 of 90 days"))
    }

    @Test
    func theSummaryLeadsWithSchengenWhileInSchengenWhereTheLimitCounts() {
        let presentation = card(
            days: Support.run(61, "ES"),
            current: "ES",
            settings: AppSettings(citizenshipCountryCodes: ["US"])
        )

        #expect(presentation.summary == "Schengen 61/90")
        #expect(presentation.summaryHelp.contains("Spain · day 61"))
    }

    @Test
    func anAllowanceKeepsTheStayOnTheLineEvenInSchengen() {
        let presentation = card(days: Support.run(10, "ES"), current: "ES", settings: AppSettings(stayAllowances: ["ES": 30]))
        #expect(presentation.summary == "Spain day 10 · 10/30")
    }

    @Test
    func anExemptCitizenInSchengenSeesTheStay() {
        let presentation = card(days: Support.run(10, "ES"), current: "ES", settings: AppSettings(citizenshipCountryCodes: ["FI"]))
        #expect(presentation.summary == "Spain day 10")
    }

    @Test
    func theSummaryFallsBackToSchengenThenTheBusiestCountryThenCollecting() {
        let schengenOnly = card(days: Support.run(61, "ES", endingOffset: 1), current: nil)
        #expect(schengenOnly.summary == "Schengen 61/90")

        let taxOnly = card(
            days: Support.run(20, "MA", endingOffset: 1),
            current: nil,
            settings: AppSettings(schengenCounterEnabled: false)
        )
        #expect(taxOnly.summary == "Morocco 20 days")

        let nothing = card(days: [], current: nil, settings: AppSettings(schengenCounterEnabled: false))
        #expect(nothing.summary == "Collecting")
    }

    @Test
    func theSummaryOmitsSchengenOutsideSchengenWhenTheStayIsKnown() {
        let presentation = card(days: Support.run(10, "MA") + Support.run(61, "ES", endingOffset: 10))
        #expect(presentation.summary == "Morocco day 10")
    }

    @Test
    func theCollapsedSummaryComesFromThePresentation() {
        var settings = AppSettings(stayAllowances: ["MA": 90])
        settings.dashboardCollapsedCards = [.stays]
        let summary = DashboardCardSummaryPresentation(
            cardID: .stays,
            snapshot: .preview,
            settings: settings,
            travelAlertPreferences: TravelAlertPreferences(advisoryEnabled: false, weatherEnabled: false, securityEnabled: false),
            timeTracking: .disabled,
            visitedCountryDays: Support.run(23, "ES"),
            now: Support.now,
            calendar: Support.calendar
        )

        #expect(summary.text == "Schengen 23/90")
    }

    @Test
    func theStaysCardHasATitleAndSettingsTarget() {
        #expect(DashboardCardID.stays.displayTitle == "Stays & Visas")
        #expect(DashboardCardID.stays.settingsFocusTarget == .stays)
    }
}
