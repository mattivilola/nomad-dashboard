import CoreLocation
import Foundation
import MapKit
import OSLog

private struct CachedEmergencyCareResult {
    let request: EmergencyCareSearchRequest
    let snapshot: EmergencyCareSnapshot
}

protocol EmergencyCareSearchPerforming: Sendable {
    func nearbyHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async throws -> [EmergencyCareSearchResult]

    func broaderHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        query: String
    ) async throws -> [EmergencyCareSearchResult]
}

extension EmergencyCareSearchPerforming {
    func broaderHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        query: String
    ) async throws -> [EmergencyCareSearchResult] {
        []
    }
}

struct EmergencyCareSearchResult: Equatable, Sendable {
    let name: String
    let address: String?
    let locality: String?
    let latitude: Double
    let longitude: Double
    let ownershipHint: String?
}

private enum EmergencyCareSearchMode: String {
    case pointsOfInterest = "poi"
    case text
}

private struct EmergencyCareSearchCandidate {
    let hospitals: [EmergencyHospital]
    let radiusKilometers: Double
    let totalDistanceKilometers: Double
}

public actor LiveEmergencyCareProvider: EmergencyCareProvider {
    private static let fallbackSearchRadiiKilometers: [Double] = [50, 100]
    private static let minimumFallbackResults = 2
    private static let preferredFallbackResults = 3
    private static let fallbackTextQueries = ["hospital", "emergency room", "urgent care", "urgencias", "emergencias"]
    private static let broaderSearchKeywords = ["hospital", "emergency", "emergency room", "urgent care", "urgencias", "emergencias"]
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
        category: "EmergencyCare"
    )

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

        let expandedSearch = try await expandedHospitalSearch(for: request)
        let hospitals = expandedSearch.hospitals

        let snapshot = EmergencyCareSnapshot(
            status: hospitals.isEmpty ? .noHospitalsFound : .ready,
            sourceName: "Apple Maps",
            sourceURL: URL(string: "https://maps.apple.com"),
            searchRadiusKilometers: expandedSearch.radiusKilometers,
            hospitals: hospitals,
            fetchedAt: Date(),
            detail: hospitals.isEmpty ? "No nearby emergency hospitals were found." : "Nearby emergency hospitals within \(Int(expandedSearch.radiusKilometers)) km."
        )
        cachedResult = CachedEmergencyCareResult(request: request, snapshot: snapshot)
        return snapshot
    }

    private static func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func expandedHospitalSearch(
        for request: EmergencyCareSearchRequest
    ) async throws -> (hospitals: [EmergencyHospital], radiusKilometers: Double) {
        let searchRadii = Self.searchRadii(startingAt: request.searchRadiusKilometers)
        let minimumResults = min(Self.minimumFallbackResults, request.maximumResults)
        let preferredResults = min(Self.preferredFallbackResults, request.maximumResults)
        var bestCandidate: EmergencyCareSearchCandidate?
        var pointOfInterestResultsByRadius: [Double: [EmergencyCareSearchResult]] = [:]
        var firstBroaderFallbackRadius: Double?
        var lastSuccessfulRadiusKilometers: Double?
        var lastError: Error?

        for radiusKilometers in searchRadii {
            do {
                let rawResults = try await searcher.nearbyHospitalResults(
                    near: request.coordinate,
                    radiusMeters: radiusKilometers * 1_000
                )
                lastSuccessfulRadiusKilometers = radiusKilometers
                let radiusScopedResults = searchResults(
                    within: radiusKilometers,
                    from: rawResults,
                    origin: request.coordinate
                )
                pointOfInterestResultsByRadius[radiusKilometers] = radiusScopedResults
                let hospitals = selectEmergencyHospitals(
                    from: radiusScopedResults,
                    origin: request.coordinate,
                    maximumResults: request.maximumResults
                )
                logSearchSuccess(
                    mode: .pointsOfInterest,
                    radiusKilometers: radiusKilometers,
                    query: nil,
                    rawResultCount: rawResults.count,
                    acceptedResultCount: radiusScopedResults.count,
                    displayedCount: hospitals.count
                )
                bestCandidate = betterCandidate(
                    current: bestCandidate,
                    hospitals: hospitals,
                    radiusKilometers: radiusKilometers
                )

                if hospitals.count >= preferredResults {
                    return (hospitals, radiusKilometers)
                }

                if hospitals.count < preferredResults, firstBroaderFallbackRadius == nil {
                    firstBroaderFallbackRadius = radiusKilometers
                }
            } catch {
                lastError = error
                logSearchFailure(
                    mode: .pointsOfInterest,
                    radiusKilometers: radiusKilometers,
                    query: nil,
                    error: error
                )
                if firstBroaderFallbackRadius == nil {
                    firstBroaderFallbackRadius = radiusKilometers
                }
                continue
            }
        }

        if let firstBroaderFallbackRadius,
           let startIndex = searchRadii.firstIndex(of: firstBroaderFallbackRadius)
        {
            for radiusKilometers in searchRadii[startIndex...] {
                var combinedResults = pointOfInterestResultsByRadius[radiusKilometers] ?? []
                var rawTextResultCount = 0
                var acceptedTextResultCount = 0
                var hadSuccessfulTextSearch = false

                for query in Self.fallbackTextQueries {
                    do {
                        let rawResults = try await searcher.broaderHospitalResults(
                            near: request.coordinate,
                            radiusMeters: radiusKilometers * 1_000,
                            query: query
                        )
                        lastSuccessfulRadiusKilometers = radiusKilometers
                        hadSuccessfulTextSearch = true
                        rawTextResultCount += rawResults.count

                        let acceptedResults = searchResults(
                            within: radiusKilometers,
                            from: rawResults,
                            origin: request.coordinate
                        ).filter(Self.isBroaderEmergencyCareMatch)
                        acceptedTextResultCount += acceptedResults.count
                        combinedResults.append(contentsOf: acceptedResults)
                    } catch {
                        lastError = error
                        logSearchFailure(
                            mode: .text,
                            radiusKilometers: radiusKilometers,
                            query: query,
                            error: error
                        )
                    }
                }

                guard hadSuccessfulTextSearch else {
                    continue
                }

                let hospitals = selectEmergencyHospitals(
                    from: combinedResults,
                    origin: request.coordinate,
                    maximumResults: request.maximumResults
                )
                logSearchSuccess(
                    mode: .text,
                    radiusKilometers: radiusKilometers,
                    query: nil,
                    rawResultCount: rawTextResultCount + (pointOfInterestResultsByRadius[radiusKilometers]?.count ?? 0),
                    acceptedResultCount: combinedResults.count,
                    displayedCount: hospitals.count
                )
                bestCandidate = betterCandidate(
                    current: bestCandidate,
                    hospitals: hospitals,
                    radiusKilometers: radiusKilometers
                )

                if hospitals.count >= preferredResults {
                    return (hospitals, radiusKilometers)
                }
            }
        }

        guard let lastSuccessfulRadiusKilometers else {
            throw lastError ?? CocoaError(.fileReadUnknown)
        }

        if let bestCandidate {
            if bestCandidate.hospitals.count >= minimumResults {
                return (bestCandidate.hospitals, bestCandidate.radiusKilometers)
            }

            if bestCandidate.hospitals.isEmpty == false {
                return (bestCandidate.hospitals, bestCandidate.radiusKilometers)
            }
        }

        if minimumResults > 0 {
            return ([], lastSuccessfulRadiusKilometers)
        }
        return ([], request.searchRadiusKilometers)
    }

    private static func searchRadii(startingAt requestedRadiusKilometers: Double) -> [Double] {
        [requestedRadiusKilometers] + fallbackSearchRadiiKilometers.filter { $0 > requestedRadiusKilometers }
    }

    private func betterCandidate(
        current: EmergencyCareSearchCandidate?,
        hospitals: [EmergencyHospital],
        radiusKilometers: Double
    ) -> EmergencyCareSearchCandidate? {
        guard hospitals.isEmpty == false else {
            return current
        }

        let candidate = EmergencyCareSearchCandidate(
            hospitals: hospitals,
            radiusKilometers: radiusKilometers,
            totalDistanceKilometers: hospitals.reduce(0) { $0 + $1.distanceKilometers }
        )

        guard let current else {
            return candidate
        }

        if candidate.hospitals.count > current.hospitals.count {
            return candidate
        }

        if candidate.hospitals.count < current.hospitals.count {
            return current
        }

        if candidate.radiusKilometers < current.radiusKilometers {
            return candidate
        }

        if candidate.radiusKilometers > current.radiusKilometers {
            return current
        }

        if candidate.totalDistanceKilometers < current.totalDistanceKilometers {
            return candidate
        }

        return current
    }

    private func searchResults(
        within radiusKilometers: Double,
        from searchResults: [EmergencyCareSearchResult],
        origin: CLLocationCoordinate2D
    ) -> [EmergencyCareSearchResult] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let radiusMeters = radiusKilometers * 1_000

        return searchResults.filter { result in
            let coordinate = CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                return false
            }

            let location = CLLocation(latitude: result.latitude, longitude: result.longitude)
            return originLocation.distance(from: location) <= radiusMeters
        }
    }

    private static func isBroaderEmergencyCareMatch(_ result: EmergencyCareSearchResult) -> Bool {
        let haystack = [result.name, result.ownershipHint]
            .compactMap(\.self)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return broaderSearchKeywords.contains(where: { haystack.contains($0) })
    }

    private func logSearchSuccess(
        mode: EmergencyCareSearchMode,
        radiusKilometers: Double,
        query: String?,
        rawResultCount: Int,
        acceptedResultCount: Int,
        displayedCount: Int
    ) {
        if let query {
            Self.logger.info(
                "Emergency care search mode=\(mode.rawValue, privacy: .public) query=\(query, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public) raw=\(rawResultCount, privacy: .public) accepted=\(acceptedResultCount, privacy: .public) displayed=\(displayedCount, privacy: .public)"
            )
        } else {
            Self.logger.info(
                "Emergency care search mode=\(mode.rawValue, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public) raw=\(rawResultCount, privacy: .public) accepted=\(acceptedResultCount, privacy: .public) displayed=\(displayedCount, privacy: .public)"
            )
        }
    }

    private func logSearchFailure(
        mode: EmergencyCareSearchMode,
        radiusKilometers: Double,
        query: String?,
        error: Error
    ) {
        let description = String(describing: error)
        if let query {
            Self.logger.error(
                "Emergency care search failed mode=\(mode.rawValue, privacy: .public) query=\(query, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public) error=\(description, privacy: .public)"
            )
        } else {
            Self.logger.error(
                "Emergency care search failed mode=\(mode.rawValue, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public) error=\(description, privacy: .public)"
            )
        }
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

    func broaderHospitalResults(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        query: String
    ) async throws -> [EmergencyCareSearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: radiusMeters * 2,
                    longitudinalMeters: radiusMeters * 2
                )

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
