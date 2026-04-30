import Foundation
import NomadCore
import Testing

struct FileVisitedPlaceEventsStoreTests {
    @Test
    func recordsFirstObservedPlaceEvent() async throws {
        let store = makeStore()
        let observedAt = Date(timeIntervalSince1970: 1_767_225_600)

        try await store.record(input(city: "Paris", country: "France", countryCode: "FR", observedAt: observedAt))

        let values = try await store.loadAll()
        #expect(values.count == 1)
        #expect(values.first?.city == "Paris")
        #expect(values.first?.countryCode == "FR")
        #expect(values.first?.firstObservedAt == observedAt)
        #expect(values.first?.lastObservedAt == observedAt)
        #expect(values.first?.observedDay == .init(year: 2026, month: 1, day: 1))
    }

    @Test
    func mergesSamePlaceOnSameDayAndPrefersDeviceCoordinates() async throws {
        let store = makeStore()
        let firstObservedAt = Date(timeIntervalSince1970: 1_767_225_600)
        let secondObservedAt = firstObservedAt.addingTimeInterval(3_600)

        try await store.record(input(
            city: "Helsinki",
            country: "Finland",
            countryCode: "FI",
            latitude: 60,
            longitude: 24,
            source: .publicIPGeolocation,
            observedAt: firstObservedAt
        ))
        try await store.record(input(
            city: "Helsinki",
            country: "Finland",
            countryCode: "FI",
            latitude: 60.1699,
            longitude: 24.9384,
            source: .deviceLocation,
            observedAt: secondObservedAt
        ))

        let values = try await store.loadAll()
        #expect(values.count == 1)
        #expect(values.first?.latitude == 60.1699)
        #expect(values.first?.longitude == 24.9384)
        #expect(values.first?.firstObservedAt == firstObservedAt)
        #expect(values.first?.lastObservedAt == secondObservedAt)
        #expect(Set(values.first?.sources ?? []) == Set([.publicIPGeolocation, .deviceLocation]))
    }

    @Test
    func keepsSamePlaceOnDifferentDaysAsSeparateEventsAndBuildsOneStop() async throws {
        let store = makeStore()
        let firstObservedAt = Date(timeIntervalSince1970: 1_767_225_600)
        let secondObservedAt = firstObservedAt.addingTimeInterval(86_400)

        try await store.record(input(city: "Berlin", country: "Germany", countryCode: "DE", observedAt: firstObservedAt))
        try await store.record(input(
            city: "Berlin",
            country: "Germany",
            countryCode: "DE",
            observedAt: secondObservedAt,
            day: .init(year: 2026, month: 1, day: 2)
        ))

        let values = try await store.loadAll()
        let stops = values.travelStops(for: 2026)
        #expect(values.count == 2)
        #expect(stops.count == 1)
        #expect(stops.first?.dayCount == 2)
    }

    @Test
    func buildsSeparateTravelStopsWhenPlaceChanges() async throws {
        let events = [
            event(city: "Tarifa", country: "Spain", countryCode: "ES", observedAt: Date(timeIntervalSince1970: 1_767_225_600)),
            event(city: "Paris", country: "France", countryCode: "FR", observedAt: Date(timeIntervalSince1970: 1_767_312_000))
        ]

        let stops = events.travelStops(for: 2026)

        #expect(stops.count == 2)
        #expect(stops.map(\.sequenceNumber) == [1, 2])
        #expect(stops.map(\.displayName) == ["Tarifa, Spain", "Paris, France"])
    }

    private func makeStore() -> FileVisitedPlaceEventsStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return FileVisitedPlaceEventsStore(fileURL: directory.appendingPathComponent("visited-place-events.json"))
    }

    private func input(
        city: String,
        country: String,
        countryCode: String?,
        latitude: Double = 48.8566,
        longitude: Double = 2.3522,
        source: VisitedPlaceSource = .publicIPGeolocation,
        observedAt: Date,
        day: VisitedCountryDayStamp = .init(year: 2026, month: 1, day: 1)
    ) -> VisitedPlaceEventInput {
        VisitedPlaceEventInput(
            city: city,
            region: nil,
            country: country,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            source: source,
            observedAt: observedAt,
            observedDay: day
        )
    }

    private func event(
        city: String,
        country: String,
        countryCode: String?,
        observedAt: Date
    ) -> VisitedPlaceEvent {
        VisitedPlaceEvent(
            city: city,
            region: nil,
            country: country,
            countryCode: countryCode,
            latitude: 48.8566,
            longitude: 2.3522,
            sources: [.deviceLocation],
            firstObservedAt: observedAt,
            lastObservedAt: observedAt,
            observedDay: .init(year: 2026, month: 1, day: 1)
        )
    }
}
