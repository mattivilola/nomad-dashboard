import Foundation
import NomadCore
import Testing
@testable import NomadUI

struct ArrivalBriefingPresentationTests {
    private typealias Support = StaysTestSupport

    private let morocco = EmergencyNumbers(general: "177", police: "19", ambulance: "15", fire: "15")

    private func period(_ kind: LocalRhythmKind, confidence: LocalRhythmDateConfidence = .expected) -> LocalRhythmPeriod {
        LocalRhythmPeriod(
            kind: kind,
            name: "Ramadan",
            countryCode: "MA",
            start: Support.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!,
            end: Support.calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 59))!,
            confidence: confidence,
            guidance: "Shops keep shorter hours."
        )
    }

    private func presentation(_ briefing: ArrivalBriefing, previous: String? = "ES") -> ArrivalBriefingPresentation {
        ArrivalBriefingPresentation(
            briefing: briefing,
            previousCountryCode: previous,
            now: Support.now,
            calendar: Support.calendar,
            locale: Support.locale
        )
    }

    private func row(_ kind: ArrivalBriefingPresentation.Row.Kind, in presentation: ArrivalBriefingPresentation) -> ArrivalBriefingPresentation.Row? {
        presentation.rows.first { $0.kind == kind }
    }

    @Test
    func titleAndSubtitleNameTheCountryAndWhereTheTravellerCameFrom() {
        let briefing = ArrivalBriefing(countryCode: "MA", countryName: "Morocco")

        #expect(presentation(briefing).title == "Welcome to Morocco")
        #expect(presentation(briefing).subtitle == "Arrived from Spain")
        #expect(presentation(briefing, previous: "MA").subtitle == nil)
        #expect(presentation(briefing, previous: nil).subtitle == nil)
    }

    @Test
    func anEmptyBriefingHasNoRows() {
        let empty = presentation(ArrivalBriefing(countryCode: "MA", countryName: "Morocco"))

        #expect(empty.rows.isEmpty)
        #expect(empty.collapsedSummary.isEmpty)
    }

    @Test
    func timeShowsTheLocalClockOffsetAndHome() throws {
        let time = ArrivalBriefing.Time(
            timeZoneIdentifier: "UTC",
            utcOffsetSeconds: 0,
            home: .init(timeZoneIdentifier: "Europe/Helsinki", cityName: "Helsinki", offsetFromLocalSeconds: 7_200)
        )
        let row = try #require(row(.time, in: presentation(ArrivalBriefing(countryCode: "MA", countryName: "Morocco", time: time))))

        #expect(row.text == "Local 12:00 (UTC+0) · Home (Helsinki) is 2 h ahead")
    }

    @Test
    func emergencyNumbersAreSelectableAndListTheOthers() throws {
        let row = try #require(row(.emergency, in: presentation(ArrivalBriefing(countryCode: "MA", countryName: "Morocco", emergency: morocco))))

        #expect(row.text == "177")
        #expect(row.detail == morocco.othersText)
        #expect(row.isSelectable)
    }

    @Test
    func drivingSideIsSandOnlyWhenItChanges() throws {
        func road(changes: Bool) throws -> ArrivalBriefingPresentation.Row {
            let briefing = ArrivalBriefing(
                countryCode: "GB",
                countryName: "United Kingdom",
                road: .init(side: .left, changesFromPreviousCountry: changes)
            )
            return try #require(row(.road, in: presentation(briefing)))
        }

        let changed = try road(changes: true)
        let same = try road(changes: false)

        #expect(changed.text == "Drive on the left")
        #expect(changed.tone == .caution)
        #expect(changed.flag == "Changed")
        #expect(same.tone == .neutral)
        #expect(same.flag == nil)
    }

    @Test
    func powerAndCurrencyCarryAChangeFlag() throws {
        let briefing = ArrivalBriefing(
            countryCode: "MA",
            countryName: "Morocco",
            power: .init(
                electricity: CountryElectricity(plugTypes: ["C", "E"], voltage: 220, frequencyHertz: 50),
                differsFromPreviousCountry: true
            ),
            money: .init(currencyCode: "MAD", currencyName: "Moroccan Dirham", changesFromPreviousCountry: true)
        )
        let result = presentation(briefing)

        #expect(row(.power, in: result)?.text == "Plug C, E · 220 V · 50 Hz")
        #expect(row(.power, in: result)?.flag == "Changed")
        #expect(row(.money, in: result)?.text == "Moroccan Dirham (MAD)")
        #expect(row(.money, in: result)?.flag == "Changed")
    }

    @Test
    func aKnownCurrencyWithoutANameShowsTheCode() throws {
        let briefing = ArrivalBriefing(
            countryCode: "MA",
            countryName: "Morocco",
            money: .init(currencyCode: "MAD", currencyName: nil, changesFromPreviousCountry: false)
        )
        let money = try #require(row(.money, in: presentation(briefing)))

        #expect(money.text == "MAD")
        #expect(money.flag == nil)
    }

    @Test
    func holidayAdvisoryAndDataGuardRowsAppearWhenPresent() throws {
        let briefing = ArrivalBriefing(
            countryCode: "MA",
            countryName: "Morocco",
            holiday: .init(name: "Throne Day", daysFromToday: 1),
            advisory: .init(severity: .warning, summary: "Exercise a high degree of caution.", sourceName: "Smartraveller"),
            dataGuardHint: ArrivalBriefing.dataGuardHintText
        )
        let result = presentation(briefing)

        #expect(row(.holiday, in: result)?.text == "Throne Day tomorrow")
        let advisory = try #require(row(.advisory, in: result))
        #expect(advisory.tone == .attention)
        #expect(advisory.detail == "Smartraveller")
        #expect(row(.dataGuard, in: result)?.text == ArrivalBriefing.dataGuardHintText)
        #expect(ArrivalBriefingPresentation.startMonitoringTitle == "Start monitoring")
    }

    @Test
    func rhythmPeriodsShowNameDatesAndGuidance() throws {
        let briefing = ArrivalBriefing(countryCode: "MA", countryName: "Morocco", rhythm: [period(.ramadan)])
        let rhythm = try #require(row(.rhythm, in: presentation(briefing)))

        #expect(rhythm.title == "Ramadan")
        #expect(rhythm.text == "12 Oct – 10 Nov (expected; may shift a day)")
        #expect(rhythm.detail == "Shops keep shorter hours.")
        #expect(rhythm.flag == "Now")
    }

    @Test
    func theEmbassyRowLeadsWithTheMissionAndKeepsTheHotlineSelectable() throws {
        let mission = DiplomaticMission(
            id: "Q1",
            sendingCountry: "FI",
            hostCountry: "MA",
            kind: .embassy,
            name: "Embassy of Finland, Rabat",
            city: "Rabat",
            latitude: 34,
            longitude: -6.8
        )
        let briefing = ArrivalBriefing(
            countryCode: "MA",
            countryName: "Morocco",
            embassy: .init(
                citizenshipCode: "FI",
                nearestMission: DiplomaticMissionMatch(mission: mission, distanceKilometers: 3),
                fallbackReason: nil,
                consularContacts: ConsularContacts(ministryName: "Ministry for Foreign Affairs of Finland", emergencyPhone: "+358 9 1605 5555")
            )
        )
        let embassy = try #require(row(.embassy, in: presentation(briefing)))

        #expect(embassy.text == "Embassy of Finland, Rabat")
        #expect(embassy.detail == "Ministry for Foreign Affairs +358 9 1605 5555")
        #expect(embassy.isSelectable)
    }

    @Test
    func rowsAppearInReadingOrder() {
        let briefing = ArrivalBriefing(
            countryCode: "MA",
            countryName: "Morocco",
            time: .init(timeZoneIdentifier: "UTC", utcOffsetSeconds: 0, home: nil),
            emergency: morocco,
            road: .init(side: .right, changesFromPreviousCountry: false),
            money: .init(currencyCode: "MAD", currencyName: nil, changesFromPreviousCountry: false),
            dataGuardHint: ArrivalBriefing.dataGuardHintText
        )

        #expect(presentation(briefing).rows.map(\.id) == ["time", "emergency", "road", "money", "dataGuard"])
    }

    @Test
    func theCollapsedLineHasTheEmergencyNumberAndAChangedDrivingSide() {
        let briefing = ArrivalBriefing(
            countryCode: "GB",
            countryName: "United Kingdom",
            emergency: EmergencyNumbers(general: "999"),
            road: .init(side: .left, changesFromPreviousCountry: true)
        )

        #expect(presentation(briefing).collapsedSummary == "Emergency 999 · Drive on the left")
    }

    // MARK: Which arrival to show

    private func settings(acknowledged: String? = nil, enabled: Bool = true) -> AppSettings {
        AppSettings(arrivalBriefingEnabled: enabled, arrivalBriefingAcknowledgedCountryCode: acknowledged)
    }

    @Test
    func theDetectedArrivalIsShown() throws {
        let event = try #require(ArrivalBriefingEvents.event(
            reopened: nil,
            countryDays: [Support.day(1, "ES")],
            currentCountryCode: "MA",
            settings: settings(),
            now: Support.now,
            calendar: Support.calendar
        ))

        #expect(event.countryCode == "MA")
        #expect(event.previousCountryCode == "ES")
    }

    @Test
    func aReopenedBriefingWinsEvenAfterAcknowledgement() throws {
        let reopened = try #require(ArrivalBriefingEvents.reopened(
            countryDays: [Support.day(5, "ES"), Support.day(1, "MA")],
            currentCountryCode: "ma",
            now: Support.now,
            calendar: Support.calendar
        ))
        let event = ArrivalBriefingEvents.event(
            reopened: reopened,
            countryDays: [Support.day(1, "MA")],
            currentCountryCode: "MA",
            settings: settings(acknowledged: "MA", enabled: false),
            now: Support.now,
            calendar: Support.calendar
        )

        #expect(reopened.countryCode == "MA")
        #expect(reopened.previousCountryCode == "ES")
        #expect(event == reopened)
    }

    @Test
    func aReopenedBriefingOfAnotherCountryIsDropped() throws {
        let reopened = try #require(ArrivalBriefingEvents.reopened(
            countryDays: [], currentCountryCode: "MA", now: Support.now, calendar: Support.calendar
        ))
        let event = ArrivalBriefingEvents.event(
            reopened: reopened,
            countryDays: [],
            currentCountryCode: "ES",
            settings: settings(),
            now: Support.now,
            calendar: Support.calendar
        )

        #expect(event == nil)
    }

    @Test
    func reopeningWithoutADifferentPreviousCountryFlagsNothingAsChanged() throws {
        let reopened = try #require(ArrivalBriefingEvents.reopened(
            countryDays: Support.run(4, "MA", endingOffset: 1),
            currentCountryCode: "MA",
            now: Support.now,
            calendar: Support.calendar
        ))

        #expect(reopened.previousCountryCode == "MA")
    }

    @Test
    func reopeningNeedsACurrentCountry() {
        #expect(ArrivalBriefingEvents.reopened(countryDays: [], currentCountryCode: nil, now: Support.now, calendar: Support.calendar) == nil)
        #expect(ArrivalBriefingEvents.reopened(countryDays: [], currentCountryCode: "Morocco", now: Support.now, calendar: Support.calendar) == nil)
    }

    @Test
    func aDisabledOrAcknowledgedBriefingIsNotDetected() {
        func event(_ settings: AppSettings) -> ArrivalEvent? {
            ArrivalBriefingEvents.event(
                reopened: nil,
                countryDays: [Support.day(1, "ES")],
                currentCountryCode: "MA",
                settings: settings,
                now: Support.now,
                calendar: Support.calendar
            )
        }

        #expect(event(settings(enabled: false)) == nil)
        #expect(event(settings(acknowledged: "MA")) == nil)
        #expect(event(settings(acknowledged: "ES")) != nil)
    }
}
