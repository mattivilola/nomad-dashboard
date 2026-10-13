import Foundation
import NomadCore
import Testing
@testable import NomadUI

/// Counts the lookups a model makes, so the tests can see what it asks the network for.
@MainActor
private final class RecordingServices {
    var onlineCalls: [(country: String, force: Bool)] = []
    var priceCalls: [String] = []
    var online: TripPreviewOnline?
    var indices: [String: [LocalPriceIndicatorKind: Double]] = [:]

    var services: TripPlannerModel.Services {
        TripPlannerModel.Services(
            online: { [self] trip, force in
                onlineCalls.append((trip.countryCode, force))
                return online
            },
            priceIndices: { [self] code in
                priceCalls.append(code)
                return indices[code]
            }
        )
    }
}

@MainActor
struct TripPlannerModelTests {
    private typealias Support = StaysTestSupport
    private let calendar = Support.calendar

    private func makeStore(trips: [PlannedTrip] = [], citizenships: [String] = ["FI"], home: String? = nil) throws -> AppSettingsStore {
        let store = try AppSettingsStore(defaults: #require(UserDefaults(suiteName: UUID().uuidString)))
        store.settings = Support.settings(trips: trips, citizenships: citizenships, home: home)
        return store
    }

    private func makeModel(
        store: AppSettingsStore,
        services: RecordingServices,
        policy: DashboardResourcePolicy = .normal
    ) -> TripPlannerModel {
        TripPlannerModel(
            settingsStore: store,
            services: services.services,
            context: TripPlannerModel.Context(countryDays: [], currentCountryCode: "FI", policy: policy),
            homeTimeZoneIdentifier: "Europe/Helsinki",
            now: { Support.now },
            calendar: calendar,
            locale: Support.locale
        )
    }

    private let morocco = Support.trip(from: (2_027, 1, 12), to: (2_027, 1, 25))
    private let portugal = Support.trip("PT", from: (2_027, 3, 1), to: (2_027, 3, 8))

    // MARK: Selection and preview

    @Test
    func theFirstUpcomingTripIsSelectedAndPreviewedImmediately() throws {
        let store = try makeStore(trips: [morocco, portugal])
        let model = makeModel(store: store, services: RecordingServices())

        #expect(model.selectedTripID == morocco.id)
        #expect(model.preview?.countryCode == "MA")
        #expect(model.presentation?.title == "Morocco")
        #expect(model.onlineState == .loading)
    }

    @Test
    func withoutTripsThereIsNothingToPreview() throws {
        let store = try makeStore()
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)

        #expect(model.selectedTripID == nil)
        #expect(model.preview == nil)
        #expect(model.presentation == nil)
        #expect(services.onlineCalls.isEmpty)
    }

    @Test
    func selectingAnotherTripLoadsItsHolidaysAndAdvisory() async throws {
        let store = try makeStore(trips: [morocco, portugal])
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)
        await model.waitForLoads()

        model.select(portugal.id)
        await model.waitForLoads()

        #expect(model.preview?.countryCode == "PT")
        #expect(services.onlineCalls.map(\.country) == ["MA", "PT"])
        #expect(services.onlineCalls.allSatisfy { $0.force == false })
    }

    // MARK: Online

    @Test
    func loadedOnlineDataReachesThePresentation() async throws {
        let store = try makeStore(trips: [morocco])
        let services = RecordingServices()
        services.online = TripPreviewOnline(holidays: [], advisory: nil, fetchedAt: Support.now)
        let model = makeModel(store: store, services: services)

        await model.waitForLoads()

        #expect(model.onlineState == .loaded(try #require(services.online)))
        #expect(model.presentation?.online.holidays.first?.text == "None during your trip")
    }

    @Test
    func nothingLoadedMeansUnavailable() async throws {
        let store = try makeStore(trips: [morocco])
        let model = makeModel(store: store, services: RecordingServices())

        await model.waitForLoads()

        #expect(model.onlineState == .unavailable)
    }

    @Test
    func refreshingAsksAgainAndForcesIt() async throws {
        let store = try makeStore(trips: [morocco])
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)
        await model.waitForLoads()

        model.refreshOnline()
        await model.waitForLoads()

        #expect(services.onlineCalls.map(\.force) == [false, true])
    }

    @Test
    func editingOnlyTheNoteDoesNotAskTheNetworkAgain() async throws {
        let store = try makeStore(trips: [morocco])
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)
        await model.waitForLoads()

        var draft = TripDraft(trip: morocco)
        draft.note = "Surf camp"
        model.save(draft)
        await model.waitForLoads()

        #expect(model.selectedTrip?.note == "Surf camp")
        #expect(services.onlineCalls.count == 1)
    }

    @Test
    func movingTheTripToAnotherCountryAsksForThatCountryOnly() async throws {
        let store = try makeStore(trips: [morocco])
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)
        await model.waitForLoads()

        var draft = TripDraft(trip: morocco)
        draft.countryCode = "PT"
        model.save(draft)
        await model.waitForLoads()

        #expect(services.onlineCalls.map(\.country) == ["MA", "PT"])
    }

    // MARK: Prices

    @Test
    func pricesComparePortugalWithFinland() async throws {
        let store = try makeStore(trips: [portugal])
        let services = RecordingServices()
        services.indices = [
            "PT": [.groceries: 70, .overall: 80],
            "FI": [.groceries: 100, .overall: 100]
        ]
        let model = makeModel(store: store, services: services)

        await model.waitForLoads()

        #expect(model.priceState == .loaded([
            PriceLevelDifference(kind: .groceries, percentDifference: -30),
            PriceLevelDifference(kind: .overall, percentDifference: -20)
        ]))
        #expect(Set(services.priceCalls) == ["PT", "FI"])
        #expect(model.presentation?.prices?.lines.first == "Groceries ~30% cheaper than Finland")
    }

    @Test
    func theHomeCountryChosenInSettingsIsWhatPricesAreComparedWith() async throws {
        let store = try makeStore(trips: [portugal], home: "SE")
        let services = RecordingServices()
        services.indices = ["PT": [.overall: 80], "SE": [.overall: 100]]
        let model = makeModel(store: store, services: services)

        await model.waitForLoads()

        #expect(Set(services.priceCalls) == ["PT", "SE"])
        #expect(model.presentation?.prices?.lines == ["Overall ~20% cheaper than Sweden"])
    }

    @Test
    func changingTheHomeCountryComparesAgain() async throws {
        let store = try makeStore(trips: [portugal])
        let services = RecordingServices()
        services.indices = ["PT": [.overall: 80], "FI": [.overall: 100], "SE": [.overall: 90]]
        let model = makeModel(store: store, services: services)
        await model.waitForLoads()

        store.settings.homeCountryCode = "SE"
        await model.waitForLoads()

        #expect(model.presentation?.prices?.lines == ["Overall ~11% cheaper than Sweden"])
    }

    @Test
    func noPriceComparisonWithTheHomeCountryItself() async throws {
        let store = try makeStore(trips: [Support.trip("FI", from: (2_027, 3, 1), to: (2_027, 3, 8))])
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)

        await model.waitForLoads()

        #expect(model.priceState == .unavailable)
        #expect(services.priceCalls.isEmpty)
    }

    @Test
    func noPriceComparisonWithoutAHomeCountry() async throws {
        let store = try makeStore(trips: [portugal], citizenships: [])
        let services = RecordingServices()
        let model = makeModel(store: store, services: services)

        await model.waitForLoads()

        #expect(model.priceState == .unavailable)
        #expect(services.priceCalls.isEmpty)
    }

    @Test
    func pricesAreUnavailableWhenEitherSideCannotBeLoaded() async throws {
        let store = try makeStore(trips: [portugal])
        let services = RecordingServices()
        services.indices = ["PT": [.overall: 80]]
        let model = makeModel(store: store, services: services)

        await model.waitForLoads()

        #expect(model.priceState == .unavailable)
    }

    // MARK: Editing

    @Test
    func addingSavesThroughTheSanitizerAndSelectsTheNewTrip() throws {
        let store = try makeStore(trips: [portugal])
        let model = makeModel(store: store, services: RecordingServices())
        model.beginAdding()
        var draft = try #require(model.editor?.draft)
        draft.countryCode = "ma"
        draft.setStart(Support.date(2_027, 1, 12))
        draft.endDate = Support.date(2_027, 1, 25)
        draft.note = "  Surf camp  "

        model.save(draft)

        #expect(model.editor == nil)
        #expect(store.settings.plannedTrips.map(\.countryCode) == ["MA", "PT"])
        #expect(store.settings.plannedTrips.first?.note == "Surf camp")
        #expect(model.selectedTrip?.countryCode == "MA")
        #expect(model.trips.map(\.countryCode) == ["MA", "PT"])
    }

    @Test
    func aDraftWithoutACountryIsNotSaved() throws {
        let store = try makeStore()
        let model = makeModel(store: store, services: RecordingServices())
        model.beginAdding()
        let draft = try #require(model.editor?.draft)

        model.save(draft)

        #expect(store.settings.plannedTrips.isEmpty)
        #expect(model.editor != nil)
    }

    @Test
    func addingIsRefusedAtTheMaximum() throws {
        let trips = (0..<AppSettings.maximumPlannedTrips).map { offset in
            Support.trip(from: (2_027, 1, 1 + offset), to: (2_027, 1, 1 + offset))
        }
        let model = makeModel(store: try makeStore(trips: trips), services: RecordingServices())

        #expect(model.canAddTrip == false)
        model.beginAdding()
        #expect(model.editor == nil)

        var draft = TripDraft.new(now: Support.now, calendar: calendar)
        draft.countryCode = "PT"
        model.save(draft)
        #expect(model.trips.count == AppSettings.maximumPlannedTrips)
    }

    @Test
    func editingAtTheMaximumStillSaves() throws {
        let trips = (0..<AppSettings.maximumPlannedTrips).map { offset in
            Support.trip(from: (2_027, 1, 1 + offset), to: (2_027, 1, 1 + offset))
        }
        let model = makeModel(store: try makeStore(trips: trips), services: RecordingServices())
        model.beginEditing(trips[3].id)
        var draft = try #require(model.editor?.draft)
        draft.note = "Edited"

        model.save(draft)

        #expect(model.trips.count == AppSettings.maximumPlannedTrips)
        #expect(model.trips.first { $0.id == trips[3].id }?.note == "Edited")
    }

    @Test
    func editingStartsFromTheStoredTrip() throws {
        let store = try makeStore(trips: [morocco])
        let model = makeModel(store: store, services: RecordingServices())

        model.beginEditing(morocco.id)

        let draft = try #require(model.editor?.draft)
        #expect(draft.isNew == false)
        #expect(draft.id == morocco.id)
        #expect(draft.countryCode == "MA")
    }

    @Test
    func deletingSelectsTheNextTripAndEmptiesWhenNoneIsLeft() throws {
        let store = try makeStore(trips: [morocco, portugal])
        let model = makeModel(store: store, services: RecordingServices())

        model.delete(morocco.id)
        #expect(model.selectedTripID == portugal.id)
        #expect(store.settings.plannedTrips.map(\.id) == [portugal.id])

        model.delete(portugal.id)
        #expect(model.selectedTripID == nil)
        #expect(model.preview == nil)
        #expect(store.settings.plannedTrips.isEmpty)
    }

    @Test
    func theWholeListRowsFollowTheStore() throws {
        let store = try makeStore(trips: [morocco])
        let model = makeModel(store: store, services: RecordingServices())
        #expect(model.listRows.map(\.countryName) == ["Morocco"])

        store.settings.plannedTrips = [morocco, portugal]

        #expect(model.listRows.map(\.countryName) == ["Morocco", "Portugal"])
    }

    // MARK: Context

    @Test
    func theHomeTimeZoneChangesTheTimeRow() throws {
        let japan = Support.trip("JP", from: (2_027, 1, 12), to: (2_027, 1, 25))
        let store = try makeStore(trips: [japan])
        let model = makeModel(store: store, services: RecordingServices())
        #expect(model.presentation?.basics.first?.text == "Home (Helsinki) is 7 h behind")

        model.homeTimeZoneIdentifier = "Europe/Lisbon"

        #expect(model.presentation?.basics.first?.text == "Home (Lisbon) is 9 h behind")
    }

    @Test
    func theResourcePolicyDecidesTheUnavailableWording() async throws {
        let offline = DashboardResourcePolicy(mode: .automatic, conditions: ResourceConditions(pathAvailable: false))
        let model = makeModel(store: try makeStore(trips: [morocco]), services: RecordingServices(), policy: offline)

        await model.waitForLoads()

        #expect(model.presentation?.online.status == .unavailable("Not available offline"))
    }
}
