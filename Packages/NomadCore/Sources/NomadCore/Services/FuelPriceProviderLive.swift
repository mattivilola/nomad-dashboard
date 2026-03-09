import CoreLocation
import Foundation

private struct FuelSourceDescriptor: Sendable {
    let name: String
    let url: URL?
    let note: String?
}

private struct FuelStationCandidate: Sendable {
    let identifier: String
    let stationName: String
    let address: String?
    let locality: String?
    let latitude: Double
    let longitude: Double
    let updatedAt: Date?
    let isSelfService: Bool?
    let prices: [FuelType: Double]
}

private struct ScoredFuelStationCandidate: Sendable {
    let candidate: FuelStationCandidate
    let distanceKilometers: Double
}

private protocol CountryFuelPriceSource: Sendable {
    var descriptor: FuelSourceDescriptor { get }
    func snapshot(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot
}

public struct FuelPriceProviderError: Error, Sendable {
    public let sourceName: String
    public let sourceURL: URL?
    public let underlyingDescription: String

    public init(sourceName: String, sourceURL: URL?, underlyingDescription: String) {
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.underlyingDescription = underlyingDescription
    }
}

public actor LiveEuropeanFuelPriceProvider: FuelPriceProvider {
    private let session: URLSession
    private let ttl: TimeInterval
    private let tankerkonigAPIKey: String?
    private var cache: [String: FuelPriceSnapshot] = [:]

    public init(
        session: URLSession = .shared,
        ttl: TimeInterval = 900,
        tankerkonigAPIKey: String? = nil
    ) {
        self.session = session
        self.ttl = ttl
        self.tankerkonigAPIKey = tankerkonigAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func prices(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        let cacheKey = Self.cacheKey(for: request)
        if !forceRefresh,
           let cached = cache[cacheKey],
           abs(cached.fetchedAt?.timeIntervalSinceNow ?? ttl + 1) < ttl
        {
            return cached
        }

        let provider = provider(for: request.countryCode)
        let snapshot: FuelPriceSnapshot
        do {
            snapshot = try await provider.snapshot(for: request, forceRefresh: forceRefresh)
        } catch {
            throw FuelPriceProviderError(
                sourceName: provider.descriptor.name,
                sourceURL: provider.descriptor.url,
                underlyingDescription: error.localizedDescription
            )
        }
        cache[cacheKey] = snapshot
        return snapshot
    }

    private func provider(for countryCode: String) -> any CountryFuelPriceSource {
        switch countryCode.uppercased() {
        case "ES":
            SpainFuelPriceSource(session: session)
        case "FR":
            FranceFuelPriceSource(session: session)
        case "IT":
            ItalyFuelPriceSource(session: session)
        case "DE":
            GermanyFuelPriceSource(session: session, apiKey: tankerkonigAPIKey)
        default:
            UnsupportedFuelPriceSource()
        }
    }

    private static func cacheKey(for request: FuelSearchRequest) -> String {
        let latitude = String(format: "%.3f", request.coordinate.latitude)
        let longitude = String(format: "%.3f", request.coordinate.longitude)
        let radius = String(format: "%.0f", request.searchRadiusKilometers)
        return "\(request.countryCode.uppercased())|\(latitude),\(longitude)|\(radius)"
    }
}

private struct UnsupportedFuelPriceSource: CountryFuelPriceSource {
    let descriptor = FuelSourceDescriptor(name: "Nomad Fuel Prices", url: nil, note: nil)

    func snapshot(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        FuelPriceSnapshot(
            status: .unsupported,
            sourceName: descriptor.name,
            sourceURL: descriptor.url,
            countryCode: request.countryCode,
            countryName: request.countryName,
            searchRadiusKilometers: request.searchRadiusKilometers,
            diesel: nil,
            gasoline: nil,
            fetchedAt: Date(),
            detail: "Fuel prices are not supported in \(request.countryName ?? request.countryCode) yet.",
            note: nil
        )
    }
}

private struct SpainFuelPriceSource: CountryFuelPriceSource {
    let session: URLSession
    let descriptor = FuelSourceDescriptor(
        name: "Spanish Ministry Fuel Prices",
        url: URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/"),
        note: nil
    )

    func snapshot(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        let data = try await fetchData(
            from: URL(string: "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/")!,
            session: session
        )
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let payload = object as? [String: Any],
            let stations = payload["ListaEESSPrecio"] as? [[String: Any]]
        else {
            throw ProviderError.invalidResponse
        }

        let candidates = stations.compactMap { station -> FuelStationCandidate? in
            guard
                let latitude = parseCoordinate(station["Latitud"]),
                let longitude = parseCoordinate(station["Longitud (WGS84)"])
            else {
                return nil
            }

            var prices: [FuelType: Double] = [:]

            if let dieselPrice = firstPrice(
                in: station,
                keys: ["Precio Gasoleo A", "Precio Gasoleo Premium"]
            ) {
                prices[.diesel] = dieselPrice
            }

            if let gasolinePrice = firstPrice(
                in: station,
                keys: ["Precio Gasolina 95 E5", "Precio Gasolina 95 E10", "Precio Gasolina 98 E5", "Precio Gasolina 98 E10"]
            ) {
                prices[.gasoline] = gasolinePrice
            }

            guard prices.isEmpty == false else {
                return nil
            }

            let stationName = normalizedString(station["Rótulo"]) ?? normalizedString(station["Dirección"]) ?? "Station"
            let address = normalizedString(station["Dirección"])
            let locality = normalizedString(station["Municipio"]) ?? normalizedString(station["Localidad"])
            let updatedAt = parseDate(station["Horario"])

            return FuelStationCandidate(
                identifier: normalizedString(station["IDEESS"]) ?? "\(stationName)|\(latitude)|\(longitude)",
                stationName: stationName,
                address: address,
                locality: locality,
                latitude: latitude,
                longitude: longitude,
                updatedAt: updatedAt,
                isSelfService: nil,
                prices: prices
            )
        }

        return bestSnapshot(
            from: candidates,
            request: request,
            descriptor: descriptor
        )
    }
}

private struct FranceFuelPriceSource: CountryFuelPriceSource {
    let session: URLSession
    let descriptor = FuelSourceDescriptor(
        name: "French Government Fuel Prices",
        url: URL(string: "https://data.economie.gouv.fr/explore/dataset/prix-des-carburants-en-france-flux-instantane-v2/"),
        note: nil
    )

    func snapshot(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        let rows = try await fetchRows(near: request.coordinate, radiusKilometers: request.searchRadiusKilometers)
        let candidates = rows.compactMap { row -> FuelStationCandidate? in
            guard let coordinate = parseFranceCoordinate(row["geom"]) else {
                return nil
            }

            var prices: [FuelType: Double] = [:]

            if let diesel = parsePrice(row["gazole_prix"]) {
                prices[.diesel] = diesel
            }

            if let gasoline = firstAvailablePrice(values: [
                row["sp95_e10_prix"],
                row["sp95_prix"],
                row["sp98_prix"]
            ]) {
                prices[.gasoline] = gasoline
            }

            guard prices.isEmpty == false else {
                return nil
            }

            let stationName = normalizedString(row["enseigne"]) ?? normalizedString(row["adresse"]) ?? "Station"
            let address = normalizedString(row["adresse"])
            let locality = normalizedString(row["ville"])
            let updatedAt = latestDate(
                parseDate(row["gazole_maj"]),
                parseDate(row["sp95_e10_maj"]),
                parseDate(row["sp95_maj"]),
                parseDate(row["sp98_maj"])
            )

            return FuelStationCandidate(
                identifier: normalizedString(row["id"]) ?? "\(stationName)|\(coordinate.latitude)|\(coordinate.longitude)",
                stationName: stationName,
                address: address,
                locality: locality,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                updatedAt: updatedAt,
                isSelfService: nil,
                prices: prices
            )
        }

        return bestSnapshot(
            from: candidates,
            request: request,
            descriptor: descriptor
        )
    }

    private func fetchRows(near coordinate: CLLocationCoordinate2D, radiusKilometers: Double) async throws -> [[String: Any]] {
        let pageSize = 100
        var offset = 0
        var rows: [[String: Any]] = []

        while true {
            var components = URLComponents(string: "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records")!
            let point = "within_distance(geom, geom'POINT(\(coordinate.longitude) \(coordinate.latitude))', \(Int(radiusKilometers))km)"
            components.queryItems = [
                URLQueryItem(name: "where", value: point),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]

            guard let url = components.url else {
                throw ProviderError.invalidResponse
            }

            let data = try await fetchData(from: url, session: session)
            let object = try JSONSerialization.jsonObject(with: data)
            guard
                let payload = object as? [String: Any],
                let results = payload["results"] as? [[String: Any]]
            else {
                throw ProviderError.invalidResponse
            }

            rows.append(contentsOf: results)
            if results.count < pageSize || offset >= 900 {
                break
            }

            offset += pageSize
        }

        return rows
    }
}

private struct ItalyFuelPriceSource: CountryFuelPriceSource {
    let session: URLSession
    let descriptor = FuelSourceDescriptor(
        name: "MIMIT Fuel Prices",
        url: URL(string: "https://www.mimit.gov.it/it/open-data/elenco-dataset/carburanti-prezzi-praticati-e-anagrafica-degli-impianti"),
        note: "Italian prices come from the daily 8:00 update."
    )

    func snapshot(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        let stationData = try await fetchData(
            from: URL(string: "https://www.mimit.gov.it/images/exportCSV/anagrafica_impianti_attivi.csv")!,
            session: session
        )
        let priceData = try await fetchData(
            from: URL(string: "https://www.mimit.gov.it/images/exportCSV/prezzo_alle_8.csv")!,
            session: session
        )

        let stationRows = try CSVTable.parse(data: stationData, separator: ";")
        let priceRows = try CSVTable.parse(data: priceData, separator: ";")

        let stations = Dictionary(uniqueKeysWithValues: stationRows.compactMap { row -> (String, FuelStationCandidate)? in
            guard
                let stationID = row.string(forAny: ["idimpianto"]),
                let latitude = row.double(forAny: ["latitudine"]),
                let longitude = row.double(forAny: ["longitudine"])
            else {
                return nil
            }

            let stationName = row.string(forAny: ["bandiera", "gestore", "nomimpianto"]) ?? "Station"
            let address = row.string(forAny: ["indirizzo"])
            let locality = row.string(forAny: ["comune"])
            let candidate = FuelStationCandidate(
                identifier: stationID,
                stationName: stationName,
                address: address,
                locality: locality,
                latitude: latitude,
                longitude: longitude,
                updatedAt: nil,
                isSelfService: nil,
                prices: [:]
            )
            return (stationID, candidate)
        })

        var merged = stations

        for row in priceRows {
            guard
                let stationID = row.string(forAny: ["idimpianto"]),
                var candidate = merged[stationID],
                let description = row.string(forAny: ["desccarburante"]),
                let fuelType = fuelTypeForItaly(description),
                let price = row.double(forAny: ["prezzo"])
            else {
                continue
            }

            let updatedAt = parseDate(row.string(forAny: ["dtcomu"]))
            let isSelfService = row.bool(forAny: ["isself"])
            if let existing = candidate.prices[fuelType], existing <= price {
                continue
            }

            var prices = candidate.prices
            prices[fuelType] = price
            candidate = FuelStationCandidate(
                identifier: candidate.identifier,
                stationName: candidate.stationName,
                address: candidate.address,
                locality: candidate.locality,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                updatedAt: latestDate(candidate.updatedAt, updatedAt),
                isSelfService: isSelfService ?? candidate.isSelfService,
                prices: prices
            )
            merged[stationID] = candidate
        }

        return bestSnapshot(
            from: Array(merged.values).filter { $0.prices.isEmpty == false },
            request: request,
            descriptor: descriptor
        )
    }
}

private struct GermanyFuelPriceSource: CountryFuelPriceSource {
    let session: URLSession
    let apiKey: String?
    let descriptor = FuelSourceDescriptor(
        name: "Tankerkönig",
        url: URL(string: "https://creativecommons.tankerkoenig.de/"),
        note: "Germany uses the free Tankerkönig API."
    )

    func snapshot(for request: FuelSearchRequest, forceRefresh: Bool) async throws -> FuelPriceSnapshot {
        guard let apiKey, apiKey.isEmpty == false else {
            return FuelPriceSnapshot(
                status: .configurationRequired,
                sourceName: descriptor.name,
                sourceURL: descriptor.url,
                countryCode: request.countryCode,
                countryName: request.countryName,
                searchRadiusKilometers: request.searchRadiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: Date(),
                detail: "Germany needs a Tankerkönig API key in app config.",
                note: descriptor.note
            )
        }

        let tileCenters = tileCenters(for: request.coordinate)
        var byIdentifier: [String: FuelStationCandidate] = [:]

        for center in tileCenters {
            let candidates = try await fetchCandidates(near: center, apiKey: apiKey)
            for candidate in candidates {
                let existing = byIdentifier[candidate.identifier]
                let mergedPrices = (existing?.prices ?? [:]).merging(candidate.prices) { current, incoming in
                    min(current, incoming)
                }
                byIdentifier[candidate.identifier] = FuelStationCandidate(
                    identifier: candidate.identifier,
                    stationName: candidate.stationName,
                    address: candidate.address ?? existing?.address,
                    locality: candidate.locality ?? existing?.locality,
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    updatedAt: latestDate(existing?.updatedAt, candidate.updatedAt),
                    isSelfService: candidate.isSelfService ?? existing?.isSelfService,
                    prices: mergedPrices
                )
            }
        }

        return bestSnapshot(
            from: Array(byIdentifier.values),
            request: request,
            descriptor: descriptor
        )
    }

    private func fetchCandidates(near coordinate: CLLocationCoordinate2D, apiKey: String) async throws -> [FuelStationCandidate] {
        var components = URLComponents(string: "https://creativecommons.tankerkoenig.de/json/list.php")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "lng", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "rad", value: "25"),
            URLQueryItem(name: "sort", value: "dist"),
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components.url else {
            throw ProviderError.invalidResponse
        }

        let data = try await fetchData(from: url, session: session)
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let payload = object as? [String: Any],
            let ok = payload["ok"] as? Bool,
            ok,
            let stations = payload["stations"] as? [[String: Any]]
        else {
            throw ProviderError.invalidResponse
        }

        return stations.compactMap { station -> FuelStationCandidate? in
            guard
                let identifier = normalizedString(station["id"]),
                let latitude = parseDouble(station["lat"]),
                let longitude = parseDouble(station["lng"])
            else {
                return nil
            }

            var prices: [FuelType: Double] = [:]
            if let diesel = parsePrice(station["diesel"]) {
                prices[.diesel] = diesel
            }

            if let gasoline = firstAvailablePrice(values: [station["e10"], station["e5"]]) {
                prices[.gasoline] = gasoline
            }

            guard prices.isEmpty == false else {
                return nil
            }

            let stationName = normalizedString(station["brand"]) ?? normalizedString(station["name"]) ?? "Station"
            let street = normalizedString(station["street"])
            let houseNumber = normalizedString(station["houseNumber"])
            let address = [street, houseNumber].compactMap(\.self).joined(separator: " ").nilIfEmpty
            let locality = normalizedString(station["place"])

            return FuelStationCandidate(
                identifier: identifier,
                stationName: stationName,
                address: address,
                locality: locality,
                latitude: latitude,
                longitude: longitude,
                updatedAt: Date(),
                isSelfService: nil,
                prices: prices
            )
        }
    }

    private func tileCenters(for coordinate: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let latitudeOffsets = [-0.225, 0, 0.225]
        let longitudeScale = max(cos(coordinate.latitude * .pi / 180), 0.35)
        let longitudeOffset = 0.225 / longitudeScale
        let longitudeOffsets = [-longitudeOffset, 0, longitudeOffset]

        return latitudeOffsets.flatMap { latitudeDelta in
            longitudeOffsets.map { longitudeDelta in
                CLLocationCoordinate2D(
                    latitude: coordinate.latitude + latitudeDelta,
                    longitude: coordinate.longitude + longitudeDelta
                )
            }
        }
    }
}

private func bestSnapshot(
    from candidates: [FuelStationCandidate],
    request: FuelSearchRequest,
    descriptor: FuelSourceDescriptor
) -> FuelPriceSnapshot {
    let center = CLLocation(latitude: request.coordinate.latitude, longitude: request.coordinate.longitude)
    let inRange = candidates.compactMap { candidate -> ScoredFuelStationCandidate? in
        let stationLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let distanceKilometers = center.distance(from: stationLocation) / 1_000
        guard distanceKilometers <= request.searchRadiusKilometers else {
            return nil
        }

        return ScoredFuelStationCandidate(candidate: candidate, distanceKilometers: distanceKilometers)
    }

    let diesel = bestStation(for: .diesel, in: inRange)
    let gasoline = bestStation(for: .gasoline, in: inRange)
    let status: FuelPriceStatus = if diesel != nil || gasoline != nil {
        .ready
    } else {
        .noStationsFound
    }

    let detail = if status == .ready {
        "Cheapest prices within \(Int(request.searchRadiusKilometers)) km."
    } else {
        "No priced stations found within \(Int(request.searchRadiusKilometers)) km."
    }

    return FuelPriceSnapshot(
        status: status,
        sourceName: descriptor.name,
        sourceURL: descriptor.url,
        countryCode: request.countryCode,
        countryName: request.countryName,
        searchRadiusKilometers: request.searchRadiusKilometers,
        diesel: diesel,
        gasoline: gasoline,
        fetchedAt: Date(),
        detail: detail,
        note: descriptor.note
    )
}

private func bestStation(for fuelType: FuelType, in candidates: [ScoredFuelStationCandidate]) -> FuelStationPrice? {
    let best = candidates
        .compactMap { candidate -> (ScoredFuelStationCandidate, Double)? in
            guard let price = candidate.candidate.prices[fuelType] else {
                return nil
            }

            return (candidate, price)
        }
        .min { lhs, rhs in
            if lhs.1 == rhs.1 {
                if lhs.0.distanceKilometers == rhs.0.distanceKilometers {
                    return lhs.0.candidate.stationName.localizedCaseInsensitiveCompare(rhs.0.candidate.stationName) == .orderedAscending
                }

                return lhs.0.distanceKilometers < rhs.0.distanceKilometers
            }

            return lhs.1 < rhs.1
        }

    guard let best else {
        return nil
    }

    return FuelStationPrice(
        fuelType: fuelType,
        stationName: best.0.candidate.stationName,
        address: best.0.candidate.address,
        locality: best.0.candidate.locality,
        pricePerLiter: best.1,
        distanceKilometers: best.0.distanceKilometers,
        latitude: best.0.candidate.latitude,
        longitude: best.0.candidate.longitude,
        updatedAt: best.0.candidate.updatedAt,
        isSelfService: best.0.candidate.isSelfService
    )
}

private func fetchData(from url: URL, session: URLSession) async throws -> Data {
    let (data, response) = try await session.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
        throw ProviderError.invalidResponse
    }

    return data
}

private func fuelTypeForItaly(_ description: String) -> FuelType? {
    let normalized = description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()

    if normalized == "gasolio" || normalized.hasPrefix("gasolio ") || normalized == "diesel" {
        return .diesel
    }

    if normalized == "benzina" || normalized.hasPrefix("benzina ") || normalized.contains("super senza piombo") {
        return .gasoline
    }

    return nil
}

private func firstPrice(in values: [String: Any], keys: [String]) -> Double? {
    for key in keys {
        if let price = parsePrice(values[key]) {
            return price
        }
    }

    return nil
}

private func firstAvailablePrice(values: [Any?]) -> Double? {
    for value in values {
        if let price = parsePrice(value) {
            return price
        }
    }

    return nil
}

private func parseFranceCoordinate(_ value: Any?) -> CLLocationCoordinate2D? {
    if let dictionary = value as? [String: Any] {
        if let latitude = parseDouble(dictionary["lat"]), let longitude = parseDouble(dictionary["lon"]) {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        if
            let geometry = dictionary["geometry"] as? [String: Any],
            let coordinates = geometry["coordinates"] as? [Any],
            coordinates.count >= 2,
            let longitude = parseDouble(coordinates[0]),
            let latitude = parseDouble(coordinates[1])
        {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    return nil
}

private func parseCoordinate(_ value: Any?) -> Double? {
    parseDouble(value)
}

private func parsePrice(_ value: Any?) -> Double? {
    guard let parsed = parseDouble(value), parsed > 0 else {
        return nil
    }

    return parsed
}

private func parseDouble(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
        return value
    case let value as Int:
        return Double(value)
    case let value as NSNumber:
        return value.doubleValue
    case let value as String:
        let sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(sanitized)
    default:
        return nil
    }
}

private func normalizedString(_ value: Any?) -> String? {
    if let value = value as? String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    if let value = value as? NSNumber {
        return value.stringValue.nilIfEmpty
    }

    return nil
}

private func parseDate(_ value: Any?) -> Date? {
    guard let string = normalizedString(value) else {
        return nil
    }

    let iso8601 = ISO8601DateFormatter()
    iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso8601.date(from: string) {
        return date
    }

    let fallbackISO = ISO8601DateFormatter()
    if let date = fallbackISO.date(from: string) {
        return date
    }

    for format in [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
        "dd/MM/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm",
        "HH:mm"
    ] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        if let date = formatter.date(from: string) {
            return date
        }
    }

    return nil
}

private func latestDate(_ dates: Date?...) -> Date? {
    dates.compactMap(\.self).max()
}

private struct CSVTable {
    let rows: [CSVRow]

    static func parse(data: Data, separator: Character) throws -> [CSVRow] {
        guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ProviderError.invalidResponse
        }

        let parsedRows = CSVParser.parse(string, separator: separator)
        guard let header = parsedRows.first, header.isEmpty == false else {
            return []
        }

        let normalizedHeader = header.map { CSVRow.normalizeHeader($0) }
        return parsedRows.dropFirst().compactMap { row in
            guard row.isEmpty == false else {
                return nil
            }

            return CSVRow(header: normalizedHeader, values: row)
        }
    }
}

private struct CSVRow: Sendable {
    let values: [String: String]

    init(header: [String], values: [String]) {
        var dictionary: [String: String] = [:]
        for (index, key) in header.enumerated() where index < values.count {
            dictionary[key] = values[index].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        self.values = dictionary
    }

    func string(forAny keys: [String]) -> String? {
        for key in keys {
            if let value = values[Self.normalizeHeader(key)]?.nilIfEmpty {
                return value
            }
        }

        return nil
    }

    func double(forAny keys: [String]) -> Double? {
        parseDouble(string(forAny: keys))
    }

    func bool(forAny keys: [String]) -> Bool? {
        guard let value = string(forAny: keys)?.lowercased() else {
            return nil
        }

        switch value {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }

    static func normalizeHeader(_ header: String) -> String {
        header
            .replacingOccurrences(of: "\u{feff}", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

private enum CSVParser {
    static func parse(_ string: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        let characters = Array(string)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if isInsideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == separator, isInsideQuotes == false {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), isInsideQuotes == false {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }

                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index += 1
        }

        if field.isEmpty == false || row.isEmpty == false {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
