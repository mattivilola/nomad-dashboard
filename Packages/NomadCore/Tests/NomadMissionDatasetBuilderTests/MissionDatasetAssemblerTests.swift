import Foundation
import NomadCore
@testable import NomadMissionDatasetBuilder
import Testing

struct MissionDatasetAssemblerTests {
    private let assembler = MissionDatasetAssembler(
        validCountryCodes: ["FI", "MA", "DE", "ES", "NL", "VN", "XK"],
        englishRegionName: { ["FI": "Finland", "MA": "Morocco"][$0] }
    )

    /// A table with one healthy Finnish embassy in Morocco; tests mutate it.
    private func baseTables() -> MissionSourceTables {
        var tables = MissionSourceTables()
        tables.classKinds = [
            "Qembassy": .embassy,
            "Qconsulate": .consulate,
            "Qcg": .consulateGeneral,
            "Qhonorary": .honoraryConsulate
        ]
        tables.isoCodes = ["QFI": "FI", "QMA": "MA", "QDE": "DE", "QES": "ES", "QVN": "VN"]
        tables.core = [CoreRow(mission: "Q1", kindClass: "Qembassy", operatorID: "QFI", hostID: "QMA")]
        tables.labels = ["Q1": [LocalizedText(text: "embassy of Finland in Morocco", language: "en")]]
        tables.coordinates = ["Q1": [Coordinate(latitude: 34.0209, longitude: -6.8416)]]
        return tables
    }

    private func assemble(_ tables: MissionSourceTables) -> (missions: [DiplomaticMission], report: AssemblyReport) {
        let result = assembler.assemble(from: tables, generatedAt: "2026-10-12")
        return (result.dataset.missions, result.report)
    }

    @Test
    func keepsAHealthyMissionAndCapitalizesItsLabel() {
        let (missions, report) = assemble(baseTables())

        #expect(missions.count == 1)
        #expect(missions[0].name == "Embassy of Finland in Morocco")
        #expect(missions[0].sendingCountry == "FI")
        #expect(missions[0].hostCountry == "MA")
        #expect(missions[0].isApproximateLocation == false)
        #expect(report.countsByKind[.embassy] == 1)
    }

    @Test
    func excludesClosedMissionsAndEndedStatements() {
        var closed = baseTables()
        closed.closedMissions = ["Q1"]
        #expect(assemble(closed).missions.isEmpty)

        var endedOperator = baseTables()
        endedOperator.endedStatements = [EndedStatement(mission: "Q1", property: .operatorOf, value: "QFI")]
        #expect(assemble(endedOperator).report.excluded["missing operator (P137)"] == 1)

        var endedClass = baseTables()
        endedClass.endedStatements = [EndedStatement(mission: "Q1", property: .kindClass, value: "Qembassy")]
        #expect(assemble(endedClass).report.excluded["no current mission class"] == 1)
    }

    @Test
    func mostSpecificKindWins() {
        var tables = baseTables()
        tables.core = [
            CoreRow(mission: "Q1", kindClass: "Qconsulate", operatorID: "QFI", hostID: "QMA"),
            CoreRow(mission: "Q1", kindClass: "Qhonorary", operatorID: "QFI", hostID: "QMA")
        ]
        #expect(assemble(tables).missions.first?.kind == .honoraryConsulate)

        tables.core = [
            CoreRow(mission: "Q1", kindClass: "Qconsulate", operatorID: "QFI", hostID: "QMA"),
            CoreRow(mission: "Q1", kindClass: "Qcg", operatorID: "QFI", hostID: "QMA")
        ]
        #expect(assemble(tables).missions.first?.kind == .consulateGeneral)
    }

    @Test
    func resolvesStatesThroughOverridesAndForeignMinistries() {
        var tables = baseTables()
        tables.core = [
            CoreRow(mission: "Q1", kindClass: "Qembassy", operatorID: "Q55", hostID: "QMA"),
            CoreRow(mission: "Q2", kindClass: "Qembassy", operatorID: "QMinistry", hostID: "QMA")
        ]
        tables.ministryCountryCodes = ["QMinistry": "VN"]
        tables.coordinates = ["Q1": [Coordinate(latitude: 1, longitude: 1)], "Q2": [Coordinate(latitude: 2, longitude: 2)]]

        let missions = assemble(tables).missions
        #expect(missions.map(\.sendingCountry).sorted() == ["NL", "VN"])
    }

    @Test
    func rejectsUnresolvableOperatorsHostsAndHistoricCodes() {
        var unknownOperator = baseTables()
        unknownOperator.core = [CoreRow(mission: "Q1", kindClass: "Qembassy", operatorID: "QUnknown", hostID: "QMA")]
        #expect(assemble(unknownOperator).report.excluded["operator is not a country (no P297)"] == 1)

        var sameCountry = baseTables()
        sameCountry.core = [CoreRow(mission: "Q1", kindClass: "Qembassy", operatorID: "QFI", hostID: "QFI")]
        #expect(assemble(sameCountry).report.excluded["operator equals host country"] == 1)

        var historic = baseTables()
        historic.isoCodes["QFI"] = "YU"
        #expect(assemble(historic).report.excluded["historic or non-ISO country code"] == 1)

        var ambiguous = baseTables()
        ambiguous.core = [
            CoreRow(mission: "Q1", kindClass: "Qembassy", operatorID: "QFI", hostID: "QMA"),
            CoreRow(mission: "Q1", kindClass: "Qembassy", operatorID: "QDE", hostID: "QMA")
        ]
        #expect(assemble(ambiguous).report.excluded["several operator countries"] == 1)
    }

    @Test
    func fallsBackToPlaceCoordinatesAndFlagsThemApproximate() {
        var tables = baseTables()
        tables.coordinates = [:]
        tables.locations = [
            .administrativeArea: ["Q1": [LocationRow(location: "Qdistrict", coordinate: Coordinate(latitude: 10, longitude: 10), name: "District")]],
            .headquarters: ["Q1": [LocationRow(location: "Qrabat", coordinate: Coordinate(latitude: 34.02, longitude: -6.84), name: "Rabat")]]
        ]

        let mission = assemble(tables).missions.first
        #expect(mission?.isApproximateLocation == true)
        // Headquarters outranks the administrative area for both the point and the city name.
        #expect(mission?.latitude == 34.02)
        #expect(mission?.city == "Rabat")
    }

    @Test
    func dropsMissionsWithoutAnyCoordinate() {
        var tables = baseTables()
        tables.coordinates = [:]
        let (missions, report) = assemble(tables)
        #expect(missions.isEmpty)
        #expect(report.excluded["missing coordinates"] == 1)
    }

    @Test
    func synthesizesAMissingName() {
        var tables = baseTables()
        tables.labels = [:]
        let mission = assemble(tables).missions.first
        #expect(mission?.name == "Embassy of Finland in Morocco")
    }

    @Test
    func keepsOnlyHTTPWebsitesPreferringHTTPSAndSingleLineAddresses() {
        var tables = baseTables()
        tables.websites = ["Q1": ["javascript:alert(1)", "http://example.org/a", "https://example.org/b", "mailto:a@b.c"]]
        tables.addresses = ["Q1": [
            LocalizedText(text: "6 rue Bani Ritoune\nRabat", language: "fr"),
            LocalizedText(text: "6 Bani Ritoune Street", language: "en")
        ]]

        let mission = assemble(tables).missions.first
        #expect(mission?.website == "https://example.org/b")
        #expect(mission?.address == "6 Bani Ritoune Street")

        tables.addresses = ["Q1": [LocalizedText(text: "6 rue Bani Ritoune\n Rabat", language: "fr")]]
        #expect(assemble(tables).missions.first?.address == "6 rue Bani Ritoune, Rabat")
    }

    @Test
    func deduplicatesSameRouteKindAndNameKeepingTheBetterItem() {
        var tables = baseTables()
        tables.core.append(CoreRow(mission: "Q2", kindClass: "Qembassy", operatorID: "QFI", hostID: "QMA"))
        tables.labels["Q2"] = [LocalizedText(text: "Embassy of Finland in Morocco", language: "en")]
        tables.coordinates["Q2"] = [Coordinate(latitude: 34, longitude: -6)]
        tables.websites["Q2"] = ["https://finlandabroad.fi/web/mar"]

        let (missions, report) = assemble(tables)
        #expect(missions.count == 1)
        #expect(missions[0].id == "Q2")
        #expect(report.excluded["duplicate of another item (same route, kind and name)"] == 1)
    }

    @Test
    func outputIsSortedDeterministically() {
        var tables = baseTables()
        tables.core = [
            CoreRow(mission: "Q10", kindClass: "Qconsulate", operatorID: "QFI", hostID: "QMA"),
            CoreRow(mission: "Q9", kindClass: "Qembassy", operatorID: "QFI", hostID: "QMA"),
            CoreRow(mission: "Q8", kindClass: "Qembassy", operatorID: "QDE", hostID: "QES")
        ]
        tables.labels = [:]
        tables.coordinates = ["Q10": [Coordinate(latitude: 1, longitude: 1)], "Q9": [Coordinate(latitude: 2, longitude: 2)], "Q8": [Coordinate(latitude: 3, longitude: 3)]]

        #expect(assemble(tables).missions.map(\.id) == ["Q8", "Q9", "Q10"])
    }

    @Test
    func encoderWritesValidJSONThatTheRuntimeDecodes() throws {
        let dataset = DiplomaticMissionDataset(
            generatedAt: "2026-10-12",
            missions: [
                DiplomaticMission(
                    id: "Q1", sendingCountry: "FI", hostCountry: "MA", kind: .embassy, name: "Embassy \"of\" Finland",
                    city: "Rabat", latitude: 34.0209, longitude: -6.8416, address: "6 rue", website: "https://finlandabroad.fi/web/mar",
                    isApproximateLocation: true
                ),
                DiplomaticMission(id: "Q2", sendingCountry: "DE", hostCountry: "ES", kind: .consulate, name: "Konsulat", latitude: 1, longitude: 2)
            ]
        )

        let data = try MissionDatasetEncoder.encode(dataset)
        #expect(try JSONDecoder().decode(DiplomaticMissionDataset.self, from: data) == dataset)
        #expect(String(decoding: data, as: UTF8.self).contains("finlandabroad.fi/web/mar"))
    }
}

struct WikidataParsingTests {
    @Test
    func parsesWKTPointsAsLongitudeLatitude() {
        let coordinate = Coordinate(wkt: "Point(-6.8416 34.0209)")
        #expect(coordinate == Coordinate(latitude: 34.0209, longitude: -6.8416))
    }

    @Test
    func rejectsMalformedAndPlaceholderCoordinates() {
        #expect(Coordinate(wkt: "Point(0 0)") == nil)
        #expect(Coordinate(wkt: "Point(200 10)") == nil)
        #expect(Coordinate(wkt: "Point(1)") == nil)
        #expect(Coordinate(wkt: "nonsense") == nil)
    }

    @Test
    func reducesEntityURIsToIDsAndParsesBindings() throws {
        #expect(SPARQLValue(value: "http://www.wikidata.org/entity/Q42", language: nil).entityID == "Q42")
        #expect(SPARQLValue(value: "plain", language: nil).entityID == "plain")

        let json = """
        {"head":{"vars":["m","label"]},"results":{"bindings":[
          {"m":{"type":"uri","value":"http://www.wikidata.org/entity/Q1"},
           "label":{"xml:lang":"en","type":"literal","value":"Embassy"}}]}}
        """
        let rows = try WikidataClient.parseRows(Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0]["m"]?.entityID == "Q1")
        #expect(rows[0]["label"]?.language == "en")
    }

    @Test
    func optionsParseOverridesAndRejectBadInput() throws {
        let options = try BuilderOptions.parse(arguments: ["--output", "/tmp/x.json", "--generated-at", "2026-01-02", "--pause", "0"])
        #expect(options.outputPath == "/tmp/x.json")
        #expect(options.generatedAt == "2026-01-02")
        #expect(options.pauseSeconds == 0)

        #expect(throws: BuilderError.self) { try BuilderOptions.parse(arguments: ["--generated-at", "yesterday"]) }
        #expect(throws: BuilderError.self) { try BuilderOptions.parse(arguments: ["--endpoint", "http://insecure.example"]) }
        #expect(throws: BuilderError.self) { try BuilderOptions.parse(arguments: ["--bogus"]) }
    }
}
