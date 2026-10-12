import Foundation
import NomadCore
import Testing

struct EmergencyNumbersTests {
    @Test
    func lookupIsCaseInsensitiveAndTrimsWhitespace() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "fr") == EmergencyNumberDirectory.numbers(forCountryCode: "FR"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: " Fr ") == EmergencyNumberDirectory.numbers(forCountryCode: "FR"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "FR") != nil)
    }

    @Test
    func unknownOrMissingCodesReturnNil() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: nil) == nil)
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "") == nil)
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "ZZ") == nil)
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "France") == nil)
    }

    @Test
    func unverifiedCountriesAreDeliberatelyAbsent() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "LA") == nil)
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "GT") == nil)
    }

    @Test
    func moroccoListsPoliceAmbulanceFireAndTheRuralGendarmerie() {
        let morocco = EmergencyNumberDirectory.numbers(forCountryCode: "MA")
        #expect(morocco == EmergencyNumbers(
            general: "19",
            ambulance: "15",
            fire: "15",
            other: [EmergencyService(name: "Gendarmerie", number: "177")]
        ))
        #expect(morocco?.police == nil)
        #expect(morocco?.other == [EmergencyService(name: "Gendarmerie", number: "177")])
    }

    @Test
    func ruralAndHighwayPoliceAreStoredOnlyForVerifiedCountries() {
        let expected: [String: [EmergencyService]] = [
            "MA": [EmergencyService(name: "Gendarmerie", number: "177")],
            "ES": [EmergencyService(name: "Guardia Civil", number: "062")],
            "BR": [EmergencyService(name: "Federal Highway Police", number: "191")],
            "TH": [EmergencyService(name: "Highway Police", number: "1193")]
        ]
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let numbers = EmergencyNumberDirectory.numbers(forCountryCode: code) else { continue }
            #expect(numbers.other == expected[code, default: []], "unexpected other services for \(code)")
        }
        for (code, services) in expected {
            #expect(EmergencyNumberDirectory.numbers(forCountryCode: code)?.other == services, "missing other services for \(code)")
        }
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "FR")?.other == [])
    }

    @Test
    func spainListsTheGuardiaCivilEmergencyNumber() {
        let spain = EmergencyNumberDirectory.numbers(forCountryCode: "ES")
        #expect(spain == EmergencyNumbers(
            general: "112",
            other: [EmergencyService(name: "Guardia Civil", number: "062")]
        ))
        #expect(spain?.police == nil)
    }

    @Test
    func brazilListsTheFederalHighwayPolice() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "BR") == EmergencyNumbers(
            general: "190",
            ambulance: "192",
            fire: "193",
            other: [EmergencyService(name: "Federal Highway Police", number: "191")]
        ))
    }

    @Test
    func thailandListsTheHighwayPolice() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "TH") == EmergencyNumbers(
            general: "191",
            ambulance: "1669",
            fire: "199",
            other: [EmergencyService(name: "Highway Police", number: "1193")]
        ))
    }

    @Test
    func additionalServiceNumbersNeverDuplicateTheNumbersAlreadyShown() {
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let numbers = EmergencyNumberDirectory.numbers(forCountryCode: code) else { continue }
            let shown = [numbers.general, numbers.police, numbers.ambulance, numbers.fire].compactMap { $0 }
            for service in numbers.other {
                #expect(shown.contains(service.number) == false, "\(service.name) duplicates a shown number for \(code)")
            }
        }
    }

    @Test
    func europeanSpotChecks() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "PT") == EmergencyNumbers(general: "112"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "FR") == EmergencyNumbers(general: "112", police: "17", ambulance: "15", fire: "18"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "DE") == EmergencyNumbers(general: "112", police: "110"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "GB")?.general == "999")
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "CH") == EmergencyNumbers(general: "112", police: "117", ambulance: "144", fire: "118"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "NO") == EmergencyNumbers(general: "112", ambulance: "113", fire: "110"))
    }

    @Test
    func worldSpotChecks() {
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "US") == EmergencyNumbers(general: "911"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "AU")?.general == "000")
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "NZ")?.general == "111")
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "JP") == EmergencyNumbers(general: "110", ambulance: "119", fire: "119"))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "TH") == EmergencyNumbers(general: "191", ambulance: "1669", fire: "199", other: [EmergencyService(name: "Highway Police", number: "1193")]))
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "CO")?.general == "123")
        #expect(EmergencyNumberDirectory.numbers(forCountryCode: "AE") == EmergencyNumbers(general: "999", ambulance: "998", fire: "997"))
    }

    @Test
    func perServiceNumbersAreOnlyStoredWhenTheyDifferFromTheGeneralNumber() {
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let numbers = EmergencyNumberDirectory.numbers(forCountryCode: code) else { continue }
            #expect(numbers.police != numbers.general, "police duplicates general for \(code)")
            #expect(numbers.ambulance != numbers.general, "ambulance duplicates general for \(code)")
            #expect(numbers.fire != numbers.general, "fire duplicates general for \(code)")
            #expect(numbers.general.isEmpty == false)
        }
    }

    @Test
    func directoryCoversTheMostVisitedNomadCountries() {
        let required = [
            "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IE", "IT", "LV",
            "LI", "LT", "LU", "MT", "NL", "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "GB", "CH", "TR", "GE",
            "AL", "BA", "ME", "RS", "MK", "UA", "MD", "US", "CA", "MX", "CR", "PA", "CO", "PE", "CL", "AR", "BR",
            "EC", "UY", "TH", "VN", "ID", "MY", "SG", "PH", "JP", "KR", "TW", "IN", "LK", "NP", "KH", "AU", "NZ",
            "AE", "IL", "JO", "EG", "MA", "ZA", "KE", "TZ"
        ]
        for code in required {
            #expect(EmergencyNumberDirectory.numbers(forCountryCode: code) != nil, "missing \(code)")
        }
    }

    @Test
    func currentCountryCodePrefersDeviceLocationThenIPLocationThenLocalInfo() {
        let device = makeLocation(countryCode: "pt")
        let ip = makeLocation(countryCode: "ES")
        let info = makeLocalInfo(countryCode: "fr")

        #expect(makeSnapshot(device: device, ip: ip, localInfo: info).currentCountryCode == "PT")
        #expect(makeSnapshot(device: nil, ip: ip, localInfo: info).currentCountryCode == "ES")
        #expect(makeSnapshot(device: nil, ip: nil, localInfo: info).currentCountryCode == "FR")
        #expect(makeSnapshot(device: nil, ip: nil, localInfo: nil).currentCountryCode == nil)
    }

    @Test
    func currentCountryCodeSkipsBlankCodes() {
        let blankDevice = makeLocation(countryCode: "  ")
        let missingIP = makeLocation(countryCode: nil)
        let info = makeLocalInfo(countryCode: "de")

        #expect(makeSnapshot(device: blankDevice, ip: missingIP, localInfo: info).currentCountryCode == "DE")
        #expect(makeSnapshot(device: blankDevice, ip: missingIP, localInfo: nil).currentCountryCode == nil)
    }
}

private func makeLocation(countryCode: String?) -> IPLocationSnapshot {
    IPLocationSnapshot(
        city: nil,
        region: nil,
        country: nil,
        countryCode: countryCode,
        latitude: nil,
        longitude: nil,
        timeZone: nil,
        provider: "test",
        fetchedAt: .now
    )
}

private func makeLocalInfo(countryCode: String?) -> LocalInfoSnapshot {
    LocalInfoSnapshot(
        status: .ready,
        locality: nil,
        administrativeRegion: nil,
        countryCode: countryCode,
        countryName: nil,
        timeZoneIdentifier: nil,
        subdivisionCode: nil,
        publicHolidayStatus: LocalHolidayStatus(state: .unavailable, currentPeriod: nil, nextPeriod: nil, note: nil),
        schoolHolidayStatus: nil,
        localPriceLevel: nil,
        sources: [],
        fetchedAt: nil,
        detail: nil,
        note: nil
    )
}

private func makeSnapshot(
    device: IPLocationSnapshot?,
    ip: IPLocationSnapshot?,
    localInfo: LocalInfoSnapshot?
) -> DashboardSnapshot {
    DashboardSnapshot(
        network: NetworkSectionSnapshot(
            throughput: nil,
            connectivity: ConnectivitySnapshot(pathAvailable: true, internetState: .online, lastCheckedAt: .now),
            latency: nil,
            downloadHistory: [],
            uploadHistory: [],
            latencyHistory: []
        ),
        power: PowerSectionSnapshot(snapshot: nil, chargeHistory: [], dischargeHistory: []),
        travelContext: TravelContextSnapshot(
            wifi: nil,
            vpn: nil,
            timeZoneIdentifier: "Europe/Madrid",
            deviceLocation: device,
            publicIP: nil,
            location: ip
        ),
        weather: nil,
        localInfo: localInfo,
        appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: [])
    )
}
