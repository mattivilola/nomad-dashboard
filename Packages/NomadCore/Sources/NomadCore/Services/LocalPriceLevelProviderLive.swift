import CoreLocation
import Foundation

public actor LiveLocalPriceLevelProvider: LocalPriceLevelProvider, LocalPriceLevelProviderConfigurationUpdating {
    private let session: URLSession
    private let ttl: TimeInterval
    private var hudUserAPIToken: String?
    private var cache: [String: LocalPriceLevelSnapshot] = [:]

    private static let eurostatSource = LocalPriceSourceAttribution(
        name: "Eurostat",
        url: URL(string: "https://ec.europa.eu/eurostat/web/main/data/database")
    )
    private static let hudSource = LocalPriceSourceAttribution(
        name: "HUD USER",
        url: URL(string: "https://www.huduser.gov/portal/dataset/fmr-api.html")
    )
    private static let censusSource = LocalPriceSourceAttribution(
        name: "US Census Geocoder",
        url: URL(string: "https://geocoding.geo.census.gov/")
    )
    private static let eurostatCountryCodes: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "EL", "ES", "FI", "FR", "HR", "HU",
        "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK"
    ]

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 21_600,
        hudUserAPIToken: String? = nil
    ) {
        self.session = session
        self.ttl = ttl
        self.hudUserAPIToken = Self.trimmed(hudUserAPIToken)
    }

    public func setHUDUserAPIToken(_ token: String?) async {
        hudUserAPIToken = Self.trimmed(token)
        cache = cache.filter { $0.key.hasPrefix("US|") == false }
    }

    public func prices(for request: LocalPriceSearchRequest, forceRefresh: Bool) async throws -> LocalPriceLevelSnapshot {
        let cacheKey = Self.cacheKey(for: request)

        if !forceRefresh,
           let cached = cache[cacheKey],
           abs(cached.fetchedAt?.timeIntervalSinceNow ?? ttl + 1) < ttl
        {
            return cached
        }

        let snapshot: LocalPriceLevelSnapshot
        switch normalizedCountryCode(request.countryCode) {
        case "US":
            snapshot = try await usSnapshot(for: request)
        case let code where Self.eurostatCountryCodes.contains(code):
            snapshot = try await eurostatSnapshot(for: request, countryCode: code)
        default:
            snapshot = LocalPriceLevelSnapshot(
                status: .unsupported,
                summaryBand: nil,
                countryCode: normalizedCountryCode(request.countryCode),
                countryName: request.countryName,
                rows: [],
                sources: [],
                fetchedAt: Date(),
                detail: "Local price level is only supported in Europe and the United States right now.",
                note: nil
            )
        }

        cache[cacheKey] = snapshot
        return snapshot
    }

    private func eurostatSnapshot(
        for request: LocalPriceSearchRequest,
        countryCode: String
    ) async throws -> LocalPriceLevelSnapshot {
        async let mealObservation = eurostatObservation(countryCode: countryCode, category: "A0111")
        async let groceryObservation = eurostatObservation(countryCode: countryCode, category: "A0101")
        async let overallObservation = eurostatObservation(countryCode: countryCode, category: "A01")

        let meal = try await mealObservation
        let groceries = try await groceryObservation
        let overall = try await overallObservation

        var rows: [LocalPriceIndicatorRow] = []

        if let meal {
            rows.append(
                makeEurostatRow(
                    kind: .mealOut,
                    observation: meal,
                    suffix: "EU average"
                )
            )
        }

        if let groceries {
            rows.append(
                makeEurostatRow(
                    kind: .groceries,
                    observation: groceries,
                    suffix: "EU average"
                )
            )
        }

        if let overall {
            rows.append(
                makeEurostatRow(
                    kind: .overall,
                    observation: overall,
                    suffix: "EU average"
                )
            )
        }

        guard rows.isEmpty == false else {
            return LocalPriceLevelSnapshot(
                status: .unsupported,
                summaryBand: nil,
                countryCode: countryCode,
                countryName: request.countryName,
                rows: [],
                sources: [Self.eurostatSource],
                fetchedAt: Date(),
                detail: "Eurostat does not currently publish traveller price levels for this country in the v1 dataset.",
                note: nil
            )
        }

        let displayRows = Array(rows.prefix(3))
        let summaryReference = overall?.value ?? mean([meal?.value, groceries?.value])
        let summaryBand = summaryReference.map(Self.summaryBand(for:)) ?? .limited
        let status: LocalPriceLevelStatus = displayRows.count == 3 ? .ready : .partial

        return LocalPriceLevelSnapshot(
            status: status,
            summaryBand: summaryBand,
            countryCode: countryCode,
            countryName: request.countryName,
            rows: displayRows,
            sources: [Self.eurostatSource],
            fetchedAt: Date(),
            detail: "Meal out and groceries use country-level Eurostat price indices. 1BR rent is replaced with an overall local cost signal when no official free rent dataset is available.",
            note: nil
        )
    }

    private func usSnapshot(for request: LocalPriceSearchRequest) async throws -> LocalPriceLevelSnapshot {
        guard let token = hudUserAPIToken else {
            return LocalPriceLevelSnapshot(
                status: .configurationRequired,
                summaryBand: nil,
                countryCode: "US",
                countryName: request.countryName,
                rows: [],
                sources: [Self.hudSource],
                fetchedAt: nil,
                detail: "Add a HUD USER API token in Settings to show the US 1-bedroom rent benchmark.",
                note: nil
            )
        }

        guard let coordinate = request.coordinate else {
            return LocalPriceLevelSnapshot(
                status: .locationRequired,
                summaryBand: nil,
                countryCode: "US",
                countryName: request.countryName,
                rows: [],
                sources: [Self.hudSource, Self.censusSource],
                fetchedAt: nil,
                detail: "Allow current location to resolve the US county for the HUD 1-bedroom rent benchmark.",
                note: nil
            )
        }

        do {
            let county = try await censusCounty(for: coordinate)
            let hudResult = try await hudOneBedroomRent(for: county.geoid, token: token)
            let value = Self.makeMonthlyCurrencyFormatter().string(from: NSNumber(value: hudResult.oneBedroomRent)) ?? "n/a"
            let detail = [
                hudResult.precision.displayName,
                hudResult.areaName,
                String(hudResult.year)
            ]
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
            let row = LocalPriceIndicatorRow(
                kind: .rentOneBedroom,
                value: "\(value)/mo",
                detail: detail,
                precision: hudResult.precision,
                source: Self.hudSource
            )

            return LocalPriceLevelSnapshot(
                status: .partial,
                summaryBand: .limited,
                countryCode: "US",
                countryName: request.countryName ?? "United States",
                rows: [row],
                sources: [Self.hudSource, Self.censusSource],
                fetchedAt: Date(),
                detail: "US v1 currently shows the HUD 1-bedroom rent benchmark only.",
                note: county.name
            )
        } catch ProviderError.missingConfiguration {
            return LocalPriceLevelSnapshot(
                status: .configurationRequired,
                summaryBand: nil,
                countryCode: "US",
                countryName: request.countryName,
                rows: [],
                sources: [Self.hudSource],
                fetchedAt: nil,
                detail: "The HUD USER API token was rejected. Update the token in Settings.",
                note: nil
            )
        }
    }

    private func eurostatObservation(countryCode: String, category: String) async throws -> EurostatObservation? {
        var components = URLComponents(string: "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_ppp_ind_1")!
        components.queryItems = [
            URLQueryItem(name: "geo", value: countryCode),
            URLQueryItem(name: "indic_ppp", value: "PLI_EU27_2020"),
            URLQueryItem(name: "ppp_cat18", value: category),
            URLQueryItem(name: "lang", value: "EN")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw ProviderError.invalidResponse
        }

        let dataset = try JSONDecoder().decode(EurostatDatasetResponse.self, from: data)
        guard let value = dataset.value, value.isEmpty == false else {
            return nil
        }

        let reverseTimeIndex = Dictionary(uniqueKeysWithValues: dataset.dimension.time.category.index.map { ($1, $0) })
        guard let latestKey = value.keys.compactMap(Int.init).max(),
              let latestValue = value[String(latestKey)],
              let yearText = reverseTimeIndex[latestKey],
              let year = Int(yearText)
        else {
            return nil
        }

        return EurostatObservation(category: category, year: year, value: latestValue)
    }

    private func censusCounty(for coordinate: CLLocationCoordinate2D) async throws -> CensusCounty {
        var components = URLComponents(string: "https://geocoding.geo.census.gov/geocoder/geographies/coordinates")!
        components.queryItems = [
            URLQueryItem(name: "x", value: String(coordinate.longitude)),
            URLQueryItem(name: "y", value: String(coordinate.latitude)),
            URLQueryItem(name: "benchmark", value: "Public_AR_Current"),
            URLQueryItem(name: "vintage", value: "Current_Current"),
            URLQueryItem(name: "format", value: "json")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw ProviderError.invalidResponse
        }

        let lookup = try JSONDecoder().decode(CensusCountyLookupResponse.self, from: data)
        guard let county = lookup.result.geographies.counties.first else {
            throw ProviderError.invalidResponse
        }

        return county
    }

    private func hudOneBedroomRent(for countyGEOID: String, token: String) async throws -> HUDOneBedroomRent {
        let url = URL(string: "https://www.huduser.gov/hudapi/public/fmr/data/\(countyGEOID)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProviderError.missingConfiguration
        default:
            throw ProviderError.invalidResponse
        }

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = payload["data"] as? [String: Any]
        else {
            throw ProviderError.invalidResponse
        }

        if let basicData = dataObject["basicdata"] as? [String: Any] {
            let rent = try oneBedroomRentValue(from: basicData)
            let metroName = Self.trimmed(dataObject["metro_name"] as? String)
            let countyName = Self.trimmed(dataObject["county_name"] as? String)
            let areaName = Self.trimmed(dataObject["area_name"] as? String)
                ?? metroName
                ?? countyName
                ?? "HUD area"
            let precision: LocalPricePrecision = metroName == nil ? .countyBenchmark : .metroBenchmark
            let year = Self.intValue(from: basicData["year"]) ?? Self.intValue(from: dataObject["year"]) ?? Calendar.current.component(.year, from: .now)

            return HUDOneBedroomRent(
                areaName: areaName,
                year: year,
                oneBedroomRent: rent,
                precision: precision
            )
        }

        if let basicDataRows = dataObject["basicdata"] as? [[String: Any]],
           let row = basicDataRows.first(where: { ($0["zip_code"] as? String) == "MSA level" }) ?? basicDataRows.first
        {
            let rent = try oneBedroomRentValue(from: row)
            let areaName = Self.trimmed(dataObject["area_name"] as? String)
                ?? Self.trimmed(dataObject["metro_name"] as? String)
                ?? "HUD metro area"
            let year = Self.intValue(from: dataObject["year"]) ?? Calendar.current.component(.year, from: .now)

            return HUDOneBedroomRent(
                areaName: areaName,
                year: year,
                oneBedroomRent: rent,
                precision: .metroBenchmark
            )
        }

        throw ProviderError.invalidResponse
    }

    private func oneBedroomRentValue(from object: [String: Any]) throws -> Double {
        if let value = Self.doubleValue(from: object["One-Bedroom"]) {
            return value
        }

        throw ProviderError.invalidResponse
    }

    private func makeEurostatRow(
        kind: LocalPriceIndicatorKind,
        observation: EurostatObservation,
        suffix: String
    ) -> LocalPriceIndicatorRow {
        let valueDescription = Self.rowValueDescription(for: observation.value)
        let detail = [
            Self.relativeDifferenceText(for: observation.value, against: 100, suffix: suffix),
            LocalPricePrecision.countryFallback.displayName,
            String(observation.year)
        ].joined(separator: " · ")

        return LocalPriceIndicatorRow(
            kind: kind,
            value: valueDescription,
            detail: detail,
            precision: .countryFallback,
            source: Self.eurostatSource
        )
    }

    private static func cacheKey(for request: LocalPriceSearchRequest) -> String {
        let latitude = request.coordinate.map { String(format: "%.3f", $0.latitude) } ?? "none"
        let longitude = request.coordinate.map { String(format: "%.3f", $0.longitude) } ?? "none"
        return "\(request.countryCode.uppercased())|\(latitude),\(longitude)"
    }

    private static func summaryBand(for value: Double) -> LocalPriceSummaryBand {
        switch value {
        case ..<95:
            .low
        case 105...:
            .high
        default:
            .medium
        }
    }

    private static func rowValueDescription(for value: Double) -> String {
        switch value {
        case ..<95:
            "Below Avg"
        case 105...:
            "Above Avg"
        default:
            "Moderate"
        }
    }

    private static func relativeDifferenceText(for value: Double, against baseline: Double, suffix: String) -> String {
        let delta = Int((value - baseline).rounded())
        if abs(delta) <= 1 {
            return "Around \(suffix)"
        }

        if delta > 0 {
            return "\(delta)% above \(suffix)"
        }

        return "\(abs(delta))% below \(suffix)"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            value
        case let value as NSNumber:
            value.doubleValue
        case let value as String:
            Double(value)
        default:
            nil
        }
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as NSNumber:
            value.intValue
        case let value as String:
            Int(value)
        default:
            nil
        }
    }

    private static func makeMonthlyCurrencyFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.currencyCode = "USD"
        return formatter
    }

    private func normalizedCountryCode(_ value: String) -> String {
        let uppercased = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return uppercased == "GR" ? "EL" : uppercased
    }
}

private struct EurostatObservation {
    let category: String
    let year: Int
    let value: Double
}

private struct HUDOneBedroomRent {
    let areaName: String
    let year: Int
    let oneBedroomRent: Double
    let precision: LocalPricePrecision
}

private struct EurostatDatasetResponse: Decodable {
    let value: [String: Double]?
    let dimension: EurostatDatasetDimension
}

private struct EurostatDatasetDimension: Decodable {
    let time: EurostatDatasetCategoryContainer
}

private struct EurostatDatasetCategoryContainer: Decodable {
    let category: EurostatDatasetCategory
}

private struct EurostatDatasetCategory: Decodable {
    let index: [String: Int]
}

private struct CensusCountyLookupResponse: Decodable {
    let result: CensusCountyLookupResult
}

private struct CensusCountyLookupResult: Decodable {
    let geographies: CensusCountyLookupGeographies
}

private struct CensusCountyLookupGeographies: Decodable {
    let counties: [CensusCounty]

    enum CodingKeys: String, CodingKey {
        case counties = "Counties"
    }
}

private struct CensusCounty: Decodable {
    let geoid: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case geoid = "GEOID"
        case name = "NAME"
    }
}

private func mean(_ values: [Double?]) -> Double? {
    let resolved = values.compactMap(\.self)
    guard resolved.isEmpty == false else {
        return nil
    }

    return resolved.reduce(0, +) / Double(resolved.count)
}
