import CoreLocation
import Foundation
@testable import NomadCore
import Testing

struct EmergencyCareProviderTests {
    @Test
    func classifyHospitalOwnershipUsesExplicitKeywordsOnly() {
        #expect(classifyHospitalOwnership(name: "Hospital Public de Valencia", ownershipHint: nil) == .public)
        #expect(classifyHospitalOwnership(name: "Clinica Privada Valencia", ownershipHint: nil) == .private)
        #expect(classifyHospitalOwnership(name: "General Hospital", ownershipHint: "Emergency department") == .unknown)
    }

    @Test
    func selectEmergencyHospitalsPrefersNearestPublicAndPrivateBeforeFillingRemainingSlots() {
        let hospitals = selectEmergencyHospitals(
            from: [
                EmergencyCareSearchResult(
                    name: "Hospital General",
                    address: "Street 1",
                    locality: "Valencia",
                    latitude: 39.4700,
                    longitude: -0.3760,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital Public de Valencia",
                    address: "Street 2",
                    locality: "Valencia",
                    latitude: 39.4720,
                    longitude: -0.3780,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital Privado Burjassot",
                    address: "Street 3",
                    locality: "Burjassot",
                    latitude: 39.4760,
                    longitude: -0.3820,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital Public de Valencia",
                    address: "Street 2",
                    locality: "Valencia",
                    latitude: 39.4720,
                    longitude: -0.3780,
                    ownershipHint: nil
                )
            ],
            origin: CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763),
            maximumResults: 3
        )

        #expect(hospitals.count == 3)
        #expect(hospitals[0].ownership == .public)
        #expect(hospitals[1].ownership == .private)
        #expect(hospitals[2].ownership == .unknown)
    }

    @Test
    func selectEmergencyHospitalsFallsBackToNearestThreeWhenOwnershipIsUnknown() {
        let hospitals = selectEmergencyHospitals(
            from: [
                EmergencyCareSearchResult(name: "A", address: nil, locality: nil, latitude: 39.4700, longitude: -0.3760, ownershipHint: nil),
                EmergencyCareSearchResult(name: "B", address: nil, locality: nil, latitude: 39.4710, longitude: -0.3770, ownershipHint: nil),
                EmergencyCareSearchResult(name: "C", address: nil, locality: nil, latitude: 39.4720, longitude: -0.3780, ownershipHint: nil),
                EmergencyCareSearchResult(name: "D", address: nil, locality: nil, latitude: 39.4900, longitude: -0.3900, ownershipHint: nil)
            ],
            origin: CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763),
            maximumResults: 3
        )

        #expect(hospitals.map(\.name) == ["A", "B", "C"])
    }

    @Test
    func providerCachesAutomaticRefreshUntilMovementThresholdIsExceeded() async throws {
        let searcher = RecordingEmergencyCareSearcher()
        let provider = LiveEmergencyCareProvider(searcher: searcher, ttl: 900, cacheDistanceMeters: 500)
        let firstRequest = EmergencyCareSearchRequest(
            coordinate: CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763)
        )
        let secondRequest = EmergencyCareSearchRequest(
            coordinate: CLLocationCoordinate2D(latitude: 39.4759, longitude: -0.3763)
        )

        _ = try await provider.nearbyHospitals(for: firstRequest, forceRefresh: false)
        _ = try await provider.nearbyHospitals(for: firstRequest, forceRefresh: false)
        #expect(await searcher.callCount() == 1)

        _ = try await provider.nearbyHospitals(for: secondRequest, forceRefresh: false)
        #expect(await searcher.callCount() == 2)
    }

    @Test
    func providerForceRefreshBypassesCache() async throws {
        let searcher = RecordingEmergencyCareSearcher()
        let provider = LiveEmergencyCareProvider(searcher: searcher, ttl: 900, cacheDistanceMeters: 500)
        let request = EmergencyCareSearchRequest(
            coordinate: CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763)
        )

        _ = try await provider.nearbyHospitals(for: request, forceRefresh: false)
        _ = try await provider.nearbyHospitals(for: request, forceRefresh: true)

        #expect(await searcher.callCount() == 2)
    }

    @Test
    func providerReturnsNoHospitalsFoundWhenSearchYieldsNoValidCoordinates() async throws {
        let searcher = StaticEmergencyCareSearcher(results: [
            EmergencyCareSearchResult(
                name: "Broken Hospital",
                address: "Street 1",
                locality: "Valencia",
                latitude: 190,
                longitude: -500,
                ownershipHint: nil
            )
        ])
        let provider = LiveEmergencyCareProvider(searcher: searcher, ttl: 900, cacheDistanceMeters: 500)

        let snapshot = try await provider.nearbyHospitals(
            for: EmergencyCareSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 39.4699, longitude: -0.3763)
            ),
            forceRefresh: false
        )

        #expect(snapshot.status == .noHospitalsFound)
        #expect(snapshot.hospitals.isEmpty)
    }

    @Test
    func providerExpandsSearchRadiusUntilItFindsPreferredThreeHospitals() async throws {
        let searcher = RadiusAwareEmergencyCareSearcher(resultsByRadiusKilometers: [
            25: [
                EmergencyCareSearchResult(
                    name: "Hospital Quironsalud Torrevieja",
                    address: "Partida de La Loma",
                    locality: "Torrevieja",
                    latitude: 37.9820,
                    longitude: -0.6750,
                    ownershipHint: nil
                )
            ],
            50: [
                EmergencyCareSearchResult(
                    name: "Hospital Quironsalud Torrevieja",
                    address: "Partida de La Loma",
                    locality: "Torrevieja",
                    latitude: 37.9820,
                    longitude: -0.6750,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital Vega Baja",
                    address: "Calle de Orihuela",
                    locality: "Orihuela",
                    latitude: 38.0850,
                    longitude: -0.9440,
                    ownershipHint: nil
                )
            ],
            100: [
                EmergencyCareSearchResult(
                    name: "Hospital Quironsalud Torrevieja",
                    address: "Partida de La Loma",
                    locality: "Torrevieja",
                    latitude: 37.9820,
                    longitude: -0.6750,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital Vega Baja",
                    address: "Calle de Orihuela",
                    locality: "Orihuela",
                    latitude: 38.0850,
                    longitude: -0.9440,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital General Universitario de Alicante",
                    address: "Pintor Baeza",
                    locality: "Alicante",
                    latitude: 38.3615,
                    longitude: -0.4818,
                    ownershipHint: "Hospital Publico"
                )
            ]
        ])
        let provider = LiveEmergencyCareProvider(searcher: searcher, ttl: 900, cacheDistanceMeters: 500)

        let snapshot = try await provider.nearbyHospitals(
            for: EmergencyCareSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 37.9780, longitude: -0.6820)
            ),
            forceRefresh: false
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.hospitals.count == 3)
        #expect(snapshot.searchRadiusKilometers == 100)
        #expect(snapshot.detail == "Nearby emergency hospitals within 100 km.")
        #expect(await searcher.requestedRadiiKilometers() == [25, 50, 100])
    }

    @Test
    func providerStopsExpandingAfterFiftyKilometersWhenPreferredCountIsReached() async throws {
        let searcher = RadiusAwareEmergencyCareSearcher(resultsByRadiusKilometers: [
            25: [
                EmergencyCareSearchResult(
                    name: "Hospital Quironsalud Torrevieja",
                    address: "Partida de La Loma",
                    locality: "Torrevieja",
                    latitude: 37.9820,
                    longitude: -0.6750,
                    ownershipHint: nil
                )
            ],
            50: [
                EmergencyCareSearchResult(
                    name: "Hospital Quironsalud Torrevieja",
                    address: "Partida de La Loma",
                    locality: "Torrevieja",
                    latitude: 37.9820,
                    longitude: -0.6750,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital Vega Baja",
                    address: "Calle de Orihuela",
                    locality: "Orihuela",
                    latitude: 38.0850,
                    longitude: -0.9440,
                    ownershipHint: nil
                ),
                EmergencyCareSearchResult(
                    name: "Hospital General Universitario de Elche",
                    address: "Camino de l'Almazara",
                    locality: "Elche",
                    latitude: 38.2681,
                    longitude: -0.6990,
                    ownershipHint: "Hospital Publico"
                )
            ]
        ])
        let provider = LiveEmergencyCareProvider(searcher: searcher, ttl: 900, cacheDistanceMeters: 500)

        let snapshot = try await provider.nearbyHospitals(
            for: EmergencyCareSearchRequest(
                coordinate: CLLocationCoordinate2D(latitude: 37.9780, longitude: -0.6820)
            ),
            forceRefresh: false
        )

        #expect(snapshot.hospitals.count == 3)
        #expect(snapshot.searchRadiusKilometers == 50)
        #expect(await searcher.requestedRadiiKilometers() == [25, 50])
    }
}

private actor RecordingEmergencyCareSearcher: EmergencyCareSearchPerforming {
    private var calls = 0

    func nearbyHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async throws -> [EmergencyCareSearchResult] {
        calls += 1
        return [
            EmergencyCareSearchResult(
                name: "Hospital Public de Valencia",
                address: "Street 1",
                locality: "Valencia",
                latitude: coordinate.latitude + 0.002,
                longitude: coordinate.longitude + 0.002,
                ownershipHint: nil
            ),
            EmergencyCareSearchResult(
                name: "Hospital Privado Burjassot",
                address: "Street 2",
                locality: "Burjassot",
                latitude: coordinate.latitude + 0.004,
                longitude: coordinate.longitude + 0.004,
                ownershipHint: nil
            ),
            EmergencyCareSearchResult(
                name: "Hospital Casa de Salut",
                address: "Street 3",
                locality: "Valencia",
                latitude: coordinate.latitude + 0.001,
                longitude: coordinate.longitude + 0.001,
                ownershipHint: nil
            )
        ]
    }

    func callCount() -> Int {
        calls
    }
}

private actor RadiusAwareEmergencyCareSearcher: EmergencyCareSearchPerforming {
    private let resultsByRadiusKilometers: [Int: [EmergencyCareSearchResult]]
    private var requestedRadii: [Int] = []

    init(resultsByRadiusKilometers: [Int: [EmergencyCareSearchResult]]) {
        self.resultsByRadiusKilometers = resultsByRadiusKilometers
    }

    func nearbyHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async throws -> [EmergencyCareSearchResult] {
        let radiusKilometers = Int((radiusMeters / 1_000).rounded())
        requestedRadii.append(radiusKilometers)
        return resultsByRadiusKilometers[radiusKilometers] ?? []
    }

    func requestedRadiiKilometers() -> [Int] {
        requestedRadii
    }
}

private struct StaticEmergencyCareSearcher: EmergencyCareSearchPerforming {
    let results: [EmergencyCareSearchResult]

    func nearbyHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async throws -> [EmergencyCareSearchResult] {
        results
    }
}
