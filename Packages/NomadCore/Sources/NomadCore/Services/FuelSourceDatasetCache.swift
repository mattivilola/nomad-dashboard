import Foundation

/// Caches the small, public national datasets used to select nearby fuel stations.
/// It deliberately accepts only the three known public URLs, so no user input,
/// credentials, or arbitrary response URLs can be persisted.
actor FuelSourceDatasetCache {
    private static let maximumPayloadByteCount = 32 * 1_024 * 1_024
    private let directory: URL?
    private let ttl: TimeInterval
    private var memory: [String: Record] = [:]

    init(directory: URL?, ttl: TimeInterval = 6 * 60 * 60) {
        self.directory = directory
        self.ttl = ttl
    }

    func fetch(
        from url: URL,
        forceRefresh: Bool,
        session: URLSession,
        descriptor: FuelSourceDescriptor
    ) async throws -> FuelHTTPFetchResult {
        try Task.checkCancellation()
        guard let identifier = Self.identifier(for: url) else {
            return try await fetchData(from: url, session: session, descriptor: descriptor)
        }

        let cached = memory[url.absoluteString] ?? loadPersistedRecord(identifier: identifier, url: url)
        if let cached {
            memory[url.absoluteString] = cached
            if !forceRefresh, cached.isFresh(ttl: ttl) {
                return cached.fetchResult(transport: .urlSession)
            }
        }

        var requestHeaders: [String: String] = [:]
        if let eTag = cached?.eTag {
            requestHeaders["If-None-Match"] = eTag
        }
        if let lastModified = cached?.lastModified {
            requestHeaders["If-Modified-Since"] = lastModified
        }

        let fetched = try await fetchData(
            from: url,
            session: session,
            descriptor: descriptor,
            headers: requestHeaders,
            allowsNotModified: cached != nil
        )
        if fetched.response.statusCode == 304, let cached {
            let refreshed = cached.refreshed(at: Date())
            memory[url.absoluteString] = refreshed
            persist(refreshed, identifier: identifier)
            return refreshed.fetchResult(transport: fetched.transport)
        }

        guard fetched.data.count <= Self.maximumPayloadByteCount else {
            throw ProviderError.invalidResponse
        }

        let record = Record(
            url: url.absoluteString,
            data: fetched.data,
            eTag: Self.header("ETag", in: fetched.response),
            lastModified: Self.header("Last-Modified", in: fetched.response),
            mimeType: fetched.response.mimeType,
            fetchedAt: Date()
        )
        memory[url.absoluteString] = record
        persist(record, identifier: identifier)
        return fetched
    }

    private func loadPersistedRecord(identifier: String, url: URL) -> Record? {
        guard let directory else { return nil }
        let fileURL = directory.appendingPathComponent("fuel-source-\(identifier).json")
        guard
            let data = try? Data(contentsOf: fileURL),
            data.count <= Self.maximumPayloadByteCount,
            let record = try? JSONDecoder().decode(Record.self, from: data),
            record.url == url.absoluteString,
            record.data.isEmpty == false
        else { return nil }
        return record
    }

    private func persist(_ record: Record, identifier: String) {
        guard let directory, let data = try? JSONEncoder().encode(record) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("fuel-source-\(identifier).json"), options: .atomic)
        } catch {
            // Persistence is an optimization. Network results remain usable.
        }
    }

    private static func identifier(for url: URL) -> String? {
        switch url.absoluteString {
        case "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/": "spain"
        case "https://www.mimit.gov.it/images/exportCSV/anagrafica_impianti_attivi.csv": "italy-stations"
        case "https://www.mimit.gov.it/images/exportCSV/prezzo_alle_8.csv": "italy-prices"
        default: nil
        }
    }

    private static func header(_ name: String, in response: HTTPURLResponse) -> String? {
        response.allHeaderFields.first { String(describing: $0.key).caseInsensitiveCompare(name) == .orderedSame }
            .map { String(describing: $0.value) }
    }

    private struct Record: Codable {
        let url: String
        let data: Data
        let eTag: String?
        let lastModified: String?
        let mimeType: String?
        let fetchedAt: Date

        func isFresh(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(fetchedAt) < ttl
        }

        func refreshed(at date: Date) -> Record {
            Record(url: url, data: data, eTag: eTag, lastModified: lastModified, mimeType: mimeType, fetchedAt: date)
        }

        func fetchResult(transport: FuelHTTPFetchResult.Transport) -> FuelHTTPFetchResult {
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: mimeType.map { ["Content-Type": $0] })!
            return FuelHTTPFetchResult(url: URL(string: url)!, data: data, response: response, startedAt: fetchedAt, finishedAt: fetchedAt, transport: transport)
        }
    }
}
