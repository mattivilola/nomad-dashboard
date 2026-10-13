import Foundation
import NomadCore
import Testing
@testable import NomadUI

struct TripPlannerPresentationTests {
    private typealias Support = StaysTestSupport
    private let calendar = Support.calendar
    private let locale = Support.locale
    private let now = Support.now

    // MARK: Timing

    @Test
    func timingReadsInDaysTomorrowTodayNowAndEnded() {
        #expect(TripTiming.text(daysUntilStart: 12, daysSinceEnd: -20) == "in 12 days")
        #expect(TripTiming.text(daysUntilStart: 1, daysSinceEnd: -20) == "tomorrow")
        #expect(TripTiming.text(daysUntilStart: 0, daysSinceEnd: -4) == "today")
        #expect(TripTiming.text(daysUntilStart: -3, daysSinceEnd: -1) == "now")
        #expect(TripTiming.text(daysUntilStart: -3, daysSinceEnd: 0) == "now")
        #expect(TripTiming.text(daysUntilStart: -10, daysSinceEnd: 2) == "ended")
    }

    // MARK: Dates

    /// The system puts thin spaces around the dash of a range; the tests compare with plain spaces.
    private func range(of trip: PlannedTrip) -> String {
        TripDateFormatting.range(of: trip, calendar: calendar, locale: locale).plainSpaces
    }

    @Test
    func aTripInOneMonthIsWrittenAsOneRange() {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))

        #expect(range(of: trip) == "12 – 25 Jan 2027")
    }

    @Test
    func aTripAcrossMonthsAndYearsKeepsBothEnds() {
        let acrossMonths = Support.trip(from: (2_027, 1, 30), to: (2_027, 2, 2))
        let acrossYears = Support.trip(from: (2_026, 12, 28), to: (2_027, 1, 3))

        #expect(range(of: acrossMonths) == "30 Jan – 2 Feb 2027")
        #expect(range(of: acrossYears) == "28 Dec 2026 – 3 Jan 2027")
    }

    @Test
    func aOneDayTripIsOneDate() {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 12))

        #expect(range(of: trip) == "12 Jan 2027")
    }

    @Test
    func aRangeInAnotherLocaleFollowsThatLocale() {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))
        let american = TripDateFormatting.range(of: trip, calendar: calendar, locale: Locale(identifier: "en_US")).plainSpaces

        #expect(american == "Jan 12 – 25, 2027")
    }

    @Test
    func lengthCountsDaysAndNights() {
        #expect(TripDateFormatting.length(dayCount: 14, nightCount: 13) == "14 days (13 nights)")
        #expect(TripDateFormatting.length(dayCount: 2, nightCount: 1) == "2 days (1 night)")
        #expect(TripDateFormatting.length(dayCount: 1, nightCount: 0) == "1 day")
    }

    // MARK: List rows

    @Test
    func aRowNamesTheCountryDatesAndTiming() {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25), note: "Surf camp")
        let row = TripListRow(trip: trip, now: now, calendar: calendar, locale: locale)

        #expect(row.id == trip.id)
        #expect(row.countryName == "Morocco")
        #expect(row.dates.plainSpaces == "12 – 25 Jan 2027")
        #expect(row.timing == "in 92 days")
        #expect(row.hasEnded == false)
        #expect(row.note == "Surf camp")
        #expect(row.accessibilityLabel.plainSpaces == "Morocco, 12 – 25 Jan 2027, in 92 days")
    }

    @Test
    func anEndedTripIsMarked() {
        let trip = Support.trip("PT", from: (2_026, 9, 20), to: (2_026, 9, 28))
        let row = TripListRow(trip: trip, now: now, calendar: calendar, locale: locale)

        #expect(row.timing == "ended")
        #expect(row.hasEnded)
    }

    @Test
    func aTripThatIsOnSaysNow() {
        let trip = Support.trip("ES", from: (2_026, 10, 10), to: (2_026, 10, 20))

        #expect(TripListRow(trip: trip, now: now, calendar: calendar, locale: locale).timing == "now")
    }

    // MARK: Selection

    @Test
    func theFirstTripThatHasNotEndedIsSelectedFirst() {
        let ended = Support.trip("PT", from: (2_026, 9, 20), to: (2_026, 9, 28))
        let upcoming = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))

        #expect(TripSelection.initial(among: [ended, upcoming], now: now, calendar: calendar) == upcoming.id)
        #expect(TripSelection.initial(among: [ended], now: now, calendar: calendar) == ended.id)
        #expect(TripSelection.initial(among: [], now: now, calendar: calendar) == nil)
    }

    @Test
    func aSelectionThatNoLongerExistsFallsBack() {
        let first = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))
        let second = Support.trip("PT", from: (2_027, 3, 1), to: (2_027, 3, 8))

        #expect(TripSelection.reconciled(second.id, among: [first, second], now: now, calendar: calendar) == second.id)
        #expect(TripSelection.reconciled(UUID(), among: [first, second], now: now, calendar: calendar) == first.id)
        #expect(TripSelection.reconciled(nil, among: [first], now: now, calendar: calendar) == first.id)
    }

    // MARK: Draft

    @Test
    func aNewDraftStartsInAWeekAndLastsAWeek() {
        let draft = TripDraft.new(now: now, calendar: calendar)

        #expect(draft.isNew)
        #expect(draft.countryCode == nil)
        #expect(draft.startDate == calendar.startOfDay(for: Support.date(2_026, 10, 19)))
        #expect(draft.endDate == calendar.startOfDay(for: Support.date(2_026, 10, 25)))
        #expect(draft.note.isEmpty)
    }

    @Test
    func aDraftWithoutACountryCannotBeSaved() {
        let draft = TripDraft.new(now: now, calendar: calendar)

        #expect(draft.problem(now: now, calendar: calendar) == .noCountry)
        #expect(draft.canSave(now: now, calendar: calendar) == false)
        #expect(draft.trip() == nil)
    }

    @Test
    func movingTheStartPastTheEndPullsTheEndAlong() {
        var draft = TripDraft.new(now: now, calendar: calendar)
        let later = Support.date(2_026, 12, 1)

        draft.setStart(later)

        #expect(draft.startDate == later)
        #expect(draft.endDate == later)
    }

    @Test
    func movingTheStartWithinTheTripKeepsTheEnd() {
        var draft = TripDraft.new(now: now, calendar: calendar)
        let end = draft.endDate

        draft.setStart(Support.date(2_026, 10, 21))

        #expect(draft.endDate == end)
    }

    @Test
    func theEndCanBeChosenUpToTheLongestKeptTrip() {
        let draft = TripDraft.new(now: now, calendar: calendar)
        let range = draft.endDateRange(calendar: calendar)

        #expect(range.lowerBound == draft.startDate)
        #expect(calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day == PlannedTrip.maximumDurationDays - 1)
    }

    @Test
    func theNoteIsLimitedToTwoHundredCharacters() {
        var draft = TripDraft.new(now: now, calendar: calendar)
        draft.note = String(repeating: "a", count: 250)

        draft.limitNote()

        #expect(draft.note.count == PlannedTrip.maximumNoteLength)
        #expect(TripPlannerText.noteCounter(draft.note) == "200/200")
    }

    @Test
    func aTripThatEndedLongAgoCannotBeSavedAndSaysWhy() {
        var draft = TripDraft.new(now: now, calendar: calendar)
        draft.countryCode = "MA"
        draft.setStart(Support.date(2_026, 8, 1))
        draft.endDate = Support.date(2_026, 8, 10)

        #expect(draft.problem(now: now, calendar: calendar) == .tooLongAgo)
        #expect(draft.canSave(now: now, calendar: calendar) == false)
        #expect(draft.hint(now: now, calendar: calendar) == "Trips that ended more than 30 days ago are not kept.")
    }

    @Test
    func aValidDraftBecomesATripAndKeepsTheIdOfTheEditedOne() throws {
        let existing = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))
        var draft = TripDraft(trip: existing)
        draft.note = "  Surf camp "

        let trip = try #require(draft.trip())

        #expect(draft.isNew == false)
        #expect(draft.canSave(now: now, calendar: calendar))
        #expect(draft.hint(now: now, calendar: calendar) == nil)
        #expect(trip.id == existing.id)
        #expect(trip.countryCode == "MA")
        #expect(trip.note == "  Surf camp ")
    }

    @Test
    func editingATripKeepsItsChecklist() throws {
        var state = TripChecklistState(checkedItemIDs: ["roaming", "cash.MAD"])
        state.addCustomItem(title: "Print the booking")
        var existing = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))
        existing.checklist = state

        var draft = TripDraft(trip: existing)
        draft.note = "Surf camp"
        draft.setStart(Support.date(2_027, 1, 14))

        #expect(draft.checklist == state)
        #expect(try #require(draft.trip()).checklist == state)
    }

    @Test
    func aNewDraftStartsWithAnEmptyChecklist() throws {
        var draft = TripDraft.new(now: now, calendar: calendar)
        draft.countryCode = "MA"

        #expect(try #require(draft.trip()).checklist.isEmpty)
    }

    // MARK: Checklist

    private func row(startingInDays days: Int, checklist: (done: Int, total: Int)?) -> TripListRow {
        let start = calendar.date(byAdding: .day, value: days, to: Support.date(2_026, 10, 12))!
        let trip = PlannedTrip(countryCode: "MA", startDate: start, endDate: calendar.date(byAdding: .day, value: 6, to: start)!)
        return TripListRow(trip: trip, checklist: checklist, now: now, calendar: calendar, locale: locale)
    }

    @Test
    func theListRowShowsTheChecklistProgressInNeutralColour() {
        let result = row(startingInDays: 60, checklist: (done: 3, total: 9))

        #expect(result.checklistProgress == "3/9")
        #expect(result.checklistTone == .neutral)
        #expect(result.accessibilityLabel.hasSuffix("in 60 days, 3 of 9 checklist items done"))
    }

    @Test
    func theListRowTurnsSandWhenTheTripIsAboutToStartWithItemsLeft() {
        #expect(row(startingInDays: 3, checklist: (done: 3, total: 9)).checklistTone == .caution)
        #expect(row(startingInDays: 0, checklist: (done: 8, total: 9)).checklistTone == .caution)
        #expect(row(startingInDays: 4, checklist: (done: 3, total: 9)).checklistTone == .neutral)
    }

    @Test
    func aCompleteOrStartedChecklistStaysNeutral() {
        #expect(row(startingInDays: 1, checklist: (done: 9, total: 9)).checklistTone == .neutral)
        #expect(row(startingInDays: -2, checklist: (done: 3, total: 9)).checklistTone == .neutral)
    }

    @Test
    func aTripWithoutChecklistItemsShowsNoProgress() {
        let none = row(startingInDays: 1, checklist: (done: 0, total: 0))

        #expect(none.checklistProgress == nil)
        #expect(none.checklistTone == .neutral)
        #expect(none.checklistSpokenProgress == nil)
        #expect(row(startingInDays: 1, checklist: nil).checklistProgress == nil)
    }

    @Test
    func updatingTheChecklistGoesThroughTheSanitizer() throws {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))
        let other = Support.trip("PT", from: (2_027, 3, 1), to: (2_027, 3, 8))

        let trips = TripPlannerEditing.updatingChecklist(of: trip.id, in: [other, trip], now: now, calendar: calendar) {
            $0.setChecked(true, itemID: "roaming")
            $0.setChecked(true, itemID: "")
            $0.addCustomItem(title: "  Print the booking  ")
        }

        let updated = try #require(trips.first { $0.id == trip.id })
        #expect(trips.map(\.id) == [trip.id, other.id])
        #expect(updated.checklist.checkedItemIDs == ["roaming"])
        #expect(updated.checklist.customItems.map(\.title) == ["Print the booking"])
        #expect(trips.first { $0.id == other.id }?.checklist.isEmpty == true)
    }

    @Test
    func updatingTheChecklistOfAnUnknownTripChangesNothing() {
        let trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))

        let trips = TripPlannerEditing.updatingChecklist(of: UUID(), in: [trip], now: now, calendar: calendar) {
            $0.setChecked(true, itemID: "roaming")
        }

        #expect(trips == [trip])
    }

    // MARK: Editing

    @Test
    func savingAddsATripAndSortsByStart() {
        let later = Support.trip("PT", from: (2_027, 3, 1), to: (2_027, 3, 8))
        let sooner = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))

        let trips = TripPlannerEditing.saving(sooner, into: [later], now: now, calendar: calendar)

        #expect(trips.map(\.id) == [sooner.id, later.id])
    }

    @Test
    func savingAnEditedTripReplacesItInPlaceOfAddingACopy() throws {
        let original = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))
        var edited = original
        edited.countryCode = "pt"
        edited.note = "  Lisbon  "

        let trips = TripPlannerEditing.saving(edited, into: [original], now: now, calendar: calendar)

        #expect(trips.count == 1)
        let saved = try #require(trips.first)
        #expect(saved.countryCode == "PT")
        #expect(saved.note == "Lisbon")
    }

    @Test
    func savingPullsTheEndBackToTheLongestKeptTrip() throws {
        var trip = Support.trip(from: (2_027, 1, 1), to: (2_027, 1, 2))
        trip.endDate = Support.date(2_031, 1, 1)

        let saved = try #require(TripPlannerEditing.saving(trip, into: [], now: now, calendar: calendar).first)

        #expect(saved.dayCount(calendar: calendar) == PlannedTrip.maximumDurationDays)
    }

    @Test
    func deletingRemovesOnlyThatTrip() {
        let first = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 26))
        let second = Support.trip("PT", from: (2_027, 3, 1), to: (2_027, 3, 8))

        #expect(TripPlannerEditing.deleting(first.id, from: [first, second], now: now, calendar: calendar).map(\.id) == [second.id])
    }

    @Test
    func theListIsFullAtTheMaximum() {
        let trips = (0..<AppSettings.maximumPlannedTrips).map { offset in
            Support.trip(from: (2_027, 1, 1 + offset), to: (2_027, 1, 1 + offset))
        }

        #expect(TripPlannerEditing.canAddTrip(to: Array(trips.dropLast())))
        #expect(TripPlannerEditing.canAddTrip(to: trips) == false)
        #expect(TripPlannerText.limitText == "You can plan up to 20 trips.")
    }

    // MARK: Wording

    @Test
    func theFooterSaysWhatLeavesTheMac() {
        #expect(TripPlannerText.footer == "Trips stay on this Mac. Holidays and advisories send only the destination country code.")
        #expect(TripPlannerText.emptyTitle == "Plan your next trip")
    }
}

extension String {
    /// The text with the thin and no-break spaces of the system's date formats turned into plain spaces.
    var plainSpaces: String {
        replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
