import Foundation

/// A SPARQL result row: variable name to its string value (entity URIs reduced to `Q123`).
typealias SPARQLRow = [String: SPARQLValue]

struct SPARQLValue: Equatable {
    var value: String
    var language: String?

    /// `http://www.wikidata.org/entity/Q42` becomes `Q42`; other values are returned unchanged.
    var entityID: String {
        guard value.hasPrefix(WikidataClient.entityPrefix) else {
            return value
        }
        return String(value.dropFirst(WikidataClient.entityPrefix.count))
    }
}

enum WikidataClientError: Error, CustomStringConvertible {
    case badStatus(Int, String)
    case malformedResponse(String)
    case failedAfterRetries(String)

    var description: String {
        switch self {
        case let .badStatus(status, snippet): "Wikidata returned HTTP \(status): \(snippet)"
        case let .malformedResponse(message): "Unexpected Wikidata response: \(message)"
        case let .failedAfterRetries(message): "Wikidata request failed after retries: \(message)"
        }
    }
}

/// Minimal Wikidata Query Service client. Wikidata requires a descriptive User-Agent and asks
/// clients to run one query at a time, so callers should await queries sequentially.
struct WikidataClient {
    static let entityPrefix = "http://www.wikidata.org/entity/"
    static let defaultEndpoint = URL(string: "https://query.wikidata.org/sparql")!
    static let userAgent = "NomadDashboardMissionDatasetBuilder/1.0 (https://github.com/mattivilola/nomad-dashboard; build-time dataset tool)"

    let endpoint: URL
    let session: URLSession
    let pause: Duration
    let maxAttempts: Int

    init(
        endpoint: URL = WikidataClient.defaultEndpoint,
        pause: Duration = .seconds(2),
        maxAttempts: Int = 4
    ) {
        self.endpoint = endpoint
        self.pause = pause
        self.maxAttempts = maxAttempts

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 150
        session = URLSession(configuration: configuration)
    }

    func query(_ sparql: String, label: String) async throws -> [SPARQLRow] {
        var lastFailure = "no attempt made"

        for attempt in 1...maxAttempts {
            try await Task.sleep(for: pause)
            do {
                let rows = try await performQuery(sparql)
                FileHandle.standardError.write(Data("  \(label): \(rows.count) rows\n".utf8))
                return rows
            } catch {
                lastFailure = "\(error)"
                FileHandle.standardError.write(Data("  \(label): attempt \(attempt) failed (\(lastFailure))\n".utf8))
                try await Task.sleep(for: .seconds(Double(attempt) * 10))
            }
        }

        throw WikidataClientError.failedAfterRetries("\(label): \(lastFailure)")
    }

    private func performQuery(_ sparql: String) async throws -> [SPARQLRow] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedQuery = sparql.addingPercentEncoding(withAllowedCharacters: unreserved) ?? sparql
        request.httpBody = Data("query=\(encodedQuery)".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WikidataClientError.malformedResponse("not an HTTP response")
        }
        guard http.statusCode == 200 else {
            throw WikidataClientError.badStatus(http.statusCode, String(decoding: data.prefix(160), as: UTF8.self))
        }

        return try Self.parseRows(data)
    }

    static func parseRows(_ data: Data) throws -> [SPARQLRow] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [String: Any],
            let bindings = results["bindings"] as? [[String: Any]]
        else {
            throw WikidataClientError.malformedResponse("missing results.bindings")
        }

        return bindings.map { binding in
            binding.reduce(into: SPARQLRow()) { row, entry in
                guard let object = entry.value as? [String: Any], let value = object["value"] as? String else {
                    return
                }
                row[entry.key] = SPARQLValue(value: value, language: object["xml:lang"] as? String)
            }
        }
    }
}
