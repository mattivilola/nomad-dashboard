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
    enum SourceKind: Int, Sendable {
        case text = 0
        case pointsOfInterest = 1
    }

    let name: String
    let address: String?
    let locality: String?
    let latitude: Double
    let longitude: Double
    let ownershipHint: String?
    let sourceKind: SourceKind

    init(
        name: String,
        address: String?,
        locality: String?,
        latitude: Double,
        longitude: Double,
        ownershipHint: String?,
        sourceKind: SourceKind = .pointsOfInterest
    ) {
        self.name = name
        self.address = address
        self.locality = locality
        self.latitude = latitude
        self.longitude = longitude
        self.ownershipHint = ownershipHint
        self.sourceKind = sourceKind
    }

    func withSourceKind(_ sourceKind: SourceKind) -> EmergencyCareSearchResult {
        EmergencyCareSearchResult(
            name: name,
            address: address,
            locality: locality,
            latitude: latitude,
            longitude: longitude,
            ownershipHint: ownershipHint,
            sourceKind: sourceKind
        )
    }
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

private enum EmergencyCareBroaderSearchDisposition {
    case accepted
    case rejected(reason: String)
}

public actor LiveEmergencyCareProvider: EmergencyCareProvider {
    private static let fallbackSearchRadiiKilometers: [Double] = [50, 100]
    private static let minimumFallbackResults = 2
    private static let preferredFallbackResults = 3
    private static let fallbackTextQueries = ["hospital", "emergency room", "urgent care", "urgencias", "emergencias"]
    private static let broaderSearchKeywords = ["hospital", "emergency", "emergency room", "urgent care", "urgencias", "emergencias"]
    private static let excludedBroaderSearchKeywords = ["veterin", "veterinary", "animal", "pet", "mascota"]
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
                ).map { $0.withSourceKind(.pointsOfInterest) }
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
                    maximumResults: request.maximumResults,
                    onDiscardedResult: Self.logDiscardedSearchResult
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
                        ).map { $0.withSourceKind(.text) }
                        lastSuccessfulRadiusKilometers = radiusKilometers
                        hadSuccessfulTextSearch = true
                        rawTextResultCount += rawResults.count

                        let acceptedResults = acceptedBroaderSearchResults(
                            within: radiusKilometers,
                            from: rawResults,
                            origin: request.coordinate,
                            query: query
                        )
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
                    maximumResults: request.maximumResults,
                    onDiscardedResult: Self.logDiscardedSearchResult
                )
                logSearchSuccess(
                    mode: .text,
                    radiusKilometers: radiusKilometers,
                    query: nil,
                    rawResultCount: rawTextResultCount + (pointOfInterestResultsByRadius[radiusKilometers]?.count ?? 0),
                    acceptedResultCount: acceptedTextResultCount + (pointOfInterestResultsByRadius[radiusKilometers]?.count ?? 0),
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

    private func acceptedBroaderSearchResults(
        within radiusKilometers: Double,
        from rawResults: [EmergencyCareSearchResult],
        origin: CLLocationCoordinate2D,
        query: String
    ) -> [EmergencyCareSearchResult] {
        let inRadiusResults = searchResults(
            within: radiusKilometers,
            from: rawResults,
            origin: origin
        )

        return inRadiusResults.filter { result in
            switch Self.broaderSearchDisposition(for: result) {
            case .accepted:
                return true
            case let .rejected(reason):
                Self.logBroaderResultRejection(
                    result,
                    radiusKilometers: radiusKilometers,
                    query: query,
                    reason: reason
                )
                return false
            }
        }
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

    private static func broaderSearchDisposition(for result: EmergencyCareSearchResult) -> EmergencyCareBroaderSearchDisposition {
        let haystack = [result.name, result.ownershipHint]
            .compactMap(\.self)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if excludedBroaderSearchKeywords.contains(where: { haystack.contains($0) }) {
            return .rejected(reason: "non_human_facility")
        }

        if broaderSearchKeywords.contains(where: { haystack.contains($0) }) == false {
            return .rejected(reason: "not_emergency_relevant")
        }

        return .accepted
    }

    private static func logBroaderResultRejection(
        _ result: EmergencyCareSearchResult,
        radiusKilometers: Double,
        query: String,
        reason: String
    ) {
        logger.info(
            "Emergency care broader result rejected reason=\(reason, privacy: .public) query=\(query, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public) name=\(result.name, privacy: .public)"
        )
    }

    private static func logDiscardedSearchResult(
        _ result: EmergencyCareSearchResult,
        reason: String
    ) {
        logger.info(
            "Emergency care candidate discarded reason=\(reason, privacy: .public) source=\(String(result.sourceKind.rawValue), privacy: .public) name=\(result.name, privacy: .public)"
        )
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
    maximumResults: Int,
    onDiscardedResult: ((EmergencyCareSearchResult, String) -> Void)? = nil
) -> [EmergencyHospital] {
    let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
    let sortedHospitals = deduplicatedEmergencyHospitalResults(
        searchResults,
        onDiscardedResult: onDiscardedResult
    )
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
    _ searchResults: [EmergencyCareSearchResult],
    onDiscardedResult: ((EmergencyCareSearchResult, String) -> Void)? = nil
) -> [EmergencyCareSearchResult] {
    var bestByExactKey: [String: EmergencyCareSearchResult] = [:]

    for result in searchResults {
        let key = exactEmergencyHospitalKey(for: result)
        guard let existing = bestByExactKey[key] else {
            bestByExactKey[key] = result
            continue
        }

        let preferred = preferredEmergencyHospitalDuplicate(existing, result)
        if preferred == existing {
            onDiscardedResult?(result, "duplicate_exact_existing_preferred")
        } else {
            onDiscardedResult?(existing, "duplicate_exact_replaced_with_better_candidate")
            bestByExactKey[key] = result
        }
    }

    let exactDeduplicated = bestByExactKey.values.sorted(by: preferredEmergencyHospitalOrdering)
    var deduplicated: [EmergencyCareSearchResult] = []

    for result in exactDeduplicated {
        guard let duplicateIndex = deduplicated.firstIndex(where: { areNearbyAliasDuplicates($0, result) }) else {
            deduplicated.append(result)
            continue
        }

        let existing = deduplicated[duplicateIndex]
        let preferred = preferredEmergencyHospitalDuplicate(existing, result)
        if preferred == existing {
            onDiscardedResult?(result, "duplicate_alias_existing_preferred")
        } else {
            onDiscardedResult?(existing, "duplicate_alias_replaced_with_better_candidate")
            deduplicated[duplicateIndex] = result
        }
    }

    return deduplicated
}

private func exactEmergencyHospitalKey(for result: EmergencyCareSearchResult) -> String {
    [
        normalizedHospitalValue(result.name),
        roundedCoordinateText(result.latitude),
        roundedCoordinateText(result.longitude)
    ].joined(separator: "|")
}

private func normalizedHospitalValue(_ value: String?) -> String {
    normalizedHospitalTokens(from: value).joined(separator: " ")
}

private func preferredEmergencyHospitalOrdering(
    _ lhs: EmergencyCareSearchResult,
    _ rhs: EmergencyCareSearchResult
) -> Bool {
    preferredEmergencyHospitalDuplicate(lhs, rhs) == lhs
}

private func preferredEmergencyHospitalDuplicate(
    _ lhs: EmergencyCareSearchResult,
    _ rhs: EmergencyCareSearchResult
) -> EmergencyCareSearchResult {
    let lhsSpecificity = emergencyHospitalSpecificityScore(lhs)
    let rhsSpecificity = emergencyHospitalSpecificityScore(rhs)
    if lhsSpecificity != rhsSpecificity {
        return lhsSpecificity > rhsSpecificity ? lhs : rhs
    }

    if lhs.sourceKind != rhs.sourceKind {
        return lhs.sourceKind.rawValue > rhs.sourceKind.rawValue ? lhs : rhs
    }

    if lhs.name.count != rhs.name.count {
        return lhs.name.count > rhs.name.count ? lhs : rhs
    }

    return lhs
}

private func emergencyHospitalSpecificityScore(_ result: EmergencyCareSearchResult) -> Int {
    let informativeNameTokens = informativeHospitalTokens(for: result)
    var score = informativeNameTokens.count * 4
    score += normalizedHospitalTokens(from: result.name).count

    if let address = result.address, address.isEmpty == false {
        score += 6
    }

    if let locality = result.locality, locality.isEmpty == false {
        score += 2
    }

    if let ownershipHint = result.ownershipHint, ownershipHint.isEmpty == false {
        score += 1
    }

    return score
}

private func areNearbyAliasDuplicates(
    _ lhs: EmergencyCareSearchResult,
    _ rhs: EmergencyCareSearchResult
) -> Bool {
    let lhsFingerprint = aliasFingerprint(for: lhs)
    let rhsFingerprint = aliasFingerprint(for: rhs)
    guard lhsFingerprint.isEmpty == false, lhsFingerprint == rhsFingerprint else {
        return false
    }

    let lhsLocation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
    let rhsLocation = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
    return lhsLocation.distance(from: rhsLocation) <= 500
}

private func aliasFingerprint(for result: EmergencyCareSearchResult) -> String {
    let localityTokens = Set(normalizedHospitalTokens(from: result.locality))
    let informativeTokens = informativeHospitalTokens(for: result).filter { localityTokens.contains($0) == false }
    if informativeTokens.isEmpty == false {
        return informativeTokens.joined(separator: " ")
    }

    return normalizedHospitalTokens(from: result.name)
        .filter { emergencyHospitalNoiseTokens.contains($0) == false }
        .joined(separator: " ")
}

private func informativeHospitalTokens(for result: EmergencyCareSearchResult) -> [String] {
    normalizedHospitalTokens(from: result.name)
        .filter { emergencyHospitalNoiseTokens.contains($0) == false }
}

private let emergencyHospitalNoiseTokens: Set<String> = [
    "hospital", "de", "del", "la", "el", "los", "las", "y", "i",
    "centro", "centre", "medical", "medico", "sanitario", "clinic", "clinica"
]

private func normalizedHospitalTokens(from value: String?) -> [String] {
    guard let value else {
        return []
    }

    return value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .replacingOccurrences(of: "quironsalud", with: "quiron")
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.isEmpty == false }
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
