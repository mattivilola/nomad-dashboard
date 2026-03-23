import CoreLocation
import Foundation
import MapKit

private struct CachedEmergencyCareResult {
    let request: EmergencyCareSearchRequest
    let snapshot: EmergencyCareSnapshot
}

protocol EmergencyCareSearchPerforming: Sendable {
    func nearbyHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async throws -> [EmergencyCareSearchResult]
}

struct EmergencyCareSearchResult: Equatable, Sendable {
    let name: String
    let address: String?
    let locality: String?
    let latitude: Double
    let longitude: Double
    let ownershipHint: String?
}

public actor LiveEmergencyCareProvider: EmergencyCareProvider {
    private let searcher: any EmergencyCareSearchPerforming
    private let ttl: TimeInterval
    private let cacheDistanceMeters: CLLocationDistance
    private var cachedResult: CachedEmergencyCareResult?

    public init(
        ttl: TimeInterval = 900,
        cacheDistanceMeters: CLLocationDistance = 500
    ) {
        self.init(
            searcher: AppleMapsEmergencyCareSearchClient(),
            ttl: ttl,
            cacheDistanceMeters: cacheDistanceMeters
        )
    }

    init(
        searcher: any EmergencyCareSearchPerforming,
        ttl: TimeInterval = 900,
        cacheDistanceMeters: CLLocationDistance = 500
    ) {
        self.searcher = searcher
        self.ttl = ttl
        self.cacheDistanceMeters = cacheDistanceMeters
    }

    public func nearbyHospitals(
        for request: EmergencyCareSearchRequest,
        forceRefresh: Bool
    ) async throws -> EmergencyCareSnapshot {
        if forceRefresh == false,
           let cachedResult,
           cachedResult.request.maximumResults == request.maximumResults,
           cachedResult.request.searchRadiusKilometers == request.searchRadiusKilometers,
           abs(cachedResult.snapshot.fetchedAt?.timeIntervalSinceNow ?? ttl + 1) < ttl,
           Self.distanceMeters(from: cachedResult.request.coordinate, to: request.coordinate) < cacheDistanceMeters
        {
            return cachedResult.snapshot
        }

        let searchResults = try await searcher.nearbyHospitalResults(
            near: request.coordinate,
            radiusMeters: request.searchRadiusKilometers * 1_000
        )
        let hospitals = selectEmergencyHospitals(
            from: searchResults,
            origin: request.coordinate,
            maximumResults: request.maximumResults
        )

        let snapshot = EmergencyCareSnapshot(
            status: hospitals.isEmpty ? .noHospitalsFound : .ready,
            sourceName: "Apple Maps",
            sourceURL: URL(string: "https://maps.apple.com"),
            searchRadiusKilometers: request.searchRadiusKilometers,
            hospitals: hospitals,
            fetchedAt: Date(),
            detail: hospitals.isEmpty ? "No nearby emergency hospitals were found." : "Nearby emergency hospitals within \(Int(request.searchRadiusKilometers)) km."
        )
        cachedResult = CachedEmergencyCareResult(request: request, snapshot: snapshot)
        return snapshot
    }

    private static func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}

func classifyHospitalOwnership(name: String, ownershipHint: String?) -> HospitalOwnership {
    let haystack = [name, ownershipHint]
        .compactMap(\.self)
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

    let publicKeywords = ["public", "publique", "pubblico", "publico", "publica", "public hospital"]
    if publicKeywords.contains(where: { haystack.contains($0) }) {
        return .public
    }

    let privateKeywords = ["private", "privat", "privee", "privada", "privado", "privato"]
    if privateKeywords.contains(where: { haystack.contains($0) }) {
        return .private
    }

    return .unknown
}

func selectEmergencyHospitals(
    from searchResults: [EmergencyCareSearchResult],
    origin: CLLocationCoordinate2D,
    maximumResults: Int
) -> [EmergencyHospital] {
    let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
    let sortedHospitals = deduplicatedEmergencyHospitalResults(searchResults)
        .compactMap { result -> EmergencyHospital? in
            let coordinate = CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                return nil
            }

            let ownership = classifyHospitalOwnership(name: result.name, ownershipHint: result.ownershipHint)
            let distanceKilometers = originLocation.distance(from: CLLocation(latitude: result.latitude, longitude: result.longitude)) / 1_000
            return EmergencyHospital(
                name: result.name,
                address: result.address,
                locality: result.locality,
                distanceKilometers: distanceKilometers,
                latitude: result.latitude,
                longitude: result.longitude,
                ownership: ownership
            )
        }
        .sorted { lhs, rhs in
            lhs.distanceKilometers < rhs.distanceKilometers
        }

    guard maximumResults > 0 else {
        return []
    }

    guard let nearestPublic = sortedHospitals.first(where: { $0.ownership == .public }),
          let nearestPrivate = sortedHospitals.first(where: { $0.ownership == .private })
    else {
        return Array(sortedHospitals.prefix(maximumResults))
    }

    var selectedIDs: Set<String> = [nearestPublic.id, nearestPrivate.id]
    var hospitals: [EmergencyHospital] = [nearestPublic]

    if nearestPrivate.id != nearestPublic.id {
        hospitals.append(nearestPrivate)
    }

    for hospital in sortedHospitals where hospitals.count < maximumResults {
        guard selectedIDs.contains(hospital.id) == false else {
            continue
        }
        selectedIDs.insert(hospital.id)
        hospitals.append(hospital)
    }

    return hospitals
}

private func deduplicatedEmergencyHospitalResults(
    _ searchResults: [EmergencyCareSearchResult]
) -> [EmergencyCareSearchResult] {
    var seen: Set<String> = []

    return searchResults.filter { result in
        let key = [
            normalizedHospitalValue(result.name),
            roundedCoordinateText(result.latitude),
            roundedCoordinateText(result.longitude)
        ].joined(separator: "|")
        return seen.insert(key).inserted
    }
}

private func normalizedHospitalValue(_ value: String?) -> String {
    guard let value else {
        return ""
    }

    return value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { $0.isEmpty == false }
        .joined(separator: " ")
}

private func roundedCoordinateText(_ value: Double) -> String {
    String(format: "%.4f", value)
}

private final class AppleMapsEmergencyCareSearchClient: EmergencyCareSearchPerforming {
    func nearbyHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async throws -> [EmergencyCareSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radiusMeters)
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hospital])

                let search = MKLocalSearch(request: request)
                search.start { response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let results = response?.mapItems.compactMap(Self.searchResult(from:)) ?? []
                    continuation.resume(returning: results)
                }
            }
        }
    }

    private static func searchResult(from mapItem: MKMapItem) -> EmergencyCareSearchResult? {
        guard let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              name.isEmpty == false
        else {
            return nil
        }

        let coordinate = mapItem.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        let address = [mapItem.placemark.subThoroughfare, mapItem.placemark.thoroughfare]
            .compactMap(\.self)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let addressValue = address.isEmpty ? nil : address

        return EmergencyCareSearchResult(
            name: name,
            address: addressValue,
            locality: mapItem.placemark.locality,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            ownershipHint: mapItem.placemark.title
        )
    }
}
