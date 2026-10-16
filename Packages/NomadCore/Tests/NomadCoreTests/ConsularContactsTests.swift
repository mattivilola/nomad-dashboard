import Foundation
import NomadCore
import Testing

struct ConsularContactsTests {
    private static let coveredCodes = [
        "AT", "BG", "CZ", "DK", "EE", "FI", "FR", "DE", "HU", "IE", "IT", "LV", "LU", "MT", "NL", "PT", "SK", "SI",
        "ES", "SE", "NO", "IS", "CH", "GB", "US", "CA", "AU", "NZ"
    ]

    private static let excludedCodes = ["BE", "HR", "CY", "GR", "LT", "PL", "RO"]

    private static func allContacts() -> [(code: String, contacts: ConsularContacts)] {
        coveredCodes.compactMap { code in
            ConsularContactsDirectory.contacts(forCitizenship: code).map { (code, $0) }
        }
    }

    @Test
    func lookupIsCaseInsensitiveAndTrimsWhitespace() {
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "fi") == ConsularContactsDirectory.contacts(forCitizenship: "FI"))
        #expect(ConsularContactsDirectory.contacts(forCitizenship: " Fi ") == ConsularContactsDirectory.contacts(forCitizenship: "FI"))
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "FI") != nil)
    }

    @Test
    func unknownOrMissingCodesReturnNil() {
        #expect(ConsularContactsDirectory.contacts(forCitizenship: nil) == nil)
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "") == nil)
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "ZZ") == nil)
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "Finland") == nil)
    }

    @Test
    func unverifiedCountriesAreDeliberatelyAbsent() {
        for code in Self.excludedCodes {
            #expect(ConsularContactsDirectory.contacts(forCitizenship: code) == nil, "\(code) must stay excluded until verified")
        }
    }

    @Test
    func everyCoveredCountryIsPresent() {
        #expect(Self.allContacts().count == Self.coveredCodes.count)
        #expect(Set(Self.coveredCodes).isDisjoint(with: Self.excludedCodes))
    }

    @Test
    func finlandSpotCheck() {
        let finland = ConsularContactsDirectory.contacts(forCitizenship: "FI")
        #expect(finland?.ministryName == "Ministry for Foreign Affairs of Finland")
        #expect(finland?.emergencyPhone == "+358 9 1605 5555")
        #expect(finland?.travelRegistrationName == "Travel notification")
        #expect(finland?.travelRegistrationURL?.host == "matkustusilmoitus.fi")
        #expect(finland?.missionsDirectoryURL?.host == "finlandabroad.fi")
    }

    @Test
    func englishSpeakingSpotChecks() {
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "GB")?.emergencyPhone == "+44 20 7008 5000")
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "GB")?.travelRegistrationURL == nil)
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "US")?.emergencyPhone == "+1 202 501 4444")
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "US")?.travelRegistrationName == "Smart Traveler Enrollment Program (STEP)")
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "CA")?.emergencyPhone == "+1 613 996 8885")
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "CA")?.travelRegistrationName == "Registration of Canadians Abroad")
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "AU")?.emergencyPhone == "+61 2 6261 3305")
        #expect(ConsularContactsDirectory.contacts(forCitizenship: "AU")?.travelRegistrationName == "Smartraveller subscription")
    }

    @Test
    func registrationFieldsAreSetTogether() {
        for (code, contacts) in Self.allContacts() {
            #expect(
                (contacts.travelRegistrationURL == nil) == (contacts.travelRegistrationName == nil),
                "\(code) must set the registration URL and name together"
            )
        }
    }

    @Test
    func everyEntryHasAnInternationalPhoneNumber() {
        for (code, contacts) in Self.allContacts() {
            #expect(contacts.emergencyPhone.isEmpty == false, "\(code) has an empty phone number")
            #expect(contacts.emergencyPhone.hasPrefix("+"), "\(code) phone number must start with +")
            let digits = contacts.emergencyPhone.filter(\.isNumber)
            #expect(digits.count >= 8 && digits.count <= 15, "\(code) phone number has an implausible length")
            #expect(contacts.ministryName.isEmpty == false, "\(code) has an empty ministry name")
        }
    }

    @Test
    func everyURLUsesHTTPS() {
        for (code, contacts) in Self.allContacts() {
            let urls = [contacts.travelRegistrationURL, contacts.missionsDirectoryURL].compactMap(\.self)
            for url in urls {
                #expect(url.scheme == "https", "\(code) has a non-https URL: \(url)")
                #expect(url.host?.isEmpty == false, "\(code) has a URL without a host: \(url)")
            }
        }
    }

    @Test
    func everyEntryListsAnOfficialMissionsDirectory() {
        for (code, contacts) in Self.allContacts() {
            #expect(contacts.missionsDirectoryURL != nil, "\(code) is missing a missions directory")
        }
    }
}
