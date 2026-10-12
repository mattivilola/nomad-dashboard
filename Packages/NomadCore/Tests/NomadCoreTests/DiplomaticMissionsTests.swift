import Foundation
@testable import NomadCore
import Testing

struct DiplomaticMissionsTests {
    // Coordinates are real city centres so distances can be sanity-checked.
    private static let rabat = (latitude: 34.0209, longitude: -6.8416)
    private static let casablanca = (latitude: 33.5731, longitude: -7.5898)
    private static let agadir = (latitude: 30.4278, longitude: -9.5981)
    private static let marrakesh = (latitude: 31.6295, longitude: -7.9811)

    private static func mission(
        _ id: String,
        _ sending: String,
        host: String = "MA",
        _ kind: DiplomaticMissionKind,
        _ name: String,
        at point: (latitude: Double, longitude: Double)
    ) -> DiplomaticMission {
        DiplomaticMission(
            id: id,
            sendingCountry: sending,
            hostCountry: host,
            kind: kind,
            name: name,
            latitude: point.latitude,
            longitude: point.longitude
        )
    }

    /// Finland has an embassy in Rabat only; Germany has the full range; Sweden and Denmark have
    /// an embassy in Rabat; Estonia and the US have missions elsewhere in Morocco or none.
    private static let fixture = DiplomaticMissionIndex(
        missions: [
            mission("Q1", "FI", .embassy, "Embassy of Finland, Rabat", at: rabat),
            mission("Q2", "DE", .embassy, "Embassy of Germany, Rabat", at: rabat),
            mission("Q3", "DE", .consulateGeneral, "Consulate General of Germany, Casablanca", at: casablanca),
            mission("Q4", "DE", .honoraryConsulate, "Honorary Consulate of Germany, Agadir", at: agadir),
            mission("Q5", "DE", .consulate, "Consulate of Germany, Marrakesh", at: marrakesh),
            mission("Q6", "SE", .embassy, "Embassy of Sweden, Rabat", at: rabat),
            mission("Q7", "DK", .embassy, "Embassy of Denmark, Rabat", at: rabat),
            mission("Q8", "US", .embassy, "Embassy of the United States, Rabat", at: rabat),
            mission("Q9", "NO", .honoraryConsulate, "Honorary Consulate of Norway, Casablanca", at: casablanca),
            mission("Q10", "DE", host: "ES", .embassy, "Embassy of Germany, Madrid", at: (40.4168, -3.7038)),
            mission("Q11", "FI", host: "ES", .embassy, "Embassy of Finland, Madrid", at: (40.4168, -3.7038))
        ],
        source: "fixture",
        generatedAt: "2026-10-12"
    )

    private func ids(_ matches: [DiplomaticMissionMatch]) -> [String] {
        matches.map(\.mission.id)
    }

    // MARK: - Directory

    @Test
    func missionsAreLookedUpCaseInsensitivelyAndSortedByKind() {
        let germanMissions = DiplomaticMissionDirectory.missions(of: " de ", in: "ma", index: Self.fixture)

        #expect(germanMissions.map(\.id) == ["Q2", "Q3", "Q5", "Q4"])
        #expect(DiplomaticMissionDirectory.missions(of: "FI", in: "MA", index: Self.fixture).map(\.id) == ["Q1"])
        #expect(DiplomaticMissionDirectory.missions(of: "FI", in: "ES", index: Self.fixture).map(\.id) == ["Q11"])
    }

    @Test
    func unknownCodesReturnNothing() {
        #expect(DiplomaticMissionDirectory.missions(of: "ZZ", in: "MA", index: Self.fixture).isEmpty)
        #expect(DiplomaticMissionDirectory.missions(of: "FI", in: "ZZ", index: Self.fixture).isEmpty)
        #expect(DiplomaticMissionDirectory.missions(of: "", in: "", index: Self.fixture).isEmpty)
        #expect(DiplomaticMissionDirectory.nearest(of: ["ZZ"], in: "MA", near: nil, limit: 3, index: Self.fixture).isEmpty)
        #expect(DiplomaticMissionDirectory.nearest(of: [], in: "MA", near: nil, limit: 3, index: Self.fixture).isEmpty)
    }

    @Test
    func withoutACoordinateKindDecidesAndHonoraryIsLast() {
        let matches = DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: nil, limit: 10, index: Self.fixture)

        #expect(ids(matches) == ["Q2", "Q3", "Q5", "Q4"])
        #expect(matches.allSatisfy { $0.distanceKilometers == nil })
    }

    @Test
    func limitCapsTheResultsAndNonPositiveLimitsReturnNothing() {
        #expect(ids(DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: nil, limit: 2, index: Self.fixture)) == ["Q2", "Q3"])
        #expect(DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: nil, limit: 0, index: Self.fixture).isEmpty)
        #expect(DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: nil, limit: -1, index: Self.fixture).isEmpty)
    }

    @Test
    func withACoordinateTheNearestCareerMissionComesFirst() {
        // In Casablanca the consulate-general beats the embassy 87 km away.
        let inCasablanca = DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: Self.casablanca, limit: 10, index: Self.fixture)
        #expect(ids(inCasablanca) == ["Q3", "Q2", "Q5", "Q4"])
        #expect(inCasablanca.first?.distanceKilometers ?? .infinity < 1)

        // Marrakesh: the consulate there is closest, then Casablanca, then Rabat.
        let inMarrakesh = DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: Self.marrakesh, limit: 10, index: Self.fixture)
        #expect(ids(inMarrakesh) == ["Q5", "Q3", "Q2", "Q4"])
    }

    @Test
    func honoraryConsulatesNeverOutrankACareerMissionEvenWhenCloser() {
        // Standing in Agadir, the honorary consulate is ~0 km away but the embassy still comes first.
        let matches = DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: Self.agadir, limit: 10, index: Self.fixture)

        #expect(matches.last?.mission.id == "Q4")
        #expect(matches.last?.distanceKilometers ?? .infinity < 1)
        #expect(matches.first?.mission.id == "Q5")
    }

    @Test
    func equallyNearMissionsAreTiedByKind() {
        // The Danish, Finnish and Swedish embassies all share Rabat: same distance, ordered by name.
        let nordic = DiplomaticMissionDirectory.nearest(of: ["SE", "DK", "FI"], in: "MA", near: Self.rabat, limit: 10, index: Self.fixture)
        #expect(ids(nordic) == ["Q7", "Q1", "Q6"])

        // An embassy and a consulate-general a few kilometres apart count as equally near; the embassy wins.
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("A", "FR", .consulateGeneral, "CG", at: (latitude: 34.0200, longitude: -6.8400)),
            Self.mission("B", "FR", .embassy, "Embassy", at: (latitude: 34.0500, longitude: -6.8400))
        ])
        let matches = DiplomaticMissionDirectory.nearest(of: ["FR"], in: "MA", near: Self.rabat, limit: 2, index: index)
        #expect(ids(matches) == ["B", "A"])
    }

    @Test
    func distancesAreGreatCircleKilometres() throws {
        let matches = DiplomaticMissionDirectory.nearest(of: ["DE"], in: "MA", near: Self.rabat, limit: 10, index: Self.fixture)
        let casablancaDistance = try #require(matches.first { $0.mission.id == "Q3" }?.distanceKilometers)

        // Rabat to Casablanca is about 87 km as the crow flies.
        #expect(abs(casablancaDistance - 87) < 3)
        #expect(try #require(matches.first { $0.mission.id == "Q2" }?.distanceKilometers) < 0.001)
    }

    @Test
    func missionsListedForSeveralCitizenshipsAppearOnce() {
        let index = DiplomaticMissionIndex(missions: [Self.mission("X", "FI", .embassy, "Shared", at: Self.rabat)])
        #expect(DiplomaticMissionDirectory.nearest(of: ["FI", "fi", "FI"], in: "MA", near: nil, limit: 5, index: index).count == 1)
    }

    @Test
    func euMemberStatesAreTheTwentySevenUniqueCodes() {
        let states = DiplomaticMissionDirectory.euMemberStates
        #expect(states.count == 27)
        #expect(Set(states).count == 27)
        #expect(states.contains("FI") && states.contains("IE") && states.contains("HR"))
        #expect(states.contains("GB") == false && states.contains("NO") == false && states.contains("CH") == false)
        #expect(DiplomaticMissionDirectory.nordicStates == ["DK", "FI", "IS", "NO", "SE"])
    }

    @Test
    func fallbackStatesForEUNordicAndOtherCitizens() {
        let finland = DiplomaticMissionDirectory.fallbackStates(for: "FI")
        #expect(finland.contains("DE") && finland.contains("SE") && finland.contains("NO") && finland.contains("IS"))
        #expect(finland.contains("FI") == false)
        #expect(finland.count == 28) // 26 other EU states + Norway + Iceland

        let germany = DiplomaticMissionDirectory.fallbackStates(for: "de")
        #expect(germany.count == 26)
        #expect(germany.contains("NO") == false)
        #expect(germany.contains("DE") == false)

        #expect(DiplomaticMissionDirectory.fallbackStates(for: "NO") == ["DK", "FI", "IS", "SE"])
        #expect(DiplomaticMissionDirectory.fallbackStates(for: "IS") == ["DK", "FI", "NO", "SE"])
        #expect(DiplomaticMissionDirectory.fallbackStates(for: "US").isEmpty)
        #expect(DiplomaticMissionDirectory.fallbackStates(for: "GB").isEmpty)
        #expect(DiplomaticMissionDirectory.fallbackStates(for: "ZZ").isEmpty)
        #expect(DiplomaticMissionDirectory.fallbackStates(for: "").isEmpty)
    }

    // MARK: - Lookup

    @Test
    func atHomeYieldsNothing() {
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "FI", coordinate: nil, index: Self.fixture)

        #expect(lookup.isEmpty)
        #expect(lookup.fallbackReason == nil)

        #expect(EmbassyLookup(citizenships: ["fi"], hostCountry: " fi ", coordinate: nil, index: Self.fixture).isEmpty)
    }

    @Test
    func ownMissionsAreListedAndSuppressTheFallback() {
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "MA", coordinate: Self.rabat, index: Self.fixture)

        #expect(ids(lookup.ownMatches) == ["Q1"])
        #expect(lookup.fallbackMatches.isEmpty)
        #expect(lookup.fallbackReason == nil)
        #expect(lookup.hostCountry == "MA")
    }

    @Test
    func finnWithoutAMissionGetsEUAndNordicStatesRankedTogether() {
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("Q2", "DE", .embassy, "Embassy of Germany, Rabat", at: Self.rabat),
            Self.mission("Q6", "SE", .embassy, "Embassy of Sweden, Rabat", at: Self.rabat),
            Self.mission("Q12", "FR", .consulateGeneral, "Consulate General of France, Casablanca", at: Self.casablanca)
        ])
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "MA", coordinate: Self.rabat, index: index)

        #expect(lookup.ownMatches.isEmpty)
        // Sweden and Germany are equally near; the Nordic arrangement is more specific, so Sweden leads.
        #expect(ids(lookup.fallbackMatches) == ["Q6", "Q2", "Q12"])
        #expect(lookup.fallbackReason == .nordicCooperation)
        #expect(lookup.fallbackReason(for: lookup.fallbackMatches[0].mission) == .nordicCooperation)
        #expect(lookup.fallbackReason(for: lookup.fallbackMatches[1].mission) == .euConsularProtection)
    }

    @Test
    func nordicReasonIsReportedWhenTheBestMatchIsNordic() {
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("Q6", "SE", .embassy, "Embassy of Sweden, Rabat", at: Self.rabat),
            Self.mission("Q2", "DE", .embassy, "Embassy of Germany, Casablanca", at: Self.casablanca)
        ])
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "MA", coordinate: Self.rabat, index: index)

        #expect(ids(lookup.fallbackMatches) == ["Q6", "Q2"])
        #expect(lookup.fallbackReason == .nordicCooperation)
    }

    @Test
    func norwegianCitizensOnlyFallBackToNordicStates() {
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("Q2", "DE", .embassy, "Embassy of Germany, Rabat", at: Self.rabat),
            Self.mission("Q6", "SE", .embassy, "Embassy of Sweden, Rabat", at: Self.rabat)
        ])
        let lookup = EmbassyLookup(citizenships: ["NO"], hostCountry: "MA", coordinate: nil, index: index)

        #expect(ids(lookup.fallbackMatches) == ["Q6"])
        #expect(lookup.fallbackReason == .nordicCooperation)
    }

    @Test
    func estonianCitizenGetsEUProtectionAndNeverTheHostOrOwnState() {
        let lookup = EmbassyLookup(citizenships: ["EE"], hostCountry: "MA", coordinate: Self.rabat, limit: 2, index: Self.fixture)

        #expect(lookup.ownMatches.isEmpty)
        #expect(lookup.fallbackMatches.count == 2)
        #expect(lookup.fallbackReason == .euConsularProtection)
        // Non-EU states with missions in the fixture (US, NO) are never offered.
        #expect(lookup.fallbackMatches.allSatisfy { ["US", "NO"].contains($0.mission.sendingCountry) == false })
    }

    @Test
    func nonEUCitizensWithoutAMissionGetNothing() {
        // The fixture has a US embassy but a Canadian has no mission and no fallback arrangement.
        let lookup = EmbassyLookup(citizenships: ["CA"], hostCountry: "MA", coordinate: Self.rabat, index: Self.fixture)

        #expect(lookup.isEmpty)
        #expect(lookup.fallbackReason == nil)
    }

    @Test
    func unknownHostOrEmptyCitizenshipsYieldNothing() {
        #expect(EmbassyLookup(citizenships: ["FI"], hostCountry: nil, coordinate: nil, index: Self.fixture).isEmpty)
        #expect(EmbassyLookup(citizenships: ["FI"], hostCountry: "", coordinate: nil, index: Self.fixture).isEmpty)
        #expect(EmbassyLookup(citizenships: [], hostCountry: "MA", coordinate: nil, index: Self.fixture).isEmpty)
        #expect(EmbassyLookup(citizenships: ["", " "], hostCountry: "MA", coordinate: nil, index: Self.fixture).isEmpty)
        #expect(EmbassyLookup(citizenships: ["FI"], hostCountry: "ZZ", coordinate: nil, index: Self.fixture).isEmpty)
    }

    @Test
    func dualCitizenAbroadOnOnePassportStillGetsThatPassportsMissions() {
        // FI + DE in Germany: at home for DE, abroad for FI.
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("Q20", "FI", host: "DE", .embassy, "Embassy of Finland, Berlin", at: (52.52, 13.405))
        ])
        let lookup = EmbassyLookup(citizenships: ["FI", "DE"], hostCountry: "DE", coordinate: nil, index: index)

        #expect(ids(lookup.ownMatches) == ["Q20"])
        #expect(lookup.fallbackMatches.isEmpty)
    }

    @Test
    func dualCitizenWithOneOwnMissionSkipsTheFallback() {
        let lookup = EmbassyLookup(citizenships: ["EE", "DE"], hostCountry: "MA", coordinate: Self.rabat, index: Self.fixture)

        #expect(ids(lookup.ownMatches).contains("Q2"))
        #expect(lookup.fallbackMatches.isEmpty)
        #expect(lookup.fallbackReason == nil)
    }

    // MARK: - Model and bundled resource

    @Test
    func missionCodableUsesCompactKeysAndDefaultsOptionalFields() throws {
        let json = #"{"i":"Q1","s":"FI","h":"MA","k":"embassy","n":"Embassy","la":34.02,"lo":-6.84}"#
        let mission = try JSONDecoder().decode(DiplomaticMission.self, from: Data(json.utf8))

        #expect(mission.city == nil)
        #expect(mission.website == nil)
        #expect(mission.isApproximateLocation == false)

        let full = DiplomaticMission(
            id: "Q1", sendingCountry: "FI", hostCountry: "MA", kind: .honoraryConsulate, name: "Honorary",
            city: "Rabat", latitude: 1, longitude: 2, address: "Street 1", website: "https://example.org", isApproximateLocation: true
        )
        let decoded = try JSONDecoder().decode(DiplomaticMission.self, from: JSONEncoder().encode(full))
        #expect(decoded == full)
        #expect(decoded.websiteURL == URL(string: "https://example.org"))
    }

    @Test
    func kindTitlesAreUserFacing() {
        #expect(DiplomaticMissionKind.embassy.title == "Embassy")
        #expect(DiplomaticMissionKind.consulateGeneral.title == "Consulate-general")
        #expect(DiplomaticMissionKind.consulate.title == "Consulate")
        #expect(DiplomaticMissionKind.honoraryConsulate.title == "Honorary consulate")
        #expect(DiplomaticMissionKind.other.title == "Mission")
    }

    @Test
    func bundledDatasetDecodesAndIsSane() {
        let index = DiplomaticMissionIndex.bundled

        #expect(index.source == DiplomaticMissionDataset.wikidataSource)
        #expect(index.generatedAt?.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
        #expect(index.missions.count > 5_000)

        // Spot checks that must hold for any acceptable refresh of the dataset.
        #expect(DiplomaticMissionDirectory.missions(of: "FI", in: "MA", index: index).contains { $0.kind == .embassy })
        #expect(DiplomaticMissionDirectory.missions(of: "US", in: "MA", index: index).contains { $0.kind == .embassy })
        #expect(DiplomaticMissionDirectory.missions(of: "GB", in: "MA", index: index).isEmpty == false)
        #expect(DiplomaticMissionDirectory.missions(of: "DE", in: "ES", index: index).contains { $0.kind == .embassy })
        #expect(DiplomaticMissionDirectory.missions(of: "NL", in: "MA", index: index).isEmpty == false)
        #expect(DiplomaticMissionDirectory.missions(of: "DK", in: "MA", index: index).isEmpty == false)
    }

    @Test
    func bundledMissionsAreWellFormed() {
        var seenIDs = Set<String>()
        let codePattern = /[A-Z]{2}/
        let missions = DiplomaticMissionIndex.bundled.missions

        #expect(missions.isEmpty == false)
        for mission in missions {
            #expect(seenIDs.insert(mission.id).inserted, "duplicate id \(mission.id)")
            #expect(mission.sendingCountry.wholeMatch(of: codePattern) != nil)
            #expect(mission.hostCountry.wholeMatch(of: codePattern) != nil)
            #expect(mission.sendingCountry != mission.hostCountry)
            #expect((-90...90).contains(mission.latitude) && (-180...180).contains(mission.longitude))
            #expect(mission.name.isEmpty == false)
            if let website = mission.website {
                #expect(["http", "https"].contains(URL(string: website)?.scheme))
            }
        }
    }

    // MARK: - Fallback ranking

    private static let amman = (latitude: 31.9539, longitude: 35.9106)

    /// Alphabetically Austria, Belgium and Bulgaria come first; Sweden, Norway and Denmark are as near.
    private static let ammanFixture = DiplomaticMissionIndex(
        missions: [
            mission("AT", "AT", host: "JO", .embassy, "Embassy of Austria, Amman", at: amman),
            mission("BE", "BE", host: "JO", .embassy, "Embassy of Belgium, Amman", at: amman),
            mission("BG", "BG", host: "JO", .embassy, "Embassy of Bulgaria, Amman", at: amman),
            mission("DE", "DE", host: "JO", .consulateGeneral, "Consulate General of Germany, Amman", at: amman),
            mission("SE", "SE", host: "JO", .embassy, "Embassy of Sweden, Amman", at: amman),
            mission("NO", "NO", host: "JO", .embassy, "Embassy of Norway, Amman", at: amman),
            mission("DK", "DK", host: "JO", .embassy, "Embassy of Denmark, Amman", at: amman),
            mission("SE-AQ", "SE", host: "JO", .honoraryConsulate, "Honorary Consulate of Sweden, Aqaba", at: (29.53, 35.0))
        ]
    )

    @Test
    func nordicMissionsOutrankEUMissionsForANordicCitizenAtTheSameDistance() {
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "JO", coordinate: Self.amman, index: Self.ammanFixture)

        #expect(ids(lookup.fallbackMatches) == ["DK", "NO", "SE"])
        #expect(lookup.fallbackReason == .nordicCooperation)
    }

    @Test
    func nordicPreferenceAlsoAppliesWithoutACoordinate() {
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "JO", coordinate: nil, limit: 4, index: Self.ammanFixture)

        #expect(ids(lookup.fallbackMatches) == ["DK", "NO", "SE", "AT"])
    }

    @Test
    func aMuchNearerEUMissionStillBeatsADistantNordicOne() {
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("AT-NEAR", "AT", host: "JO", .embassy, "Embassy of Austria, Amman", at: Self.amman),
            Self.mission("SE-FAR", "SE", host: "JO", .embassy, "Embassy of Sweden, Aqaba", at: (29.53, 35.0))
        ])
        let lookup = EmbassyLookup(citizenships: ["FI"], hostCountry: "JO", coordinate: Self.amman, index: index)

        #expect(ids(lookup.fallbackMatches) == ["AT-NEAR", "SE-FAR"])
    }

    @Test
    func anEUOnlyCitizenKeepsTheKindThenNameOrderingWithinABucket() {
        let lookup = EmbassyLookup(citizenships: ["FR"], hostCountry: "JO", coordinate: Self.amman, limit: 6, index: Self.ammanFixture)

        #expect(ids(lookup.fallbackMatches) == ["AT", "BE", "BG", "DK", "SE", "DE"])
        #expect(lookup.fallbackReason == .euConsularProtection)
    }
}
