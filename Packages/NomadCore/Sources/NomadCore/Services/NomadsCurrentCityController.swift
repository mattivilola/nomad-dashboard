import Combine
import Foundation

@MainActor
public final class NomadsCurrentCityController: ObservableObject {
    public enum State: Equatable, Sendable {
        case waitingForLocation
        case disabled
        case loading
        case matched
        case notFound
        case unavailable
    }

    public struct Match: Codable, Sendable, Hashable {
        public let directoryCity: NomadsDirectoryCity
        public let distanceKilometers: Double?
        public let isNearby: Bool

        public init(directoryCity: NomadsDirectoryCity, distanceKilometers: Double?, isNearby: Bool) {
            self.directoryCity = directoryCity
            self.distanceKilometers = distanceKilometers
            self.isNearby = isNearby
        }
    }

    @Published public private(set) var state: State = .waitingForLocation
    @Published public private(set) var currentLocationName: String?
    @Published public private(set) var matchedCity: NomadsCity?
    @Published public private(set) var match: Match?
    @Published public private(set) var checkedAt: Date?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var directory: [NomadsDirectoryCity] = []

    @Published public var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: preferencesKey)
            guard enabled != oldValue else { return }
            if !enabled {
                generation &+= 1
                automaticTask?.cancel()
                automaticTask = nil
                lastIdentity = nil
                isLoading = false
                state = .disabled
                return
            }
            if let lastLocation {
                ingest(location: lastLocation)
            } else {
                state = .waitingForLocation
            }
        }
    }

    private let provider: NomadsCityProvider
    private let storageURL: URL
    private let preferencesKey: String
    private let defaults: UserDefaults
    private var lastLocation: IPLocationSnapshot?
    private var lastIdentity: LocationIdentity?
    private var generation = 0
    private var automaticTask: Task<Void, Never>?
    private var storageIsUnreadable = false
    private var storedResult: StoredResult?

    public init(provider: NomadsCityProvider, storageURL: URL, preferencesKey: String) {
        self.provider = provider
        self.storageURL = storageURL
        self.preferencesKey = preferencesKey
        defaults = .standard
        enabled = defaults.object(forKey: preferencesKey) as? Bool ?? true
        loadStoredData()
        if !enabled {
            state = .disabled
        }
    }

    deinit { automaticTask?.cancel() }

    public func ingest(location: IPLocationSnapshot?) {
        guard let location else { return }
        lastLocation = location
        let locationName = Self.locationName(for: location)
        if currentLocationName != locationName {
            currentLocationName = locationName
        }
        guard enabled else {
            state = .disabled
            return
        }
        guard let identity = LocationIdentity(location: location), identity.country != nil else {
            generation &+= 1
            automaticTask?.cancel()
            automaticTask = nil
            isLoading = false
            state = .waitingForLocation
            return
        }
        guard identity != lastIdentity else {
            if state == .waitingForLocation {
                if let storedResult, storedResult.identity == identity {
                    apply(storedResult)
                } else {
                    state = .unavailable
                    errorMessage = "The city check was interrupted. Choose Retry to check this city again."
                }
            }
            return
        }
        lastIdentity = identity
        generation &+= 1
        automaticTask?.cancel()
        automaticTask = nil

        if let storedResult, storedResult.identity == identity {
            apply(storedResult)
            return
        }
        beginAutomaticLookup(location: location, identity: identity, generation: generation)
    }

    public func retry() {
        guard enabled, let location = lastLocation, let identity = LocationIdentity(location: location), identity.country != nil else { return }
        lastIdentity = identity
        generation &+= 1
        automaticTask?.cancel()
        beginAutomaticLookup(location: location, identity: identity, generation: generation)
    }

    /// Loads the directory for an explicit city exploration action. It never starts a timer or refresh loop.
    public func loadDirectory() async {
        guard directory.isEmpty else { return }
        do {
            let result = try await provider.directory()
            directory = result
            persist()
        } catch {
            if state != .matched {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private func beginAutomaticLookup(location: IPLocationSnapshot, identity: LocationIdentity, generation: Int) {
        state = .loading
        isLoading = true
        errorMessage = storageIsUnreadable ? "Saved city matching data could not be read." : nil
        matchedCity = nil
        match = nil
        checkedAt = nil
        let provider = provider
        automaticTask = Task { [weak self] in
            do {
                let cities: [NomadsDirectoryCity] = if let self, !self.directory.isEmpty {
                    directory
                } else {
                    try await provider.directory()
                }
                try Task.checkCancellation()
                guard let self, isCurrent(identity: identity, generation: generation) else { return }
                directory = cities
                guard let candidate = Self.bestMatch(for: location, in: cities) else {
                    finish(.notFound, identity: identity, matchedCity: nil, match: nil, errorMessage: nil)
                    return
                }
                let city = try await provider.city(slug: candidate.directoryCity.slug)
                try Task.checkCancellation()
                guard isCurrent(identity: identity, generation: generation) else { return }
                finish(.matched, identity: identity, matchedCity: city, match: candidate, errorMessage: nil)
            } catch is CancellationError {
                return
            } catch {
                guard let self, isCurrent(identity: identity, generation: generation) else { return }
                finish(.unavailable, identity: identity, matchedCity: nil, match: nil, errorMessage: Self.message(for: error))
            }
        }
    }

    private func isCurrent(identity: LocationIdentity, generation: Int) -> Bool {
        enabled && lastIdentity == identity && self.generation == generation
    }

    private func finish(_ state: State, identity: LocationIdentity, matchedCity: NomadsCity?, match: Match?, errorMessage: String?) {
        guard isCurrent(identity: identity, generation: generation) else { return }
        self.state = state
        self.matchedCity = matchedCity
        self.match = match
        checkedAt = Date()
        self.errorMessage = errorMessage ?? (storageIsUnreadable ? "Saved city matching data could not be read." : nil)
        isLoading = false
        automaticTask = nil
        storedResult = StoredResult(identity: identity, state: state, matchedCity: matchedCity, match: match, checkedAt: checkedAt, errorMessage: errorMessage)
        persist()
    }

    private func apply(_ result: StoredResult) {
        state = result.state
        matchedCity = result.matchedCity
        match = result.match
        checkedAt = result.checkedAt
        errorMessage = result.errorMessage
        isLoading = false
    }

    private func loadStoredData() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let persisted = try JSONDecoder().decode(PersistedData.self, from: data)
            directory = persisted.directory
            storedResult = persisted.result
        } catch {
            storageIsUnreadable = true
            errorMessage = "Saved city matching data could not be read."
        }
    }

    private func persist() {
        guard !storageIsUnreadable else { return }
        do {
            let data = try JSONEncoder().encode(PersistedData(directory: directory, result: storedResult))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            errorMessage = "City matching data could not be saved."
        }
    }

    static func bestMatch(for location: IPLocationSnapshot, in cities: [NomadsDirectoryCity]) -> Match? {
        let cityName = normalized(location.city)
        let country = normalizedCountry(location.country, countryCode: location.countryCode)
        guard let country else { return nil }
        let countryCities = cities.filter { normalizedCountry($0.country, countryCode: nil) == country }
        if let cityName {
            let exact = countryCities.filter { normalized($0.name) == cityName }
            if exact.count == 1 {
                let candidate = exact[0]
                let distance = distance(from: location, to: candidate)
                if distance.map({ $0 <= 50 }) ?? true {
                    return Match(directoryCity: candidate, distanceKilometers: distance, isNearby: false)
                }
            }
        }
        guard let coordinate = coordinate(from: location) else { return nil }
        let nearby = countryCities.compactMap { city -> (NomadsDirectoryCity, Double)? in
            guard let distance = distance(from: coordinate, to: city), distance <= 50 else { return nil }
            return (city, distance)
        }.min { $0.1 < $1.1 }
        guard let nearby else { return nil }
        return Match(directoryCity: nearby.0, distanceKilometers: nearby.1, isNearby: true)
    }

    private static func locationName(for location: IPLocationSnapshot) -> String? {
        [location.city, location.country].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ").nilIfEmpty
    }

    fileprivate nonisolated static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let compact = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return compact.split(whereSeparator: \.isWhitespace).joined(separator: " ").nilIfEmpty
    }

    fileprivate nonisolated static func normalizedCountry(_ country: String?, countryCode: String?) -> String? {
        let raw: String? = if let code = countryCode?.uppercased(), code.count == 2 {
            Locale(identifier: "en_US").localizedString(forRegionCode: code)
        } else {
            country
        }
        guard let normalized = normalized(raw) else { return nil }
        return switch normalized {
        case "suomi": "finland"
        case "turkiye", "turkey": "turkey"
        case "czech republic", "czechia": "czechia"
        case "uk", "great britain", "united kingdom": "united kingdom"
        case "us", "usa", "united states of america", "united states": "united states"
        default: normalized
        }
    }

    private static func coordinate(from location: IPLocationSnapshot) -> (Double, Double)? {
        guard let latitude = location.latitude, let longitude = location.longitude,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        return (latitude, longitude)
    }

    private static func distance(from location: IPLocationSnapshot, to city: NomadsDirectoryCity) -> Double? {
        guard let coordinate = coordinate(from: location) else { return nil }
        return distance(from: coordinate, to: city)
    }

    private static func distance(from coordinate: (Double, Double), to city: NomadsDirectoryCity) -> Double? {
        guard let latitude = city.latitude, let longitude = city.longitude,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        let radians = Double.pi / 180
        let lat1 = coordinate.0 * radians
        let lat2 = latitude * radians
        let dLat = (latitude - coordinate.0) * radians
        let dLon = (longitude - coordinate.1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Nomads.com is unavailable right now."
    }
}

private struct LocationIdentity: Codable, Equatable, Sendable {
    let city: String
    let country: String?
    let region: String?

    init?(location: IPLocationSnapshot) {
        guard let city = NomadsCurrentCityController.normalized(location.city) else { return nil }
        self.city = city
        country = NomadsCurrentCityController.normalizedCountry(location.country, countryCode: location.countryCode)
        // Reverse-geocoding and IP providers often disagree about a region for the same city.
        // Retain it only when country identity is unavailable.
        region = country == nil ? NomadsCurrentCityController.normalized(location.region) : nil
    }
}

private struct StoredResult: Codable, Sendable {
    let identity: LocationIdentity
    let storedState: StoredState
    let matchedCity: NomadsCity?
    let match: NomadsCurrentCityController.Match?
    let checkedAt: Date?
    let errorMessage: String?

    init(identity: LocationIdentity, state: NomadsCurrentCityController.State, matchedCity: NomadsCity?, match: NomadsCurrentCityController.Match?, checkedAt: Date?, errorMessage: String?) {
        self.identity = identity
        storedState = StoredState(state)
        self.matchedCity = matchedCity
        self.match = match
        self.checkedAt = checkedAt
        self.errorMessage = errorMessage
    }

    var state: NomadsCurrentCityController.State {
        switch storedState {
        case .matched: .matched
        case .notFound: .notFound
        case .unavailable: .unavailable
        }
    }
}

private enum StoredState: String, Codable, Sendable {
    case matched, notFound, unavailable

    init(_ state: NomadsCurrentCityController.State) {
        switch state {
        case .matched: self = .matched
        case .notFound: self = .notFound
        default: self = .unavailable
        }
    }
}

private struct PersistedData: Codable, Sendable {
    let directory: [NomadsDirectoryCity]
    let result: StoredResult?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
