import Foundation
@testable import NomadCore
import Testing

struct TravelReferenceDataTests {
    private let allRegions = Locale.Region.isoRegions.map(\.identifier)

    // MARK: - Driving side

    @Test
    func wellKnownCountriesDriveOnTheExpectedSide() {
        for code in ["GB", "IE", "JP", "TH", "ID", "IN", "AU", "NZ", "ZA", "KE", "MT", "CY", "HK", "JM"] {
            #expect(TravelReferenceData.drivingSide(forCountryCode: code) == .left, "\(code) should drive on the left")
        }
        for code in ["ES", "FI", "MA", "FR", "DE", "US", "CA", "MX", "BR", "CN", "VN", "PH", "EG", "GI", "MM", "VU", "IO"] {
            #expect(TravelReferenceData.drivingSide(forCountryCode: code) == .right, "\(code) should drive on the right")
        }
    }

    @Test
    func drivingSideLookupIsCaseInsensitiveAndTrimsWhitespace() {
        #expect(TravelReferenceData.drivingSide(forCountryCode: "gb") == .left)
        #expect(TravelReferenceData.drivingSide(forCountryCode: " Gb ") == .left)
        #expect(TravelReferenceData.drivingSide(forCountryCode: "es") == .right)
    }

    @Test
    func unknownOrMissingCodesHaveNoDrivingSide() {
        #expect(TravelReferenceData.drivingSide(forCountryCode: nil) == nil)
        #expect(TravelReferenceData.drivingSide(forCountryCode: "") == nil)
        #expect(TravelReferenceData.drivingSide(forCountryCode: "ZZ") == nil)
        #expect(TravelReferenceData.drivingSide(forCountryCode: "XX") == nil)
        #expect(TravelReferenceData.drivingSide(forCountryCode: "United Kingdom") == nil)
    }

    @Test
    func everyLeftDrivingEntryIsAValidRegionAndTheListHasTheVerifiedSize() {
        let regions = Set(allRegions)
        let invalid = TravelReferenceData.leftDrivingRegions.filter { regions.contains($0) == false }
        #expect(invalid.isEmpty, "not ISO 3166-1 alpha-2 regions: \(invalid.sorted())")
        #expect(TravelReferenceData.leftDrivingRegions.count == 76)
    }

    @Test
    func theFiftyFourLeftDrivingUnMembersAreAllOnTheList() {
        let unMembers: Set = [
            "BW", "KE", "LS", "MW", "MU", "MZ", "NA", "SC", "SZ", "TZ", "UG", "ZA", "ZM", "ZW",
            "AG", "BS", "BB", "DM", "GD", "GY", "JM", "KN", "LC", "VC", "SR", "TT",
            "BD", "BT", "BN", "IN", "ID", "JP", "LK", "MV", "MY", "NP", "PK", "SG", "TH", "TL", "CY",
            "GB", "IE", "MT",
            "AU", "FJ", "KI", "NR", "NZ", "PG", "WS", "SB", "TO", "TV"
        ]
        #expect(unMembers.count == 54)
        #expect(unMembers.isSubset(of: TravelReferenceData.leftDrivingRegions))
    }

    @Test
    func everyValidRegionHasADrivingSide() {
        for code in allRegions {
            #expect(TravelReferenceData.drivingSide(forCountryCode: code) != nil, "\(code) has no driving side")
        }
    }

    // MARK: - Electricity

    @Test
    func spainAndMoroccoListTheirPlugTypes() {
        #expect(TravelReferenceData.electricity(forCountryCode: "ES")
            == CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50))
        #expect(TravelReferenceData.electricity(forCountryCode: "MA")
            == CountryElectricity(plugTypes: ["C", "E"], voltage: 220, frequencyHertz: 50))
        #expect(TravelReferenceData.electricity(forCountryCode: "us")
            == CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60))
        #expect(TravelReferenceData.electricity(forCountryCode: "GB")?.plugTypes == ["G"])
        #expect(TravelReferenceData.electricity(forCountryCode: "AU")?.plugTypes == ["I"])
    }

    @Test
    func unverifiedElectricityIsDeliberatelyAbsent() {
        #expect(TravelReferenceData.electricity(forCountryCode: nil) == nil)
        #expect(TravelReferenceData.electricity(forCountryCode: "") == nil)
        #expect(TravelReferenceData.electricity(forCountryCode: "ZZ") == nil)
        // Regional supplies the model cannot express with one voltage and one frequency.
        #expect(TravelReferenceData.electricity(forCountryCode: "BR") == nil)
        #expect(TravelReferenceData.electricity(forCountryCode: "JP") == nil)
        // Mixed supplies and sources that disagree.
        for code in ["SA", "CU", "BO", "UZ"] {
            #expect(TravelReferenceData.electricity(forCountryCode: code) == nil, "\(code) should be unverified")
        }
    }

    @Test
    func everyEmergencyDirectoryCountryHasElectricityExceptTheUnverifiedOnes() {
        let unverified: Set = ["BR", "JP"]
        for code in allRegions where EmergencyNumberDirectory.numbers(forCountryCode: code) != nil {
            if unverified.contains(code) {
                #expect(TravelReferenceData.electricity(forCountryCode: code) == nil)
            } else {
                #expect(TravelReferenceData.electricity(forCountryCode: code) != nil, "\(code) has no electricity entry")
            }
        }
    }

    @Test
    func electricityEntriesAreWellFormed() {
        let regions = Set(allRegions)
        let validTypes = Set("ABCDEFGHIJKLMNO".map(String.init))
        for code in regions {
            guard let electricity = TravelReferenceData.electricity(forCountryCode: code) else { continue }
            #expect(electricity.plugTypes.isEmpty == false, "\(code) has no plug types")
            #expect(electricity.plugTypes == electricity.plugTypes.sorted(), "\(code) plug types are not sorted")
            #expect(Set(electricity.plugTypes).count == electricity.plugTypes.count, "\(code) repeats a plug type")
            #expect(Set(electricity.plugTypes).isSubset(of: validTypes), "\(code) has an unknown plug type")
            #expect((100...240).contains(electricity.voltage), "\(code) voltage \(electricity.voltage)")
            #expect([50, 60].contains(electricity.frequencyHertz), "\(code) frequency \(electricity.frequencyHertz)")
        }
    }

    @Test
    func theSupplyDiffersOnlyWhenItMattersToATraveller() {
        let spain = CountryElectricity(plugTypes: ["C", "F"], voltage: 230, frequencyHertz: 50)
        let morocco = CountryElectricity(plugTypes: ["C", "E"], voltage: 220, frequencyHertz: 50)
        let france = CountryElectricity(plugTypes: ["C", "E"], voltage: 230, frequencyHertz: 50)
        let uk = CountryElectricity(plugTypes: ["G"], voltage: 230, frequencyHertz: 50)
        let kenya = CountryElectricity(plugTypes: ["G"], voltage: 240, frequencyHertz: 50)
        let usa = CountryElectricity(plugTypes: ["A", "B"], voltage: 120, frequencyHertz: 60)
        let japanLike = CountryElectricity(plugTypes: ["A", "B"], voltage: 100, frequencyHertz: 50)

        #expect(spain.differs(from: morocco))
        #expect(morocco.differs(from: spain))
        #expect(morocco.differs(from: france) == false) // 220 V and 230 V are the same supply
        #expect(uk.differs(from: kenya) == false) // 230 V and 240 V too
        #expect(uk.differs(from: spain))
        #expect(spain.differs(from: usa))
        #expect(usa.differs(from: japanLike)) // same plugs, 100 V at 50 Hz
        #expect(CountryElectricity(plugTypes: ["F", "C"], voltage: 230, frequencyHertz: 50).differs(from: spain) == false)
    }

    // MARK: - Currency

    @Test
    func currencyComesFromRegionData() {
        #expect(TravelReferenceData.currencyCode(forCountryCode: "MA") == "MAD")
        #expect(TravelReferenceData.currencyCode(forCountryCode: "ES") == "EUR")
        #expect(TravelReferenceData.currencyCode(forCountryCode: "FI") == "EUR")
        #expect(TravelReferenceData.currencyCode(forCountryCode: "US") == "USD")
        #expect(TravelReferenceData.currencyCode(forCountryCode: "TH") == "THB")
        #expect(TravelReferenceData.currencyCode(forCountryCode: " th ") == "THB")
    }

    @Test
    func currencyIsNilForUnknownCodes() {
        #expect(TravelReferenceData.currencyCode(forCountryCode: nil) == nil)
        #expect(TravelReferenceData.currencyCode(forCountryCode: "") == nil)
        #expect(TravelReferenceData.currencyCode(forCountryCode: "ZZ") == nil)
        #expect(TravelReferenceData.currencyCode(forCountryCode: "Morocco") == nil)
    }
}
