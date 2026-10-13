import Foundation
import NomadCore
import Testing
@testable import NomadUI

struct TripChecklistPresentationTests {
    private typealias Support = StaysTestSupport
    private let calendar = Support.calendar
    private let locale = Support.locale

    private func morocco(checklist: TripChecklistState = TripChecklistState()) -> PlannedTrip {
        var trip = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))
        trip.checklist = checklist
        return trip
    }

    private func presentation(
        _ trip: PlannedTrip,
        online: TripOnlineState = .loading
    ) -> TripChecklistPresentation {
        let settings = Support.settings(trips: [trip])
        let preview = TripPreview.make(
            trip: trip,
            settings: settings,
            countryDays: [],
            currentCountryCode: "FI",
            homeTimeZoneIdentifier: "Europe/Helsinki",
            now: Support.now,
            calendar: calendar,
            locale: locale
        )
        return TripChecklistPresentation(preview: preview, online: online, settings: settings, calendar: calendar, locale: locale)
    }

    private func loaded(advisory: Bool = true, holidays: [HolidayPeriodSnapshot] = []) -> TripOnlineState {
        let signal = TravelAlertSignalSnapshot(
            kind: .advisory,
            severity: .caution,
            title: "Morocco",
            summary: "Exercise a high degree of caution",
            sourceName: "Smartraveller",
            sourceURL: URL(string: "https://www.smartraveller.gov.au/destinations/africa/morocco"),
            updatedAt: Support.date(2_026, 10, 1),
            affectedCountryCodes: ["MA"]
        )
        return .loaded(TripPreviewOnline(holidays: holidays, advisory: advisory ? signal : nil, fetchedAt: Support.date(2_026, 10, 12)))
    }

    private func itemIDs(_ presentation: TripChecklistPresentation) -> [String] {
        presentation.groups.flatMap(\.items).map(\.id)
    }

    // MARK: Groups

    @Test
    func itemsAreGroupedInDisplayOrderUnderTheGroupTitles() {
        let result = presentation(morocco())

        #expect(result.groups.isEmpty == false)
        let order = TripChecklistGroup.allCases
        #expect(result.groups.map(\.id) == order.filter { group in result.groups.contains { $0.id == group } })
        #expect(result.groups.allSatisfy { $0.title == $0.id.title && $0.items.isEmpty == false })
    }

    @Test
    func theAdvisoryAndHolidaysJoinOnlyOnceTheOnlineDataHasLoaded() {
        let holiday = HolidayPeriodSnapshot(
            name: "Throne Day",
            startDate: Support.date(2_027, 1, 14),
            endDate: Support.date(2_027, 1, 14)
        )
        let before = presentation(morocco(), online: .loading)
        let unavailable = presentation(morocco(), online: .unavailable)
        let after = presentation(morocco(), online: loaded(holidays: [holiday]))

        #expect(itemIDs(before).contains("advisory") == false)
        #expect(itemIDs(unavailable) == itemIDs(before))
        #expect(itemIDs(after).contains("advisory"))
        #expect(itemIDs(after).contains { $0.hasPrefix("holiday.") })
        #expect(after.total == before.total + 2)
    }

    @Test
    func anItemWithALinkCarriesIt() throws {
        let result = presentation(morocco(), online: loaded())
        let advisory = try #require(result.groups.flatMap(\.items).first { $0.id == "advisory" })

        #expect(advisory.link?.host == "www.smartraveller.gov.au")
        #expect(result.groups.flatMap(\.items).contains { $0.link == nil })
    }

    // MARK: Progress

    @Test
    func theTicksAreReadFromTheTripsChecklist() {
        let plain = presentation(morocco())
        let firstID = itemIDs(plain)[0]
        let ticked = presentation(morocco(checklist: TripChecklistState(checkedItemIDs: [firstID, "no-longer-applies"])))

        #expect(plain.done == 0)
        #expect(ticked.done == 1)
        #expect(ticked.total == plain.total)
        #expect(ticked.groups.flatMap(\.items).filter(\.isChecked).map(\.id) == [firstID])
        #expect(ticked.progressText == "1 of \(plain.total) done")
        #expect(ticked.progress == 1 / Double(plain.total))
    }

    @Test
    func ownItemsCountTowardsTheProgress() {
        var state = TripChecklistState()
        state.addCustomItem(title: "Print the booking")
        let second = state.addCustomItem(title: "Buy sunscreen")
        state.setCustomItemChecked(true, id: second!.id)

        let result = presentation(morocco(checklist: state))
        let plain = presentation(morocco())

        #expect(result.customItems.map(\.title) == ["Print the booking", "Buy sunscreen"])
        #expect(result.customItems.map(\.isChecked) == [false, true])
        #expect(result.total == plain.total + 2)
        #expect(result.done == 1)
    }

    @Test
    func theCompactAndSpokenFormsNeedAtLeastOneItem() {
        #expect(TripChecklistPresentation.compactProgressText(done: 3, total: 9) == "3/9")
        #expect(TripChecklistPresentation.compactProgressText(done: 0, total: 0) == nil)
        #expect(TripChecklistPresentation.spokenProgress(done: 3, total: 9) == "3 of 9 checklist items done")
        #expect(TripChecklistPresentation.spokenProgress(done: 0, total: 1) == "0 of 1 checklist item done")
        #expect(TripChecklistPresentation.spokenProgress(done: 0, total: 0) == nil)
    }

    // MARK: Adding

    @Test
    func aBlankDraftCannotBeAdded() {
        let result = presentation(morocco())

        #expect(result.canAdd("Print the booking"))
        #expect(result.canAdd("   \n ") == false)
        #expect(result.canAdd("") == false)
    }

    @Test
    func theTitleIsLimitedAndTheNoteSaysWhen() {
        let result = presentation(morocco())
        let long = String(repeating: "a", count: 130)

        #expect(TripChecklistPresentation.limitedTitle(long).count == TripChecklistCustomItem.maximumTitleLength)
        #expect(result.limitNote(forDraft: "short") == nil)
        #expect(result.limitNote(forDraft: String(repeating: "a", count: 119)) == nil)
        #expect(result.limitNote(forDraft: String(repeating: "a", count: 120)) == "Items are limited to 120 characters.")
    }

    @Test
    func aFullListStopsAddingAndSaysWhy() {
        var state = TripChecklistState()
        for index in 0..<TripChecklistState.maximumCustomItems {
            state.addCustomItem(title: "Item \(index)")
        }
        let full = presentation(morocco(checklist: state))

        #expect(full.canAddCustomItem == false)
        #expect(full.canAdd("One more") == false)
        #expect(full.limitNote(forDraft: "") == "You can add up to 30 items of your own.")
        #expect(presentation(morocco()).canAddCustomItem)
    }
}
