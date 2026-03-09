import CoreLocation
import Foundation
import WeatherKit

protocol TravelAlertDiagnosticError: Error {
    var diagnosticSummary: String { get }
}

enum ReliefWebProviderError: Error, Equatable, TravelAlertDiagnosticError, CustomStringConvertible {
    case requestFailed(URLError.Code)
    case unexpectedStatus(Int, bodySnippet: String?)
    case invalidPayload(String)

    var diagnosticSummary: String {
        switch self {
        case let .requestFailed(code):
            switch code {
            case .notConnectedToInternet:
                "ReliefWeb request failed: no internet connection."
            case .timedOut:
                "ReliefWeb request timed out."
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                "ReliefWeb could not be reached."
            default:
                "ReliefWeb request failed before a response was received."
            }
        case let .unexpectedStatus(statusCode, _):
            "ReliefWeb returned HTTP \(statusCode)."
        case .invalidPayload:
            "ReliefWeb response format changed."
        }
    }

    var description: String {
        switch self {
        case let .requestFailed(code):
            "ReliefWeb request failed with URLError code \(code.rawValue)."
        case let .unexpectedStatus(statusCode, bodySnippet):
            if let bodySnippet, bodySnippet.isEmpty == false {
                "ReliefWeb returned HTTP \(statusCode). Body snippet: \(bodySnippet)"
            } else {
                "ReliefWeb returned HTTP \(statusCode)."
            }
        case let .invalidPayload(message):
            "ReliefWeb response format changed: \(message)"
        }
    }
}

public struct BundledNeighborCountryResolver: NeighborCountryResolver {
    private let bordersByCountry: [String: [String]]

    public init() {
        self.init(bundle: .module)
    }

    init(bundle: Bundle) {
        guard
            let url = bundle.url(forResource: "country-borders", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let records = try? JSONDecoder().decode([CountryBorderRecord].self, from: data)
        else {
            bordersByCountry = [:]
            return
        }

        bordersByCountry = Dictionary(
            uniqueKeysWithValues: records.map { ($0.cca2.uppercased(), $0.borders.map { $0.uppercased() }) }
        )
    }

    public func neighboringCountryCodes(for countryCode: String) -> [String] {
        bordersByCountry[countryCode.uppercased()] ?? []
    }
}

public actor SmartravellerAdvisoryProvider: TravelAdvisoryProvider {
    public nonisolated let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "Smartraveller",
        url: URL(string: "https://www.smartraveller.gov.au")
    )

    private let session: URLSession
    private let ttl: TimeInterval
    private let endpoint: URL
    private let countryNameResolver: CountryNameResolver
    private var cache: (fetchedAt: Date, destinations: [SmartravellerDestination])?

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 43_200,
        endpoint: URL = URL(string: "https://www.smartraveller.gov.au/destinations-export")!
    ) {
        self.init(
            session: session,
            ttl: ttl,
            endpoint: endpoint,
            countryNameResolver: CountryNameResolver()
        )
    }

    init(
        session: URLSession,
        ttl: TimeInterval,
        endpoint: URL,
        countryNameResolver: CountryNameResolver
    ) {
        self.session = session
        self.ttl = ttl
        self.endpoint = endpoint
        self.countryNameResolver = countryNameResolver
    }

    public func advisory(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        let normalizedCountryCodes = Self.normalizedCountryCodes(countryCodes)
        let destinations = try await loadDestinations(forceRefresh: forceRefresh)
        let matches: [AdvisoryMatch] = normalizedCountryCodes.compactMap { countryCode in
            guard let match = bestDestinationMatch(for: countryCode, in: destinations) else {
                return nil
            }

            return AdvisoryMatch(
                countryCode: countryCode,
                countryName: countryNameResolver.primaryName(for: countryCode) ?? countryCode,
                destination: match
            )
        }

        return try Self.signal(from: matches, primaryCountryCode: primaryCountryCode, now: Date())
    }

    func bestDestinationMatch(for countryCode: String, in destinations: [SmartravellerDestination]) -> SmartravellerDestination? {
        let candidateNames = countryNameResolver.candidateNames(for: countryCode)
        let normalizedCandidates = Set(candidateNames.map(countryNameResolver.normalized))

        let exactMatch = destinations.first { destination in
            normalizedCandidates.contains(countryNameResolver.normalized(destination.name))
        }

        if let exactMatch {
            return exactMatch
        }

        return destinations.first { destination in
            let normalizedName = countryNameResolver.normalized(destination.name)
            return normalizedCandidates.contains { normalizedName.contains($0) || $0.contains(normalizedName) }
        }
    }

    func loadDestinations(forceRefresh: Bool) async throws -> [SmartravellerDestination] {
        if !forceRefresh, let cache, abs(cache.fetchedAt.timeIntervalSinceNow) < ttl {
            return cache.destinations
        }

        let (data, response) = try await session.data(from: endpoint)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }

        let destinations = try Self.parseDestinations(from: data)
        cache = (Date(), destinations)
        return destinations
    }

    static func signal(from matches: [AdvisoryMatch], primaryCountryCode: String, now: Date) throws -> TravelAlertSignalSnapshot {
        guard let worst = matches.max(by: { lhs, rhs in
            if lhs.severity == rhs.severity {
                return lhs.countryCode != primaryCountryCode && rhs.countryCode == primaryCountryCode
            }

            return lhs.severity < rhs.severity
        }) else {
            throw ProviderError.invalidResponse
        }

        let sourceURL = worst.destination.url
        let summary = if worst.severity == .clear {
            "No elevated travel advisories across your nearby countries."
        } else if worst.countryCode == primaryCountryCode {
            "\(worst.countryName) is at \(worst.destination.levelLabel)."
        } else {
            "\(worst.countryName) is at \(worst.destination.levelLabel) nearby."
        }

        return TravelAlertSignalSnapshot(
            kind: .advisory,
            severity: worst.severity,
            title: "Travel advisory",
            summary: summary,
            sourceName: "Smartraveller",
            sourceURL: sourceURL,
            updatedAt: worst.destination.updatedAt ?? now,
            affectedCountryCodes: matches
                .filter { $0.severity > .clear }
                .map(\.countryCode)
                .uniqued()
        )
    }

    static func parseDestinations(from data: Data) throws -> [SmartravellerDestination] {
        let rootObject = try JSONSerialization.jsonObject(with: data)

        let rawItems: [Any] = if let array = rootObject as? [Any] {
            array
        } else if let dictionary = rootObject as? [String: Any] {
            (dictionary["data"] as? [Any]) ?? (dictionary["destinations"] as? [Any]) ?? []
        } else {
            []
        }

        let destinations = rawItems.compactMap { item -> SmartravellerDestination? in
            guard let dictionary = item as? [String: Any] else {
                return nil
            }

            let name = Self
                .stringValue(in: dictionary, keys: ["title", "name", "country"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let name, name.isEmpty == false else {
                return nil
            }

            let level = Self.intValue(in: dictionary, keys: ["advice_level", "adviceLevel", "level"]) ?? 1
            let url = Self.urlValue(in: dictionary, keys: ["url", "link", "canonical_url", "destination_url"])
            let updatedAt = Self.dateValue(in: dictionary, keys: ["updated_at", "updatedAt", "last_updated", "lastUpdated"])
            return SmartravellerDestination(name: name, level: level, url: url, updatedAt: updatedAt)
        }

        guard destinations.isEmpty == false else {
            throw ProviderError.invalidResponse
        }

        return destinations
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, value.isEmpty == false {
                return value
            }
        }

        return nil
    }

    private static func intValue(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }

            if let value = dictionary[key] as? String, let intValue = Int(value) {
                return intValue
            }
        }

        return nil
    }

    private static func urlValue(in dictionary: [String: Any], keys: [String]) -> URL? {
        stringValue(in: dictionary, keys: keys).flatMap(URL.init(string:))
    }

    private static func dateValue(in dictionary: [String: Any], keys: [String]) -> Date? {
        guard let value = stringValue(in: dictionary, keys: keys) else {
            return nil
        }

        return parseISO8601Date(value)
    }

    private static func normalizedCountryCodes(_ countryCodes: [String]) -> [String] {
        countryCodes.map { $0.uppercased() }.uniqued()
    }
}

public actor WeatherKitAlertProvider: TravelWeatherAlertsProvider {
    public nonisolated let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "WeatherKit",
        url: URL(string: "https://developer.apple.com/weatherkit/")
    )

    private let service: WeatherService
    private let ttl: TimeInterval
    private var cache: (key: String, signal: TravelAlertSignalSnapshot)?

    public init(service: WeatherService = WeatherService(), ttl: TimeInterval = 1_800) {
        self.service = service
        self.ttl = ttl
    }

    public func alerts(for coordinate: CLLocationCoordinate2D?, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        guard let coordinate else {
            throw ProviderError.missingCoordinate
        }

        let cacheKey = Self.cacheKey(for: coordinate)
        if !forceRefresh, let cache, cache.key == cacheKey, abs(cache.signal.updatedAt.timeIntervalSinceNow) < ttl {
            return cache.signal
        }

        let weather = try await service.weather(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard weather.availability.alertAvailability == .available else {
            throw ProviderError.invalidResponse
        }

        let payloads = (weather.weatherAlerts ?? []).map {
            WeatherAlertPayload(
                detailsURL: $0.detailsURL,
                source: $0.source,
                summary: $0.summary,
                severity: $0.severity
            )
        }
        let signal = Self.signal(from: payloads, fetchedAt: Date())
        cache = (cacheKey, signal)
        return signal
    }

    static func signal(from alerts: [WeatherAlertPayload], fetchedAt: Date) -> TravelAlertSignalSnapshot {
        guard let worst = alerts.max(by: { lhs, rhs in
            Self.severity(for: lhs.severity) < Self.severity(for: rhs.severity)
        }) else {
            return TravelAlertSignalSnapshot(
                kind: .weather,
                severity: .clear,
                title: "Weather alerts",
                summary: "No severe weather alerts for your current location.",
                sourceName: "WeatherKit",
                sourceURL: URL(string: "https://developer.apple.com/weatherkit/"),
                updatedAt: fetchedAt,
                affectedCountryCodes: []
            )
        }

        let itemCount = alerts.count
        let prefix = itemCount > 1 ? "\(itemCount) active weather alerts. " : ""
        return TravelAlertSignalSnapshot(
            kind: .weather,
            severity: Self.severity(for: worst.severity),
            title: "Weather alerts",
            summary: prefix + worst.summary,
            sourceName: worst.source.isEmpty ? "WeatherKit" : worst.source,
            sourceURL: worst.detailsURL,
            updatedAt: fetchedAt,
            affectedCountryCodes: [],
            itemCount: itemCount
        )
    }

    static func severity(for weatherSeverity: WeatherSeverity) -> TravelAlertSeverity {
        switch weatherSeverity {
        case .minor, .unknown:
            .info
        case .moderate:
            .caution
        case .severe:
            .warning
        case .extreme:
            .critical
        @unknown default:
            .info
        }
    }

    private static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.3f", coordinate.latitude)
        let longitude = String(format: "%.3f", coordinate.longitude)
        return "\(latitude),\(longitude)"
    }
}

public actor ReliefWebSecurityProvider: RegionalSecurityProvider {
    public nonisolated let sourceDescriptor = TravelAlertSourceDescriptor(
        name: "ReliefWeb",
        url: URL(string: "https://reliefweb.int")
    )

    private let session: URLSession
    private let ttl: TimeInterval
    private let endpoint: URL
    private let appName: String
    private let countryNameResolver: CountryNameResolver
    private var cache: [String: (fetchedAt: Date, signal: TravelAlertSignalSnapshot)] = [:]

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 3_600,
        endpoint: URL = URL(string: "https://api.reliefweb.int/v1/reports")!,
        appName: String? = nil
    ) {
        self.init(
            session: session,
            ttl: ttl,
            endpoint: endpoint,
            appName: appName,
            countryNameResolver: CountryNameResolver()
        )
    }

    init(
        session: URLSession,
        ttl: TimeInterval,
        endpoint: URL,
        appName: String?,
        countryNameResolver: CountryNameResolver
    ) {
        self.session = session
        self.ttl = ttl
        self.endpoint = endpoint
        self.appName = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.countryNameResolver = countryNameResolver
    }

    public func security(for countryCodes: [String], primaryCountryCode: String, forceRefresh: Bool) async throws -> TravelAlertSignalSnapshot {
        guard appName.isEmpty == false else {
            throw ProviderError.missingConfiguration
        }

        let normalizedCountryCodes = Self.normalizedCountryCodes(countryCodes)
        let primaryCountryName = countryNameResolver.primaryName(for: primaryCountryCode) ?? primaryCountryCode
        let cacheKey = ([primaryCountryCode.uppercased()] + normalizedCountryCodes).joined(separator: ",")

        if !forceRefresh, let cached = cache[cacheKey], abs(cached.fetchedAt.timeIntervalSinceNow) < ttl {
            return cached.signal
        }

        let countryNames = normalizedCountryCodes.compactMap(countryNameResolver.primaryName(for:))
        let reports = try await fetchReports(countryNames: countryNames)
        let signal = Self.signal(
            from: reports,
            primaryCountryName: primaryCountryName,
            matchedCountryNames: countryNames,
            now: Date()
        )
        cache[cacheKey] = (Date(), signal)
        return signal
    }

    func fetchReports(countryNames: [String]) async throws -> [SecurityReportPayload] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cutoff = iso8601String(from: Date().addingTimeInterval(-72 * 3_600))
        let body: [String: Any] = [
            "appname": appName,
            "limit": 10,
            "sort": ["date.created:desc"],
            "fields": [
                "include": [
                    "title",
                    "date.created",
                    "primary_country.shortname",
                    "source.shortname",
                    "url_alias"
                ]
            ],
            "query": [
                "value": "security conflict violence protest unrest armed attack shelling airstrike",
                "operator": "OR"
            ],
            "filter": [
                "operator": "AND",
                "conditions": [
                    [
                        "field": "date.created",
                        "value": ["from": cutoff]
                    ],
                    [
                        "field": "country.name",
                        "value": countryNames,
                        "operator": "OR"
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ReliefWebProviderError.requestFailed(error.code)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ReliefWebProviderError.unexpectedStatus(statusCode, bodySnippet: responseSnippet(from: data))
        }

        return try Self.parseReports(from: data)
    }

    static func signal(
        from reports: [SecurityReportPayload],
        primaryCountryName: String,
        matchedCountryNames: [String],
        now: Date
    ) -> TravelAlertSignalSnapshot {
        let primaryNormalizer = CountryNameResolver().normalized(primaryCountryName)
        let currentCountryReports = reports.filter { CountryNameResolver().normalized($0.primaryCountryName) == primaryNormalizer }
        let nearbyReports = reports.filter { CountryNameResolver().normalized($0.primaryCountryName) != primaryNormalizer }
        let currentCountryRecentReports = currentCountryReports.filter { now.timeIntervalSince($0.date) <= 24 * 3_600 }

        let severity: TravelAlertSeverity = if currentCountryRecentReports.isEmpty == false {
            .warning
        } else if currentCountryReports.isEmpty == false || nearbyReports.count >= 2 {
            .caution
        } else if nearbyReports.isEmpty == false {
            .info
        } else {
            .clear
        }

        let latestReport = reports.sorted { $0.date > $1.date }.first
        let summary = switch severity {
        case .warning:
            "\(currentCountryRecentReports.count) recent security bulletin(s) mention \(primaryCountryName)."
        case .caution:
            if currentCountryReports.isEmpty == false {
                "Security reporting mentions \(primaryCountryName) within the last 72 hours."
            } else {
                "\(nearbyReports.count) nearby security bulletins were published recently."
            }
        case .info:
            "A nearby security bulletin was published within the last 72 hours."
        case .clear:
            "No recent security bulletins across \(matchedCountryNames.count) monitored countries."
        case .critical:
            "Regional security conditions require immediate review."
        }

        let sourceURL = latestReport?.urlAlias.flatMap { alias -> URL? in
            if alias.hasPrefix("http") {
                return URL(string: alias)
            }

            return URL(string: "https://reliefweb.int\(alias)")
        }

        return TravelAlertSignalSnapshot(
            kind: .security,
            severity: severity,
            title: "Regional security",
            summary: summary,
            sourceName: latestReport?.sourceName ?? "ReliefWeb",
            sourceURL: sourceURL,
            updatedAt: latestReport?.date ?? now,
            affectedCountryCodes: [],
            itemCount: reports.count
        )
    }

    static func parseReports(from data: Data) throws -> [SecurityReportPayload] {
        let rootObject: [String: Any]

        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ReliefWebProviderError.invalidPayload("Top-level response was not a JSON object.")
            }

            rootObject = decoded
        } catch let error as ReliefWebProviderError {
            throw error
        } catch {
            throw ReliefWebProviderError.invalidPayload("Response body was not valid JSON.")
        }

        guard
            let items = rootObject["data"] as? [[String: Any]]
        else {
            throw ReliefWebProviderError.invalidPayload("Missing top-level data array.")
        }

        return items.compactMap { item in
            guard let fields = item["fields"] as? [String: Any] else {
                return nil
            }

            let title = (fields["title"] as? String) ?? "Security update"
            let date = ((fields["date"] as? [String: Any]).flatMap { $0["created"] as? String })
                .flatMap(parseISO8601Date)
            let primaryCountryName = ((fields["primary_country"] as? [String: Any]).flatMap { $0["shortname"] as? String })
                ?? ((fields["primary_country"] as? [String: Any]).flatMap { $0["name"] as? String })
                ?? "Unknown"
            let sourceName = ((fields["source"] as? [[String: Any]])?.first?["shortname"] as? String)
                ?? ((fields["source"] as? [[String: Any]])?.first?["name"] as? String)
                ?? "ReliefWeb"
            let urlAlias = fields["url_alias"] as? String

            guard let date else {
                return nil
            }

            return SecurityReportPayload(
                title: title,
                date: date,
                primaryCountryName: primaryCountryName,
                sourceName: sourceName,
                urlAlias: urlAlias
            )
        }
    }

    private static func normalizedCountryCodes(_ countryCodes: [String]) -> [String] {
        countryCodes.map { $0.uppercased() }.uniqued()
    }

    private func responseSnippet(from data: Data) -> String? {
        guard
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            text.isEmpty == false
        else {
            return nil
        }

        return String(text.prefix(160))
    }
}

struct CountryNameResolver {
    private let locale = Locale(identifier: "en_US_POSIX")

    func primaryName(for countryCode: String) -> String? {
        let uppercasedCode = countryCode.uppercased()
        return locale.localizedString(forRegionCode: uppercasedCode) ?? aliasOverridesByCode[uppercasedCode]?.first
    }

    func candidateNames(for countryCode: String) -> [String] {
        let uppercasedCode = countryCode.uppercased()
        var names = [String]()

        if let primaryName = primaryName(for: uppercasedCode) {
            names.append(primaryName)
        }

        names.append(contentsOf: aliasOverridesByCode[uppercasedCode] ?? [])
        return names.uniqued()
    }

    func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WeatherAlertPayload {
    let detailsURL: URL
    let source: String
    let summary: String
    let severity: WeatherSeverity
}

struct SecurityReportPayload {
    let title: String
    let date: Date
    let primaryCountryName: String
    let sourceName: String
    let urlAlias: String?
}

struct AdvisoryMatch {
    let countryCode: String
    let countryName: String
    let destination: SmartravellerDestination

    var severity: TravelAlertSeverity {
        destination.severity
    }
}

struct SmartravellerDestination {
    let name: String
    let level: Int
    let url: URL?
    let updatedAt: Date?

    var severity: TravelAlertSeverity {
        switch level {
        case 1:
            .clear
        case 2:
            .caution
        case 3:
            .warning
        case 4:
            .critical
        default:
            .info
        }
    }

    var levelLabel: String {
        "Level \(level)"
    }
}

private struct CountryBorderRecord: Decodable {
    let cca2: String
    let borders: [String]
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private let aliasOverridesByCode: [String: [String]] = [
    "BO": ["Bolivia", "Bolivia Plurinational State of"],
    "BN": ["Brunei", "Brunei Darussalam"],
    "CV": ["Cape Verde", "Cabo Verde"],
    "CI": ["Ivory Coast", "Cote d Ivoire", "Cote d'Ivoire"],
    "CZ": ["Czech Republic", "Czechia"],
    "IR": ["Iran", "Iran Islamic Republic of"],
    "KR": ["South Korea", "Republic of Korea", "Korea Republic of"],
    "KP": ["North Korea", "Democratic People's Republic of Korea", "Korea Democratic People's Republic of"],
    "LA": ["Laos", "Lao People's Democratic Republic"],
    "MD": ["Moldova", "Republic of Moldova"],
    "PS": ["Palestine", "State of Palestine"],
    "RU": ["Russia", "Russian Federation"],
    "SY": ["Syria", "Syrian Arab Republic"],
    "TW": ["Taiwan", "Taiwan Province of China"],
    "TZ": ["Tanzania", "United Republic of Tanzania"],
    "TR": ["Turkey", "Turkiye", "Türkiye"],
    "VE": ["Venezuela", "Venezuela Bolivarian Republic of"],
    "VN": ["Vietnam", "Viet Nam"]
]

private func parseISO8601Date(_ value: String) -> Date? {
    let formatterWithFractionalSeconds = ISO8601DateFormatter()
    formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = formatterWithFractionalSeconds.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
