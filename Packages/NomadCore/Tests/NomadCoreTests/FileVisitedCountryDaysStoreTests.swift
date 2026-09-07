import Foundation
import NomadCore
import Testing

struct FileVisitedCountryDaysStoreTests {
    @Test
    func recordsFirstObservedDay() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 1, day: 12), country: "Spain", countryCode: "ES", source: .publicIPGeolocation))

        let values = try await store.loadAll()
        #expect(values.count == 1)
        #expect(values.first?.day == .init(year: 2_026, month: 1, day: 12))
        #expect(values.first?.country == "Spain")
        #expect(values.first?.countryCode == "ES")
        #expect(values.first?.source == .publicIPGeolocation)
        #expect(values.first?.isInferred == false)
    }

    @Test
    func ignoresLaterSameDayCountryChanges() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 1, day: 12), country: "Finland", countryCode: "FI", source: .deviceLocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 12), country: "Sweden", countryCode: "SE", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.count == 1)
        #expect(values.first?.country == "Finland")
        #expect(values.first?.countryCode == "FI")
    }

    @Test
    func replacesSameDayIPWithDevice() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 1, day: 12), country: "Finland", countryCode: "FI", source: .publicIPGeolocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 12), country: "Sweden", countryCode: "SE", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.count == 1)
        #expect(values.first?.country == "Sweden")
        #expect(values.first?.countryCode == "SE")
        #expect(values.first?.source == .deviceLocation)
        #expect(values.first?.isInferred == false)
    }

    @Test
    func fillsEvenGapCorrectlyBetweenCountries() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 1, day: 1), country: "Spain", countryCode: "ES", source: .deviceLocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 4), country: "France", countryCode: "FR", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.map(\.day) == [
            .init(year: 2_026, month: 1, day: 1),
            .init(year: 2_026, month: 1, day: 2),
            .init(year: 2_026, month: 1, day: 3),
            .init(year: 2_026, month: 1, day: 4)
        ])
        #expect(values.map(\.countryCode) == ["ES", "ES", "FR", "FR"])
        #expect(values.map(\.isInferred) == [false, true, true, false])
    }

    @Test
    func fillsOddGapWithExtraDayOnEarlierCountry() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 1, day: 1), country: "Spain", countryCode: "ES", source: .deviceLocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 5), country: "France", countryCode: "FR", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.map(\.countryCode) == ["ES", "ES", "ES", "FR", "FR"])
        #expect(values.map(\.isInferred) == [false, true, true, true, false])
    }

    @Test
    func fillsSameCountryGapWithSameCountry() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 2, day: 10), country: "Finland", countryCode: "FI", source: .publicIPGeolocation))
        try await store.record(input(day: .init(year: 2_026, month: 2, day: 13), country: "Finland", countryCode: "FI", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.map(\.countryCode) == ["FI", "FI", "FI", "FI"])
        #expect(values.filter(\.isInferred).count == 2)
    }

    @Test
    func replacingInferredDayRebuildsFollowingGap() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 1, day: 1), country: "Spain", countryCode: "ES", source: .deviceLocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 5), country: "France", countryCode: "FR", source: .deviceLocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 3), country: "Netherlands", countryCode: "NL", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.map(\.day) == [
            .init(year: 2_026, month: 1, day: 1),
            .init(year: 2_026, month: 1, day: 2),
            .init(year: 2_026, month: 1, day: 3),
            .init(year: 2_026, month: 1, day: 4),
            .init(year: 2_026, month: 1, day: 5)
        ])
        #expect(values.map(\.countryCode) == ["ES", "ES", "NL", "NL", "FR"])
        #expect(values.map(\.isInferred) == [false, true, false, true, false])
    }

    @Test
    func doesNotBackfillBeforeFirstObservedDay() async throws {
        let store = makeStore()

        try await store.record(input(day: .init(year: 2_026, month: 3, day: 10), country: "Italy", countryCode: "IT", source: .deviceLocation))

        let values = try await store.loadAll()
        #expect(values.map(\.day) == [.init(year: 2_026, month: 3, day: 10)])
    }

    @Test
    func migratesLegacyArrayAndPersistsVersionedState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("country-days.json")
        let legacy = [
            VisitedCountryDay(day: .init(year: 2_026, month: 1, day: 1), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: false),
            VisitedCountryDay(day: .init(year: 2_026, month: 1, day: 2), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: true)
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: fileURL)
        let store = FileVisitedCountryDaysStore(fileURL: fileURL)

        #expect(try await store.loadAll().count == 1)
        try await store.setOverride(.init(day: .init(year: 2_026, month: 1, day: 2), country: "Sweden", countryCode: "SE"))

        let migrated = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        #expect(migrated?["version"] as? Int == 2)
        #expect(try await store.loadAll().map(\.countryCode) == ["FI", "SE"])
    }

    @Test
    func manualOverrideSurvivesRecordingAndCanRestoreObservation() async throws {
        let store = makeStore()
        let day = VisitedCountryDayStamp(year: 2_026, month: 4, day: 5)
        try await store.record(input(day: day, country: "Finland", countryCode: "FI", source: .deviceLocation))
        try await store.setOverride(.init(day: day, country: "Spain", countryCode: "ES"))
        try await store.record(input(day: day, country: "Sweden", countryCode: "SE", source: .deviceLocation))

        let overridden = try await store.loadAll()
        #expect(overridden.first?.countryCode == "ES")
        #expect(overridden.first?.origin == .manual)

        try await store.restoreObservation(for: day)
        let restored = try await store.loadAll()
        #expect(restored.first?.countryCode == "FI")
        #expect(restored.first?.origin == .observed)
    }

    @Test
    func acceptsManualMissingDayAndRebuildsNeighboringEstimates() async throws {
        let store = makeStore()
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 1), country: "Finland", countryCode: "FI", source: .deviceLocation))
        try await store.record(input(day: .init(year: 2_026, month: 1, day: 5), country: "France", countryCode: "FR", source: .deviceLocation))
        try await store.setOverride(.init(day: .init(year: 2_026, month: 1, day: 3), country: "Spain", countryCode: "ES"))

        let values = try await store.loadAll()
        #expect(values.map(\.countryCode) == ["FI", "FI", "ES", "ES", "FR"])
        #expect(values[2].origin == .manual)
    }

    @Test
    func rejectsInvalidManualCountryInput() async throws {
        let store = makeStore()
        await #expect(throws: VisitedCountryDayStoreError.missingCountry) {
            try await store.setOverride(.init(day: .init(year: 2_026, month: 1, day: 1), country: " ", countryCode: "FI"))
        }
        await #expect(throws: VisitedCountryDayStoreError.invalidCountryCode("FIN")) {
            try await store.setOverride(.init(day: .init(year: 2_026, month: 1, day: 1), country: "Finland", countryCode: "FIN"))
        }
    }

    @Test
    func exportsVersionedEscapedCSV() {
        let csv = VisitedCountryDaysCSVExporter.export([
            .init(day: .init(year: 2_026, month: 6, day: 1), country: "Cote, \"North\"", countryCode: "CN", source: .deviceLocation, isInferred: false, isManual: true)
        ], year: 2_026)

        #expect(csv == "format_version,day,country,country_code,origin,capture_source,is_inferred,is_manual\n1,2026-06-01,\"Cote, \"\"North\"\"\",CN,manual,manual,false,true\n")
    }

    @Test
    func yearSummaryUsesTrackedDaysAndSortedCountries() {
        let entries: [VisitedCountryDay] = [
            .init(day: .init(year: 2_026, month: 1, day: 1), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: false),
            .init(day: .init(year: 2_026, month: 1, day: 2), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: true),
            .init(day: .init(year: 2_026, month: 1, day: 3), country: "Spain", countryCode: "ES", source: .publicIPGeolocation, isInferred: false)
        ]

        let summary = entries.yearSummary(for: 2_026)

        #expect(summary?.year == 2_026)
        #expect(summary?.totalTrackedDays == 3)
        #expect(summary?.items.map(\.countryCode) == ["FI", "ES"])
        #expect(summary?.items.map(\.dayCount) == [2, 1])
        #expect(summary?.items.map(\.percentage) == [2.0 / 3.0, 1.0 / 3.0])
    }

    @Test
    func monthlySummariesGroupAndSortMonthsDescending() {
        let entries: [VisitedCountryDay] = [
            .init(day: .init(year: 2_026, month: 1, day: 1), country: "Finland", countryCode: "FI", source: .deviceLocation, isInferred: false),
            .init(day: .init(year: 2_026, month: 1, day: 2), country: "Spain", countryCode: "ES", source: .publicIPGeolocation, isInferred: false),
            .init(day: .init(year: 2_026, month: 3, day: 4), country: "Spain", countryCode: "ES", source: .deviceLocation, isInferred: false),
            .init(day: .init(year: 2_026, month: 3, day: 5), country: "Spain", countryCode: "ES", source: .deviceLocation, isInferred: true)
        ]

        let summaries = entries.monthlySummaries(for: 2_026)

        #expect(summaries.map(\.month) == [3, 1])
        #expect(summaries.first?.totalTrackedDays == 2)
        #expect(summaries.first?.items.map(\.countryCode) == ["ES"])
        #expect(summaries.last?.items.map(\.countryCode) == ["FI", "ES"])
        #expect(summaries.last?.days.map(\.day.day) == [1, 2])
    }

    private func makeStore() -> FileVisitedCountryDaysStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return FileVisitedCountryDaysStore(fileURL: directory.appendingPathComponent("country-days.json"))
    }

    private func input(
        day: VisitedCountryDayStamp,
        country: String,
        countryCode: String?,
        source: VisitedPlaceSource
    ) -> VisitedCountryDayInput {
        VisitedCountryDayInput(
            day: day,
            country: country,
            countryCode: countryCode,
            source: source,
            observedAt: .now
        )
    }
}
