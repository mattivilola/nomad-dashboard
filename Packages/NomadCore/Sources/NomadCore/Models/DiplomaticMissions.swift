import Foundation

// Bundled, offline directory of embassies and consulates.
//
// Source: Wikidata (CC0), extracted at build time by `scripts/update-diplomatic-missions.sh`
// into `Resources/diplomatic-missions.json`. Nothing is fetched at runtime and the user's
// citizenship and location are only ever compared against this local dataset.
//
// The dataset is community maintained: it can be incomplete or stale, and most coordinates are the
// centre of the mission's city rather than the building (see `isApproximateLocation`). Always send
// users to the mission's own website or their government's travel pages for opening hours,
// telephone numbers and emergency contacts.

/// What kind of diplomatic post a mission is. Raw values are the on-disk strings.
public enum DiplomaticMissionKind: String, Codable, CaseIterable, Sendable {
    case embassy
    case consulateGeneral
    case consulate
    case honoraryConsulate
    case other

    /// User-facing label.
    public var title: String {
        switch self {
        case .embassy: "Embassy"
        case .consulateGeneral: "Consulate-general"
        case .consulate: "Consulate"
        case .honoraryConsulate: "Honorary consulate"
        case .other: "Mission"
        }
    }

    /// Lower is more capable for a citizen in trouble: embassies and consulates-general issue
    /// emergency travel documents and run consular crisis response, plain consulates handle most
    /// consular services, honorary consulates are staffed by a local volunteer with limited powers.
    var rank: Int {
        switch self {
        case .embassy: 0
        case .consulateGeneral: 1
        case .consulate: 2
        case .other: 3
        case .honoraryConsulate: 4
        }
    }

    /// Honorary consulates are run by a local volunteer and usually cannot issue passports or
    /// emergency travel documents, so they are never ranked ahead of a career mission.
    var isHonorary: Bool {
        self == .honoraryConsulate
    }
}

/// One embassy, consulate or similar post of a sending state in a host country.
public struct DiplomaticMission: Codable, Equatable, Sendable, Identifiable {
    /// Wikidata item id, for example `Q106303613`.
    public let id: String
    /// Upper-case ISO 3166-1 alpha-2 code of the state that operates the mission.
    public let sendingCountry: String
    /// Upper-case ISO 3166-1 alpha-2 code of the country the mission is in.
    public let hostCountry: String
    public let kind: DiplomaticMissionKind
    public let name: String
    public let city: String?
    public let latitude: Double
    public let longitude: Double
    /// Street address as recorded on Wikidata, in the language it was entered in.
    public let address: String?
    /// Official website, always an http(s) URL string.
    public let website: String?
    /// True when the coordinate is the centre of the city or district rather than the building.
    /// Good for "nearest mission" ranking, wrong for dropping a map pin on a street.
    public let isApproximateLocation: Bool

    public init(
        id: String,
        sendingCountry: String,
        hostCountry: String,
        kind: DiplomaticMissionKind,
        name: String,
        city: String? = nil,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        website: String? = nil,
        isApproximateLocation: Bool = false
    ) {
        self.id = id
        self.sendingCountry = sendingCountry
        self.hostCountry = hostCountry
        self.kind = kind
        self.name = name
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.website = website
        self.isApproximateLocation = isApproximateLocation
    }

    public var websiteURL: URL? {
        website.flatMap(URL.init(string:))
    }

    /// Short on-disk keys keep the bundled file around 2 MB (about 10,000 missions).
    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case sendingCountry = "s"
        case hostCountry = "h"
        case kind = "k"
        case name = "n"
        case city = "c"
        case latitude = "la"
        case longitude = "lo"
        case address = "a"
        case website = "w"
        case isApproximateLocation = "x"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sendingCountry = try container.decode(String.self, forKey: .sendingCountry)
        hostCountry = try container.decode(String.self, forKey: .hostCountry)
        kind = try container.decode(DiplomaticMissionKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        isApproximateLocation = try container.decodeIfPresent(Bool.self, forKey: .isApproximateLocation) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sendingCountry, forKey: .sendingCountry)
        try container.encode(hostCountry, forKey: .hostCountry)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(website, forKey: .website)
        if isApproximateLocation {
            try container.encode(true, forKey: .isApproximateLocation)
        }
    }
}

/// The on-disk file: a provenance header plus the missions.
public struct DiplomaticMissionDataset: Codable, Equatable, Sendable {
    public static let wikidataSource = "Wikidata (CC0)"

    public let source: String
    /// ISO 8601 calendar date (`yyyy-MM-dd`) the dataset was generated.
    public let generatedAt: String
    public let missions: [DiplomaticMission]

    public init(source: String = DiplomaticMissionDataset.wikidataSource, generatedAt: String, missions: [DiplomaticMission]) {
        self.source = source
        self.generatedAt = generatedAt
        self.missions = missions
    }
}

/// A mission together with how far it is from the traveller, when the position is known.
public struct DiplomaticMissionMatch: Equatable, Sendable, Identifiable {
    public let mission: DiplomaticMission
    /// Great-circle distance in kilometres from the supplied coordinate, nil without a coordinate.
    public let distanceKilometers: Double?

    public var id: String {
        mission.id
    }

    public init(mission: DiplomaticMission, distanceKilometers: Double?) {
        self.mission = mission
        self.distanceKilometers = distanceKilometers
    }
}

/// An immutable, indexed set of missions. `DiplomaticMissionIndex.bundled` is the shipped dataset;
/// tests inject their own.
public struct DiplomaticMissionIndex: Sendable {
    /// The dataset bundled with NomadCore, decoded once on first use. An unreadable resource yields
    /// an empty index rather than a crash, so the card simply has nothing to show.
    public static let bundled = DiplomaticMissionIndex(bundle: .module)

    public let generatedAt: String?
    public let source: String?
    /// Every mission in the index, in the order given.
    public let missions: [DiplomaticMission]
    private let missionsByRoute: [Route: [DiplomaticMission]]

    private struct Route: Hashable, Sendable {
        let sending: String
        let host: String
    }

    public init(missions: [DiplomaticMission], source: String? = nil, generatedAt: String? = nil) {
        self.source = source
        self.generatedAt = generatedAt
        self.missions = missions
        missionsByRoute = Dictionary(grouping: missions) {
            Route(sending: $0.sendingCountry.uppercased(), host: $0.hostCountry.uppercased())
        }
    }

    init(bundle: Bundle) {
        guard
            let url = bundle.url(forResource: "diplomatic-missions", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let dataset = try? JSONDecoder().decode(DiplomaticMissionDataset.self, from: data)
        else {
            self.init(missions: [])
            return
        }

        self.init(missions: dataset.missions, source: dataset.source, generatedAt: dataset.generatedAt)
    }

    func missions(of sendingCountry: String, in hostCountry: String) -> [DiplomaticMission] {
        missionsByRoute[Route(sending: sendingCountry.normalizedCountryCode, host: hostCountry.normalizedCountryCode)] ?? []
    }
}

public enum DiplomaticMissionDirectory {
    /// The 27 EU member states (ISO 3166-1 alpha-2), as of 2026. Their citizens are entitled to
    /// consular protection from any other member state's mission when their own state has none in
    /// the country (TFEU Art. 20(2)(c), Art. 23; Council Directive (EU) 2015/637).
    public static let euMemberStates: [String] = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU",
        "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK"
    ]

    /// Nordic states (ISO 3166-1 alpha-2). Nordic cooperation (Helsinki Treaty and Nordic consular
    /// cooperation): foreign-service officials assist citizens of other Nordic countries that are not
    /// represented locally. This is a cooperative fallback, not an individual legal entitlement.
    /// Norway and Iceland are not EU members, so this is the only fallback they get.
    public static let nordicStates: [String] = ["DK", "FI", "IS", "NO", "SE"]

    /// Distances closer than this are treated as equally near, because a city-level coordinate is
    /// accurate to about this much. Within the same bucket the more capable kind wins.
    static let distanceBucketKilometers = 5.0

    /// Missions the sending state runs in the host country, most capable kind first.
    public static func missions(
        of sendingCountry: String,
        in hostCountry: String,
        index: DiplomaticMissionIndex = .bundled
    ) -> [DiplomaticMission] {
        index.missions(of: sendingCountry, in: hostCountry).sorted(by: orderedWithoutLocation)
    }

    /// The missions of the given sending countries in the host country, best first, capped at `limit`.
    ///
    /// Ordering, chosen for a traveller who needs help soon:
    /// - With a coordinate, career missions (embassy, consulate-general, consulate) are sorted by
    ///   distance, because the realistic question is "where can I physically get to". Honorary
    ///   consulates always follow the career missions regardless of distance: they are run by a
    ///   local volunteer, usually cannot replace a lost passport, and a close-by honorary post must
    ///   not hide the embassy that can. Distances within `distanceBucketKilometers` count as a tie
    ///   (coordinates are mostly city centres, so an embassy and a consulate-general in the same
    ///   city are equally "near") and the more capable kind wins the tie.
    /// - Without a coordinate there is no honest way to rank by distance, so kind decides
    ///   (embassy, consulate-general, consulate, other, honorary), then name.
    ///
    /// `arrangementRank` (lower is better) lets a caller prefer one kind of sending state over another
    /// among equally near missions: it is applied after the distance bucket and before the kind. Without
    /// a coordinate it applies right after the honorary rule. The default ranks everything equally.
    ///
    /// Missions listed under several requested countries are returned once.
    public static func nearest(
        of sendingCountries: [String],
        in hostCountry: String,
        near coordinate: (latitude: Double, longitude: Double)?,
        limit: Int,
        index: DiplomaticMissionIndex = .bundled,
        arrangementRank: (DiplomaticMission) -> Int = { _ in 0 }
    ) -> [DiplomaticMissionMatch] {
        guard limit > 0 else {
            return []
        }

        var seenIDs = Set<String>()
        let candidates = sendingCountries
            .flatMap { index.missions(of: $0, in: hostCountry) }
            .filter { seenIDs.insert($0.id).inserted }

        let matches = candidates.map { mission in
            DiplomaticMissionMatch(
                mission: mission,
                distanceKilometers: coordinate.map {
                    greatCircleDistanceKilometers(
                        fromLatitude: $0.latitude,
                        longitude: $0.longitude,
                        toLatitude: mission.latitude,
                        longitude: mission.longitude
                    )
                }
            )
        }

        return Array(matches.sorted { ordered($0, $1, arrangementRank: arrangementRank) }.prefix(limit))
    }

    /// The states whose missions can help a citizen of `citizenship` when their own state has no
    /// mission in the country they are in: the other EU member states for EU citizens, plus the
    /// other Nordic states for Nordic citizens (which brings in Norway and Iceland). Everyone else
    /// gets an empty list. Sorted, never contains the citizenship itself.
    public static func fallbackStates(for citizenship: String) -> [String] {
        let code = citizenship.normalizedCountryCode
        var states = Set<String>()

        if euMemberStates.contains(code) {
            states.formUnion(euMemberStates)
        }
        if nordicStates.contains(code) {
            states.formUnion(nordicStates)
        }

        states.remove(code)
        return states.sorted()
    }

    // MARK: - Ordering

    private static func orderedWithoutLocation(_ lhs: DiplomaticMission, _ rhs: DiplomaticMission) -> Bool {
        if lhs.kind.rank != rhs.kind.rank {
            return lhs.kind.rank < rhs.kind.rank
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.id < rhs.id
    }

    private static func ordered(
        _ lhs: DiplomaticMissionMatch,
        _ rhs: DiplomaticMissionMatch,
        arrangementRank: (DiplomaticMission) -> Int
    ) -> Bool {
        let lhsDistance = lhs.distanceKilometers
        let rhsDistance = rhs.distanceKilometers
        let lhsArrangement = arrangementRank(lhs.mission)
        let rhsArrangement = arrangementRank(rhs.mission)

        guard let lhsDistance, let rhsDistance else {
            if lhs.mission.kind.isHonorary != rhs.mission.kind.isHonorary {
                return rhs.mission.kind.isHonorary
            }
            if lhsArrangement != rhsArrangement {
                return lhsArrangement < rhsArrangement
            }
            return orderedWithoutLocation(lhs.mission, rhs.mission)
        }

        if lhs.mission.kind.isHonorary != rhs.mission.kind.isHonorary {
            return rhs.mission.kind.isHonorary
        }

        let lhsBucket = (lhsDistance / distanceBucketKilometers).rounded(.down)
        let rhsBucket = (rhsDistance / distanceBucketKilometers).rounded(.down)
        if lhsBucket != rhsBucket {
            return lhsBucket < rhsBucket
        }
        if lhsArrangement != rhsArrangement {
            return lhsArrangement < rhsArrangement
        }
        if lhs.mission.kind.rank != rhs.mission.kind.rank {
            return lhs.mission.kind.rank < rhs.mission.kind.rank
        }
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        return orderedWithoutLocation(lhs.mission, rhs.mission)
    }

    /// Haversine distance on a spherical Earth, accurate to well under 1% which is plenty here.
    static func greatCircleDistanceKilometers(
        fromLatitude lat1: Double,
        longitude lon1: Double,
        toLatitude lat2: Double,
        longitude lon2: Double
    ) -> Double {
        let earthRadiusKilometers = 6_371.0088
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * earthRadiusKilometers * asin(min(1, sqrt(a)))
    }
}

/// Where a traveller can get consular help in the country they are in.
public struct EmbassyLookup: Equatable, Sendable {
    /// Why the fallback missions are shown instead of the traveller's own.
    public enum FallbackReason: Equatable, Sendable {
        /// EU citizens can use any EU member state's mission when their own is absent
        /// (Directive (EU) 2015/637).
        case euConsularProtection
        /// Nordic missions assist citizens of other Nordic countries that are not represented locally
        /// (Nordic cooperation; a cooperative fallback, not an individual entitlement).
        case nordicCooperation
    }

    public static let defaultLimit = 3

    /// Upper-case host country code the lookup was made for.
    public let hostCountry: String
    /// Upper-case citizenships the lookup was made for, in the order given, without duplicates.
    public let citizenships: [String]
    /// Missions of the traveller's own state(s) in the host country.
    public let ownMatches: [DiplomaticMissionMatch]
    /// Missions of other states that can help. Only filled when there is no own mission at all.
    public let fallbackMatches: [DiplomaticMissionMatch]
    /// The arrangement behind the best fallback match, nil when `fallbackMatches` is empty.
    public let fallbackReason: FallbackReason?

    public var isEmpty: Bool {
        ownMatches.isEmpty && fallbackMatches.isEmpty
    }

    public init(
        ownMatches: [DiplomaticMissionMatch],
        fallbackMatches: [DiplomaticMissionMatch],
        fallbackReason: FallbackReason?,
        hostCountry: String,
        citizenships: [String]
    ) {
        self.ownMatches = ownMatches
        self.fallbackMatches = fallbackMatches
        self.fallbackReason = fallbackReason
        self.hostCountry = hostCountry
        self.citizenships = citizenships
    }

    /// - Parameters:
    ///   - citizenships: ISO codes of the user's citizenships.
    ///   - hostCountry: ISO code of the country the user is in (`DashboardSnapshot.currentCountryCode`).
    ///   - coordinate: Device location, when available, used to rank by distance.
    ///   - limit: Maximum matches in each of `ownMatches` and `fallbackMatches`.
    ///
    /// A citizenship equal to the host country is skipped, because the user is at home for that
    /// passport. A dual citizen abroad on one of their passports still gets that passport's missions.
    /// Fallback states are only consulted when none of the remaining citizenships has a mission
    /// in the host country.
    public init(
        citizenships: [String],
        hostCountry: String?,
        coordinate: (latitude: Double, longitude: Double)?,
        limit: Int = EmbassyLookup.defaultLimit,
        index: DiplomaticMissionIndex = .bundled
    ) {
        let host = hostCountry?.normalizedCountryCode ?? ""
        var seen = Set<String>()
        let normalizedCitizenships = citizenships
            .map(\.normalizedCountryCode)
            .filter { $0.isEmpty == false && seen.insert($0).inserted }
        let abroadCitizenships = normalizedCitizenships.filter { $0 != host }

        guard host.isEmpty == false, abroadCitizenships.isEmpty == false else {
            self.init(
                ownMatches: [],
                fallbackMatches: [],
                fallbackReason: nil,
                hostCountry: host,
                citizenships: normalizedCitizenships
            )
            return
        }

        let own = DiplomaticMissionDirectory.nearest(
            of: abroadCitizenships,
            in: host,
            near: coordinate,
            limit: limit,
            index: index
        )
        guard own.isEmpty else {
            self.init(
                ownMatches: own,
                fallbackMatches: [],
                fallbackReason: nil,
                hostCountry: host,
                citizenships: normalizedCitizenships
            )
            return
        }

        let ownStates = Set(normalizedCitizenships)
        let fallbackStates = Set(abroadCitizenships.flatMap(DiplomaticMissionDirectory.fallbackStates(for:)))
            .subtracting(ownStates)
            .subtracting([host])
            .sorted()
        let fallback = DiplomaticMissionDirectory.nearest(
            of: fallbackStates,
            in: host,
            near: coordinate,
            limit: limit,
            index: index,
            arrangementRank: { mission in
                // The Nordic arrangement is the more specific one, so those missions come first.
                switch Self.fallbackReason(forSendingCountry: mission.sendingCountry, citizenships: abroadCitizenships) {
                case .nordicCooperation: 0
                case .euConsularProtection: 1
                case nil: 2
                }
            }
        )
        let reason = fallback.first.flatMap {
            Self.fallbackReason(forSendingCountry: $0.mission.sendingCountry, citizenships: abroadCitizenships)
        }

        self.init(
            ownMatches: [],
            fallbackMatches: fallback,
            fallbackReason: reason,
            hostCountry: host,
            citizenships: normalizedCitizenships
        )
    }

    /// The arrangement that lets this lookup's citizens use `mission`, nil when none applies (for
    /// example a mission from the own list). The Nordic arrangement is preferred where both apply,
    /// since it is the more specific one.
    public func fallbackReason(for mission: DiplomaticMission) -> FallbackReason? {
        Self.fallbackReason(forSendingCountry: mission.sendingCountry, citizenships: citizenships.filter { $0 != hostCountry })
    }

    private static func fallbackReason(forSendingCountry sendingCountry: String, citizenships: [String]) -> FallbackReason? {
        let sending = sendingCountry.normalizedCountryCode
        let nordic = DiplomaticMissionDirectory.nordicStates
        let eu = DiplomaticMissionDirectory.euMemberStates

        if nordic.contains(sending), citizenships.contains(where: { nordic.contains($0) && $0 != sending }) {
            return .nordicCooperation
        }
        if eu.contains(sending), citizenships.contains(where: { eu.contains($0) && $0 != sending }) {
            return .euConsularProtection
        }
        return nil
    }
}

private extension String {
    var normalizedCountryCode: String {
        trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
