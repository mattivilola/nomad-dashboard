import Foundation
import NomadCore

/// Wikidata entity and property ids this tool depends on. Verified against the live Wikidata
/// labels on 2026-10-12.
enum WikidataID {
    // Classes (the `P31/P279*` roots).
    static let embassy = "Q3917681"
    static let consulate = "Q7843791"
    static let consulateGeneral = "Q372690"
    static let honoraryConsulate = "Q23891529"
    static let interestsSection = "Q94158456"

    /// Subclasses of `embassy` / `consulate` that are not diplomatic posts of a state in a host
    /// country: Estonia's "data embassy" servers and a Commons category-style class of door plates.
    static let excludedClasses: Set<String> = ["Q104856868", "Q130479046"]

    /// "foreign affairs ministry": several states (Germany's Federal Foreign Office, Vietnam, China,
    /// Russia, ...) are recorded as the operator through their ministry rather than the state.
    static let foreignAffairsMinistry = "Q20901295"

    /// States that Wikidata models as items without an ISO code (P297) even though they are the
    /// state that runs or hosts missions: the Netherlands as a constituent country of the Kingdom,
    /// the Kingdom of Denmark (Denmark proper has its own item), and the Holy See, whose nunciatures
    /// are the Vatican City State's diplomatic posts.
    static let isoCodeOverrides: [String: String] = [
        "Q55": "NL",
        "Q756617": "DK",
        "Q159583": "VA"
    ]
}

/// One simple lookup result: all values are plain strings, entity ids already reduced to `Q123`.
struct CoreRow: Equatable {
    var mission: String
    var kindClass: String
    var operatorID: String?
    var hostID: String?
}

enum EndedStatementProperty: String {
    case operatorOf
    case host
    case kindClass
}

struct EndedStatement: Hashable {
    var mission: String
    var property: EndedStatementProperty
    var value: String
}

struct LocalizedText: Equatable {
    var text: String
    var language: String
}

struct LocationRow: Equatable {
    var location: String
    var coordinate: Coordinate?
    var name: String?
}

struct Coordinate: Equatable, Comparable {
    var latitude: Double
    var longitude: Double

    static func < (lhs: Coordinate, rhs: Coordinate) -> Bool {
        (lhs.latitude, lhs.longitude) < (rhs.latitude, rhs.longitude)
    }

    /// Parses a Wikidata WKT literal, `Point(longitude latitude)`.
    init?(wkt: String) {
        let trimmed = wkt.trimmingCharacters(in: .whitespaces)
        guard
            trimmed.hasPrefix("Point("), trimmed.hasSuffix(")")
        else {
            return nil
        }

        let parts = trimmed.dropFirst("Point(".count).dropLast().split(separator: " ")
        guard
            parts.count == 2,
            let longitude = Double(parts[0]), let latitude = Double(parts[1]),
            (-90...90).contains(latitude), (-180...180).contains(longitude),
            // Wikidata uses (0, 0) as a placeholder for "unknown" surprisingly often.
            (latitude == 0 && longitude == 0) == false
        else {
            return nil
        }

        self.latitude = latitude
        self.longitude = longitude
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Which mission property a location row came from, in order of preference for the coordinate.
enum LocationProperty: CaseIterable {
    /// P276 location.
    case location
    /// P159 headquarters location.
    case headquarters
    /// P131 located in the administrative territorial entity.
    case administrativeArea
}

struct MissionSourceTables {
    /// Wikidata class id to the kind it maps to, for every class under the supported roots.
    var classKinds: [String: DiplomaticMissionKind] = [:]
    var core: [CoreRow] = []
    /// Entity id (state or territory) to its ISO 3166-1 alpha-2 code (P297).
    var isoCodes: [String: String] = [:]
    /// Operators that are a foreign affairs ministry (P31 `Q20901295`) mapped to the ISO code of
    /// their country (P17 then P297).
    var ministryCountryCodes: [String: String] = [:]
    /// Missions with a dissolved/end/closure date in the past (P576, P582, P3999).
    var closedMissions: Set<String> = []
    var endedStatements: Set<EndedStatement> = []
    var labels: [String: [LocalizedText]] = [:]
    var coordinates: [String: [Coordinate]] = [:]
    var websites: [String: [String]] = [:]
    var addresses: [String: [LocalizedText]] = [:]
    var locations: [LocationProperty: [String: [LocationRow]]] = [:]
}

struct AssemblyReport: Equatable {
    var sourceMissions = 0
    var excluded: [String: Int] = [:]
    var countsByKind: [DiplomaticMissionKind: Int] = [:]
    var synthesizedNames = 0
    var approximateLocations = 0
    var withWebsite = 0
    var withAddress = 0
    var withCity = 0

    mutating func exclude(_ reason: String) {
        excluded[reason, default: 0] += 1
    }
}

struct MissionDatasetAssembler {
    /// ISO 3166-1 codes currently assigned, plus Kosovo's user-assigned XK which Wikidata uses.
    /// Historic codes (YU, DD, AN, ...) are rejected: those states no longer receive travellers.
    let validCountryCodes: Set<String>
    let englishRegionName: @Sendable (String) -> String?

    init(
        validCountryCodes: Set<String> = MissionDatasetAssembler.currentISOCountryCodes,
        englishRegionName: @escaping @Sendable (String) -> String? = MissionDatasetAssembler.localizedEnglishRegionName
    ) {
        self.validCountryCodes = validCountryCodes
        self.englishRegionName = englishRegionName
    }

    static let currentISOCountryCodes: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 })
        .union(["XK"])

    static let localizedEnglishRegionName: @Sendable (String) -> String? = { code in
        Locale(identifier: "en_US").localizedString(forRegionCode: code)
    }

    /// Order of preference when one mission carries several kind classes: the most specific wins.
    /// Honorary consulates and consulates-general are subclasses of consulate, so they beat it.
    private static let kindPrecedence: [DiplomaticMissionKind] = [
        .honoraryConsulate, .consulateGeneral, .embassy, .consulate, .other
    ]

    func assemble(from tables: MissionSourceTables, generatedAt: String) -> (dataset: DiplomaticMissionDataset, report: AssemblyReport) {
        var report = AssemblyReport()
        var candidates = [DiplomaticMission]()

        let rowsByMission = Dictionary(grouping: tables.core, by: \.mission)
        for missionID in rowsByMission.keys.sorted(by: Self.idOrder) {
            report.sourceMissions += 1
            let rows = rowsByMission[missionID] ?? []

            if tables.closedMissions.contains(missionID) {
                report.exclude("closed (dissolved, ended or closure date in the past)")
                continue
            }

            let classIDs = Set(rows.map(\.kindClass)).filter {
                tables.endedStatements.contains(EndedStatement(mission: missionID, property: .kindClass, value: $0)) == false
            }
            let kinds = Set(classIDs.compactMap { tables.classKinds[$0] })
            guard let kind = Self.kindPrecedence.first(where: kinds.contains) else {
                report.exclude("no current mission class")
                continue
            }

            let operators = Set(rows.compactMap(\.operatorID)).filter {
                tables.endedStatements.contains(EndedStatement(mission: missionID, property: .operatorOf, value: $0)) == false
            }
            let hosts = Set(rows.compactMap(\.hostID)).filter {
                tables.endedStatements.contains(EndedStatement(mission: missionID, property: .host, value: $0)) == false
            }
            guard operators.isEmpty == false else {
                report.exclude("missing operator (P137)")
                continue
            }
            guard hosts.isEmpty == false else {
                report.exclude("missing host country (P17)")
                continue
            }

            let sendingCodes = Set(operators.compactMap { countryCode(for: $0, in: tables) })
            let hostCodes = Set(hosts.compactMap { countryCode(for: $0, in: tables) })
            guard let sending = sendingCodes.first, sendingCodes.count == 1 else {
                report.exclude(sendingCodes.isEmpty ? "operator is not a country (no P297)" : "several operator countries")
                continue
            }
            guard let host = hostCodes.first, hostCodes.count == 1 else {
                report.exclude(hostCodes.isEmpty ? "host is not a country (no P297)" : "several host countries")
                continue
            }
            guard validCountryCodes.contains(sending), validCountryCodes.contains(host) else {
                report.exclude("historic or non-ISO country code")
                continue
            }
            guard sending != host else {
                report.exclude("operator equals host country")
                continue
            }

            guard let location = resolveLocation(for: missionID, tables: tables) else {
                report.exclude("missing coordinates")
                continue
            }

            let (name, synthesized) = resolveName(for: missionID, kind: kind, sending: sending, host: host, tables: tables)
            candidates.append(
                DiplomaticMission(
                    id: missionID,
                    sendingCountry: sending,
                    hostCountry: host,
                    kind: kind,
                    name: name,
                    city: location.city,
                    latitude: Self.rounded(location.coordinate.latitude),
                    longitude: Self.rounded(location.coordinate.longitude),
                    address: resolveAddress(for: missionID, tables: tables),
                    website: resolveWebsite(for: missionID, tables: tables),
                    isApproximateLocation: location.isApproximate
                )
            )
            if synthesized {
                report.synthesizedNames += 1
            }
        }

        let missions = deduplicated(candidates, report: &report).sorted(by: Self.missionOrder)
        for mission in missions {
            report.countsByKind[mission.kind, default: 0] += 1
            report.approximateLocations += mission.isApproximateLocation ? 1 : 0
            report.withWebsite += mission.website == nil ? 0 : 1
            report.withAddress += mission.address == nil ? 0 : 1
            report.withCity += mission.city == nil ? 0 : 1
        }

        return (DiplomaticMissionDataset(generatedAt: generatedAt, missions: missions), report)
    }

    // MARK: - Field resolution

    private func countryCode(for entityID: String, in tables: MissionSourceTables) -> String? {
        tables.isoCodes[entityID]
            ?? WikidataID.isoCodeOverrides[entityID]
            ?? tables.ministryCountryCodes[entityID]
    }

    private struct ResolvedLocation {
        var coordinate: Coordinate
        var city: String?
        var isApproximate: Bool
    }

    /// The mission's own point (P625) is the only coordinate treated as exact. Everything else is
    /// the centre of the place the mission sits in, so it is flagged approximate.
    private func resolveLocation(for missionID: String, tables: MissionSourceTables) -> ResolvedLocation? {
        // City label: a headquarters or administrative place is nearly always the city, whereas P276
        // frequently names a building.
        let cityName = [LocationProperty.headquarters, .administrativeArea].lazy
            .compactMap { property in
                tables.locations[property]?[missionID]?
                    .compactMap(\.name)
                    .sorted()
                    .first
            }
            .first

        if let own = tables.coordinates[missionID]?.sorted().first {
            return ResolvedLocation(coordinate: own, city: cityName, isApproximate: false)
        }

        for property in LocationProperty.allCases {
            if let coordinate = tables.locations[property]?[missionID]?.compactMap(\.coordinate).sorted().first {
                return ResolvedLocation(coordinate: coordinate, city: cityName, isApproximate: true)
            }
        }
        return nil
    }

    private func resolveName(
        for missionID: String,
        kind: DiplomaticMissionKind,
        sending: String,
        host: String,
        tables: MissionSourceTables
    ) -> (name: String, synthesized: Bool) {
        let labels = tables.labels[missionID] ?? []
        let label = ["en", "mul"].lazy
            .compactMap { language in labels.filter { $0.language == language }.map(\.text).sorted().first }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }

        if let label {
            return (Self.capitalizingFirstLetter(label), false)
        }

        let sendingName = englishRegionName(sending) ?? sending
        let hostName = englishRegionName(host) ?? host
        return ("\(kind.title) of \(sendingName) in \(hostName)", true)
    }

    private func resolveAddress(for missionID: String, tables: MissionSourceTables) -> String? {
        let addresses = tables.addresses[missionID] ?? []
        let preferred = addresses.filter { $0.language == "en" } + addresses.filter { $0.language != "en" }
        return preferred.lazy
            .map { Self.singleLine($0.text) }
            .first { $0.isEmpty == false && $0.count <= 240 }
    }

    /// Only http(s) URLs are kept, https preferred, so the UI can open them safely.
    private func resolveWebsite(for missionID: String, tables: MissionSourceTables) -> String? {
        let urls = (tables.websites[missionID] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { raw in
                guard let components = URLComponents(string: raw), let host = components.host, host.contains(".") else {
                    return false
                }
                return ["http", "https"].contains(components.scheme?.lowercased() ?? "")
            }
            .sorted()
        return urls.first { $0.lowercased().hasPrefix("https://") } ?? urls.first
    }

    // MARK: - Deduplication and ordering

    /// Wikidata sometimes carries the same post twice (for example an old and a new item). Two items
    /// with the same route, kind and name are one mission; keep the one with the best data.
    private func deduplicated(_ missions: [DiplomaticMission], report: inout AssemblyReport) -> [DiplomaticMission] {
        var best = [String: DiplomaticMission]()
        for mission in missions {
            let key = [mission.sendingCountry, mission.hostCountry, mission.kind.rawValue, mission.name.lowercased()]
                .joined(separator: "|")
            guard let existing = best[key] else {
                best[key] = mission
                continue
            }
            report.exclude("duplicate of another item (same route, kind and name)")
            if Self.quality(of: mission) > Self.quality(of: existing) {
                best[key] = mission
            }
        }
        return Array(best.values)
    }

    private static func quality(of mission: DiplomaticMission) -> Int {
        var score = 0
        score += mission.isApproximateLocation ? 0 : 4
        score += mission.website == nil ? 0 : 2
        score += mission.address == nil ? 0 : 1
        return score
    }

    private static func missionOrder(_ lhs: DiplomaticMission, _ rhs: DiplomaticMission) -> Bool {
        if lhs.sendingCountry != rhs.sendingCountry {
            return lhs.sendingCountry < rhs.sendingCountry
        }
        if lhs.hostCountry != rhs.hostCountry {
            return lhs.hostCountry < rhs.hostCountry
        }
        let lhsRank = kindOrder(lhs.kind), rhsRank = kindOrder(rhs.kind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return idOrder(lhs.id, rhs.id)
    }

    private static func kindOrder(_ kind: DiplomaticMissionKind) -> Int {
        switch kind {
        case .embassy: 0
        case .consulateGeneral: 1
        case .consulate: 2
        case .honoraryConsulate: 3
        case .other: 4
        }
    }

    /// Numeric order of Wikidata ids (`Q9` before `Q10`).
    static func idOrder(_ lhs: String, _ rhs: String) -> Bool {
        let lhsNumber = Int(lhs.dropFirst()), rhsNumber = Int(rhs.dropFirst())
        if let lhsNumber, let rhsNumber, lhsNumber != rhsNumber {
            return lhsNumber < rhsNumber
        }
        return lhs < rhs
    }

    // MARK: - Text helpers

    /// Four decimals is about 11 m, finer than the city-level coordinates most missions carry.
    static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
            .joined(separator: ", ")
    }
}
