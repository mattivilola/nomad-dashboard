import Foundation
import NomadCore

@main
struct NomadMissionDatasetBuilderCLI {
    static func main() async {
        do {
            let options = try BuilderOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(BuilderOptions.helpText)
                return
            }

            try await MissionDatasetBuilder(options: options).run()
        } catch {
            fputs("error: \(error)\n\n\(BuilderOptions.helpText)\n", stderr)
            Foundation.exit(1)
        }
    }
}

struct BuilderOptions {
    var outputPath: String
    var endpoint: URL
    var generatedAt: String
    var pauseSeconds: Double
    var showHelp: Bool

    static let defaultOutputPath = "Packages/NomadCore/Sources/NomadCore/Resources/diplomatic-missions.json"

    static let helpText = """
    Nomad diplomatic mission dataset builder

    Queries the Wikidata SPARQL endpoint (CC0) for current embassies, consulates and related posts
    and writes the bundled offline dataset. Run it via scripts/update-diplomatic-missions.sh.

    Options:
      --output <path>        Output JSON file (default: \(defaultOutputPath))
      --generated-at <date>  Override the generatedAt date, yyyy-MM-dd (default: today, UTC)
      --endpoint <url>       SPARQL endpoint (default: \(WikidataClient.defaultEndpoint.absoluteString))
      --pause <seconds>      Pause before each query (default: 2)
      --help                 Show this help
    """

    static func parse(arguments: [String]) throws -> BuilderOptions {
        var options = BuilderOptions(
            outputPath: defaultOutputPath,
            endpoint: WikidataClient.defaultEndpoint,
            generatedAt: todayUTC(),
            pauseSeconds: 2,
            showHelp: false
        )

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h":
                options.showHelp = true
            case "--output":
                options.outputPath = try value(for: argument, from: &iterator)
            case "--generated-at":
                let date = try value(for: argument, from: &iterator)
                guard date.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else {
                    throw BuilderError.invalidArgument("--generated-at expects yyyy-MM-dd, got \(date)")
                }
                options.generatedAt = date
            case "--endpoint":
                let raw = try value(for: argument, from: &iterator)
                guard let url = URL(string: raw), url.scheme == "https" else {
                    throw BuilderError.invalidArgument("--endpoint expects an https URL, got \(raw)")
                }
                options.endpoint = url
            case "--pause":
                let raw = try value(for: argument, from: &iterator)
                guard let seconds = Double(raw), seconds >= 0 else {
                    throw BuilderError.invalidArgument("--pause expects a non-negative number, got \(raw)")
                }
                options.pauseSeconds = seconds
            default:
                throw BuilderError.invalidArgument("Unknown argument \(argument)")
            }
        }

        return options
    }

    private static func value(for flag: String, from iterator: inout IndexingIterator<[String]>) throws -> String {
        guard let value = iterator.next() else {
            throw BuilderError.invalidArgument("\(flag) requires a value")
        }
        return value
    }

    private static func todayUTC() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

enum BuilderError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case emptyResult(String)

    var description: String {
        switch self {
        case let .invalidArgument(message): message
        case let .emptyResult(message): message
        }
    }
}

struct MissionDatasetBuilder {
    let options: BuilderOptions

    func run() async throws {
        let client = WikidataClient(endpoint: options.endpoint, pause: .seconds(options.pauseSeconds))
        log("Fetching diplomatic missions from Wikidata (\(options.endpoint.absoluteString))")

        let tables = try await fetchTables(client: client)
        let assembler = MissionDatasetAssembler()
        let (dataset, report) = assembler.assemble(from: tables, generatedAt: options.generatedAt)

        guard dataset.missions.count > 1_000 else {
            throw BuilderError.emptyResult(
                "Only \(dataset.missions.count) missions survived normalization; refusing to overwrite the dataset."
            )
        }

        let data = try MissionDatasetEncoder.encode(dataset)
        let outputURL = URL(fileURLWithPath: options.outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL, options: .atomic)

        printReport(report, dataset: dataset, byteCount: data.count, outputPath: outputURL.path)
    }

    // MARK: - Fetching

    private func fetchTables(client: WikidataClient) async throws -> MissionSourceTables {
        var tables = MissionSourceTables()

        tables.classKinds = try await fetchClassKinds(client: client)
        let classValues = tables.classKinds.keys.sorted().map { "wd:\($0)" }.joined(separator: " ")
        let missionPattern = "VALUES ?cls { \(classValues) } ?m wdt:P31 ?cls ."

        let coreRows = try await client.query(
            "SELECT ?m ?cls ?op ?host WHERE { \(missionPattern) OPTIONAL { ?m wdt:P137 ?op } OPTIONAL { ?m wdt:P17 ?host } }",
            label: "missions"
        )
        tables.core = coreRows.compactMap { row in
            guard let mission = row["m"]?.entityID, let kindClass = row["cls"]?.entityID else {
                return nil
            }
            return CoreRow(mission: mission, kindClass: kindClass, operatorID: row["op"]?.entityID, hostID: row["host"]?.entityID)
        }

        let isoRows = try await client.query("SELECT ?c ?code WHERE { ?c wdt:P297 ?code }", label: "ISO country codes")
        for row in isoRows {
            if let entity = row["c"]?.entityID, let code = row["code"]?.value.uppercased() {
                tables.isoCodes[entity] = code
            }
        }

        let unresolvedOperators = Set(tables.core.compactMap(\.operatorID))
            .subtracting(tables.isoCodes.keys)
            .subtracting(WikidataID.isoCodeOverrides.keys)
            .sorted()
        for start in stride(from: 0, to: unresolvedOperators.count, by: 150) {
            let chunk = unresolvedOperators[start..<min(start + 150, unresolvedOperators.count)]
            let rows = try await client.query(
                """
                SELECT ?op ?code WHERE {
                  VALUES ?op { \(chunk.map { "wd:\($0)" }.joined(separator: " ")) }
                  ?op wdt:P31 wd:\(WikidataID.foreignAffairsMinistry) ; wdt:P17 ?country .
                  ?country wdt:P297 ?code .
                }
                """,
                label: "foreign affairs ministries"
            )
            for row in rows {
                if let entity = row["op"]?.entityID, let code = row["code"]?.value.uppercased() {
                    tables.ministryCountryCodes[entity] = code
                }
            }
        }

        let closedRows = try await client.query(
            """
            SELECT DISTINCT ?m WHERE {
              \(missionPattern)
              ?m wdt:P576|wdt:P582|wdt:P3999 ?closed .
              FILTER(?closed < NOW())
            }
            """,
            label: "closed missions"
        )
        tables.closedMissions = Set(closedRows.compactMap { $0["m"]?.entityID })

        let endedRows = try await client.query(
            """
            SELECT ?m ?property ?v WHERE {
              \(missionPattern)
              {
                ?m p:P137 ?s . ?s ps:P137 ?v . BIND("operatorOf" AS ?property)
              } UNION {
                ?m p:P17 ?s . ?s ps:P17 ?v . BIND("host" AS ?property)
              } UNION {
                ?m p:P31 ?s . ?s ps:P31 ?v . BIND("kindClass" AS ?property)
              }
              ?s pq:P582|pq:P576 ?ended .
              FILTER(?ended < NOW())
            }
            """,
            label: "ended statements"
        )
        tables.endedStatements = Set(endedRows.compactMap { row in
            guard
                let mission = row["m"]?.entityID,
                let property = row["property"].flatMap({ EndedStatementProperty(rawValue: $0.value) }),
                let value = row["v"]?.entityID
            else {
                return nil
            }
            return EndedStatement(mission: mission, property: property, value: value)
        })

        let labelRows = try await client.query(
            """
            SELECT ?m ?label WHERE {
              \(missionPattern)
              ?m rdfs:label ?label .
              FILTER(LANG(?label) IN ("en", "mul"))
            }
            """,
            label: "labels"
        )
        for row in labelRows {
            if let mission = row["m"]?.entityID, let label = row["label"] {
                tables.labels[mission, default: []].append(LocalizedText(text: label.value, language: label.language ?? ""))
            }
        }

        let coordinateRows = try await client.query(
            "SELECT ?m ?coord WHERE { \(missionPattern) ?m wdt:P625 ?coord }",
            label: "coordinates (P625)"
        )
        for row in coordinateRows {
            if let mission = row["m"]?.entityID, let coordinate = row["coord"].flatMap({ Coordinate(wkt: $0.value) }) {
                tables.coordinates[mission, default: []].append(coordinate)
            }
        }

        let websiteRows = try await client.query(
            "SELECT ?m ?site WHERE { \(missionPattern) ?m wdt:P856 ?site }",
            label: "websites (P856)"
        )
        for row in websiteRows {
            if let mission = row["m"]?.entityID, let site = row["site"]?.value {
                tables.websites[mission, default: []].append(site)
            }
        }

        let addressRows = try await client.query(
            "SELECT ?m ?address WHERE { \(missionPattern) ?m wdt:P6375 ?address }",
            label: "street addresses (P6375)"
        )
        for row in addressRows {
            if let mission = row["m"]?.entityID, let address = row["address"] {
                tables.addresses[mission, default: []].append(LocalizedText(text: address.value, language: address.language ?? ""))
            }
        }

        for (property, wikidataProperty) in [
            (LocationProperty.location, "P276"),
            (.headquarters, "P159"),
            (.administrativeArea, "P131")
        ] {
            let rows = try await client.query(
                """
                SELECT ?m ?place ?coord ?name WHERE {
                  \(missionPattern)
                  ?m wdt:\(wikidataProperty) ?place .
                  OPTIONAL { ?place wdt:P625 ?coord }
                  OPTIONAL { ?place rdfs:label ?name . FILTER(LANG(?name) IN ("en", "mul")) }
                }
                """,
                label: "places (\(wikidataProperty))"
            )
            var byMission = [String: [LocationRow]]()
            for row in rows {
                guard let mission = row["m"]?.entityID, let place = row["place"]?.entityID else {
                    continue
                }
                byMission[mission, default: []].append(
                    LocationRow(
                        location: place,
                        coordinate: row["coord"].flatMap { Coordinate(wkt: $0.value) },
                        name: row["name"]?.value
                    )
                )
            }
            tables.locations[property] = byMission
        }

        return tables
    }

    /// Maps every class under the supported roots to a kind. Roots are applied from the broadest to
    /// the most specific, so a subclass keeps the most specific kind it belongs to.
    private func fetchClassKinds(client: WikidataClient) async throws -> [String: DiplomaticMissionKind] {
        let roots: [(id: String, kind: DiplomaticMissionKind)] = [
            (WikidataID.consulate, .consulate),
            (WikidataID.embassy, .embassy),
            (WikidataID.interestsSection, .other),
            (WikidataID.consulateGeneral, .consulateGeneral),
            (WikidataID.honoraryConsulate, .honoraryConsulate)
        ]

        var kinds = [String: DiplomaticMissionKind]()
        for root in roots {
            let rows = try await client.query("SELECT ?c WHERE { ?c wdt:P279* wd:\(root.id) }", label: "classes under \(root.id)")
            for row in rows {
                if let classID = row["c"]?.entityID {
                    kinds[classID] = root.kind
                }
            }
        }

        for excluded in WikidataID.excludedClasses {
            kinds[excluded] = nil
        }
        return kinds
    }

    // MARK: - Reporting

    private func printReport(_ report: AssemblyReport, dataset: DiplomaticMissionDataset, byteCount: Int, outputPath: String) {
        let megabytes = String(format: "%.2f", Double(byteCount) / 1_000_000)
        log("")
        log("Wrote \(dataset.missions.count) missions to \(outputPath) (\(byteCount) bytes, \(megabytes) MB)")
        log("Source items considered: \(report.sourceMissions)")
        log("Kept by kind:")
        for kind in DiplomaticMissionKind.allCases {
            log("  \(kind.rawValue): \(report.countsByKind[kind, default: 0])")
        }
        log("Excluded:")
        for (reason, count) in report.excluded.sorted(by: { $0.key < $1.key }) {
            log("  \(reason): \(count)")
        }
        log("With approximate (city-level) coordinates: \(report.approximateLocations)")
        log("With website: \(report.withWebsite), address: \(report.withAddress), city: \(report.withCity)")
        log("Names synthesized from missing labels: \(report.synthesizedNames)")
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// Writes the dataset as valid JSON with one mission per line, so regenerated files diff cleanly.
enum MissionDatasetEncoder {
    static func encode(_ dataset: DiplomaticMissionDataset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let header = try encoder.encode(["source": dataset.source, "generatedAt": dataset.generatedAt])
        let headerBody = String(decoding: header, as: UTF8.self).dropFirst().dropLast()

        var output = "{\(headerBody),\"missions\":[\n"
        output += try dataset.missions
            .map { try String(decoding: encoder.encode($0), as: UTF8.self) }
            .joined(separator: ",\n")
        output += "\n]}\n"
        return Data(output.utf8)
    }
}
