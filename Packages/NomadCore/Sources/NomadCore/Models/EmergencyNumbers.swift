import Foundation

// Bundled, offline emergency phone numbers.
//
// Safety-critical data: a wrong number is worse than none, so a country is only listed when its
// numbers agree across an official source and at least one independent compilation. Countries
// that could not be verified are deliberately absent (the lookup returns nil), e.g. Laos (3-digit
// vs 4-digit forms) and Guatemala (no unified number; fire/ambulance split across volunteer
// brigades).
//
// Verified 2026-10
//
// Sources:
//  - EU 112: https://digital-strategy.ec.europa.eu/en/policies/112
//  - Austria: https://www.oesterreich.gv.at/en/themen/notfaelle_unfaelle_und_kriminalitaet/notrufnummern
//  - France: https://www.service-public.fr (numeros d'urgence 15/17/18/112)
//  - Switzerland: https://www.ch.ch/en/emergencies-and-danger/
//  - Greece: https://www.visitgreece.gr/before-you-travel/health-safety
//  - Czech Republic: https://portal.gov.cz/en/sluzby-vs/112-150-155-and-158-S2824
//  - Croatia: https://hakom.hr/en/112-single-european-emergency-call-number/184
//  - Slovenia: https://www.gov.si/teme/klic-v-sili/
//  - Luxembourg: https://guichet.public.lu/en/citoyens/sante/services-urgence/appel-urgence.html
//  - Belgium: https://securitecivile.be/en/what-do-emergency-centres-112-do
//  - Ireland: https://www.gov.ie/en/service/89da6-how-to-contact-emergency-services-in-ireland
//  - United Kingdom: https://www.gov.uk/guidance/999-and-112-the-uks-national-emergency-numbers
//  - Slovakia: https://www.slovensko.sk (national emergency numbers) and UNHCR Slovakia help pages
//  - Georgia: https://112.gov.ge
//  - Albania: Albanian 112 service paper (Transport Community) and ITU E.129 database
//  - Turkey: Ministry of Interior unification of emergency lines under 112 (2021)
//  - Ukraine: https://mvs.gov.ua/en/news (112 introduced; 101-104 remain in service)
//  - Hungary, Poland, Norway, Germany, Bosnia and Herzegovina, Montenegro, North Macedonia, Serbia,
//    Moldova: government travel advice (Canada, UK, Sweden, Australia) cross-checked against
//    https://en.wikipedia.org/wiki/List_of_emergency_telephone_numbers
//  - Americas: https://www.argentina.gob.ar/tema/emergencias (AR), https://www.gob.ec/ecu-911 (EC),
//    https://www.gub.uy (UY), Ley 7566 (CR), Ley 70 de 2019 (PA), IFT/SESNSP 911 migration (MX),
//    CRT Resolucion 087 de 1997 (CO), Infobae/PNP/SAMU listings (PE), Carabineros/Bomberos/SAMU (CL)
//  - Asia-Pacific: https://www.triplezero.gov.au (AU), https://www.govt.nz/browse/law-crime-and-justice/crimes-and-emergencies/111-emergency-service/ (NZ),
//    https://www.scdf.gov.sg (SG), DILG Unified 911 / EO 56 (PH), UK FCDO and Canada travel advice (KH, NP, TW),
//    Vietnam police portal (VN), Kominfo 112 call centre (ID), Sri Lanka Police emergency list (LK),
//    MHA ERSS https://www.mha.gov.in/en/commoncontent/emergency-response-support-system-erss (IN)
//  - Middle East / Africa: https://u.ae/en/information-and-services/justice-safety-and-the-law/handling-emergencies (AE),
//    Public Security Directorate https://jordan.gov.jo (JO), Western Cape Government emergency numbers (ZA)
//  - Morocco: ANRT, the telecoms regulator, https://www.anrt.ma/infos-pratiques/que-sont-les-numeros-speciaux
//    (177 Gendarmerie Royale, 19 Police, 15 Pompiers; reachable from mobile and fixed lines). The
//    Protection Civile (15) also dispatches ambulances. UK FCDO and Canada travel advice list
//    190 (police) and 150 (ambulance/fire) instead; those are alternatives and deliberately not stored.
//  - Cross-check for all rows: https://en.wikipedia.org/wiki/List_of_emergency_telephone_numbers

/// An additional emergency service that does not fit police, ambulance or fire, for example a
/// gendarmerie covering rural areas and highways.
public struct EmergencyService: Equatable, Sendable {
    public let name: String
    public let number: String

    public init(name: String, number: String) {
        self.name = name
        self.number = number
    }
}

/// Phone numbers to call in an emergency in one country.
public struct EmergencyNumbers: Equatable, Sendable {
    /// The number to call first. Where a country has no all-purpose number this is the police number.
    public let general: String
    /// Police, only when it differs from `general`.
    public let police: String?
    /// Ambulance, only when it differs from `general`.
    public let ambulance: String?
    /// Fire brigade, only when it differs from `general`.
    public let fire: String?
    /// Further services that do not fit the fields above, such as a rural gendarmerie.
    public let other: [EmergencyService]

    public init(
        general: String,
        police: String? = nil,
        ambulance: String? = nil,
        fire: String? = nil,
        other: [EmergencyService] = []
    ) {
        self.general = general
        self.police = police
        self.ambulance = ambulance
        self.fire = fire
        self.other = other
    }
}

public enum EmergencyNumberDirectory {
    /// Emergency numbers for an ISO 3166-1 alpha-2 country code (case-insensitive), or nil when unknown.
    public static func numbers(forCountryCode code: String?) -> EmergencyNumbers? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return entries[normalized]
    }

    private static let europeanSingle = EmergencyNumbers(general: "112")

    private static let entries: [String: EmergencyNumbers] = [
        // European Union and EEA
        "AT": EmergencyNumbers(general: "112", police: "133", ambulance: "144", fire: "122"),
        "BE": EmergencyNumbers(general: "112", police: "101"),
        "BG": europeanSingle,
        "HR": EmergencyNumbers(general: "112", police: "192", ambulance: "194", fire: "193"),
        "CY": europeanSingle,
        "CZ": EmergencyNumbers(general: "112", police: "158", ambulance: "155", fire: "150"),
        "DK": europeanSingle,
        "EE": europeanSingle,
        "FI": europeanSingle,
        "FR": EmergencyNumbers(general: "112", police: "17", ambulance: "15", fire: "18"),
        "DE": EmergencyNumbers(general: "112", police: "110"),
        "GR": EmergencyNumbers(general: "112", police: "100", ambulance: "166", fire: "199"),
        "HU": EmergencyNumbers(general: "112", police: "107", ambulance: "104", fire: "105"),
        "IS": europeanSingle,
        "IE": europeanSingle,
        "IT": europeanSingle,
        "LV": europeanSingle,
        "LI": EmergencyNumbers(general: "112", police: "117", ambulance: "144", fire: "118"),
        "LT": europeanSingle,
        "LU": EmergencyNumbers(general: "112", police: "113"),
        "MT": europeanSingle,
        "NL": europeanSingle,
        "NO": EmergencyNumbers(general: "112", ambulance: "113", fire: "110"),
        "PL": EmergencyNumbers(general: "112", police: "997", ambulance: "999", fire: "998"),
        "PT": europeanSingle,
        "RO": europeanSingle,
        "SK": EmergencyNumbers(general: "112", police: "158", ambulance: "155", fire: "150"),
        "SI": EmergencyNumbers(general: "112", police: "113"),
        "ES": europeanSingle,
        "SE": europeanSingle,

        // Other European countries
        "GB": EmergencyNumbers(general: "999"),
        "CH": EmergencyNumbers(general: "112", police: "117", ambulance: "144", fire: "118"),
        "TR": europeanSingle,
        "GE": europeanSingle,
        "AL": EmergencyNumbers(general: "112", police: "129", ambulance: "127", fire: "128"),
        "BA": EmergencyNumbers(general: "112", police: "122", ambulance: "124", fire: "123"),
        "ME": EmergencyNumbers(general: "112", police: "122", ambulance: "124", fire: "123"),
        "RS": EmergencyNumbers(general: "112", ambulance: "194", fire: "193"),
        "MK": EmergencyNumbers(general: "112", police: "192", ambulance: "194", fire: "193"),
        "UA": EmergencyNumbers(general: "112", police: "102", ambulance: "103", fire: "101"),
        "MD": europeanSingle,

        // Americas
        "US": EmergencyNumbers(general: "911"),
        "CA": EmergencyNumbers(general: "911"),
        "MX": EmergencyNumbers(general: "911"),
        "CR": EmergencyNumbers(general: "911"),
        "PA": EmergencyNumbers(general: "911"),
        "CO": EmergencyNumbers(general: "123"),
        "PE": EmergencyNumbers(general: "105", ambulance: "106", fire: "116"),
        "CL": EmergencyNumbers(general: "133", ambulance: "131", fire: "132"),
        "AR": EmergencyNumbers(general: "911", fire: "100"),
        "BR": EmergencyNumbers(general: "190", ambulance: "192", fire: "193"),
        "EC": EmergencyNumbers(general: "911"),
        "UY": EmergencyNumbers(general: "911"),

        // Asia-Pacific
        "TH": EmergencyNumbers(general: "191", ambulance: "1669", fire: "199"),
        "VN": EmergencyNumbers(general: "113", ambulance: "115", fire: "114"),
        "ID": EmergencyNumbers(general: "112", police: "110", fire: "113"),
        "MY": EmergencyNumbers(general: "999"),
        "SG": EmergencyNumbers(general: "999", ambulance: "995", fire: "995"),
        "PH": EmergencyNumbers(general: "911"),
        "JP": EmergencyNumbers(general: "110", ambulance: "119", fire: "119"),
        "KR": EmergencyNumbers(general: "112", ambulance: "119", fire: "119"),
        "TW": EmergencyNumbers(general: "110", ambulance: "119", fire: "119"),
        "IN": EmergencyNumbers(general: "112"),
        "LK": EmergencyNumbers(general: "119", ambulance: "1990", fire: "110"),
        "NP": EmergencyNumbers(general: "100", ambulance: "102", fire: "101"),
        "KH": EmergencyNumbers(general: "117", ambulance: "119", fire: "118"),
        "AU": EmergencyNumbers(general: "000"),
        "NZ": EmergencyNumbers(general: "111"),

        // Middle East and Africa
        "AE": EmergencyNumbers(general: "999", ambulance: "998", fire: "997"),
        "IL": EmergencyNumbers(general: "100", ambulance: "101", fire: "102"),
        "JO": EmergencyNumbers(general: "911"),
        "EG": EmergencyNumbers(general: "122", ambulance: "123", fire: "180"),
        "ZA": EmergencyNumbers(general: "112", police: "10111", ambulance: "10177"),
        "MA": EmergencyNumbers(
            general: "19",
            ambulance: "15",
            fire: "15",
            other: [EmergencyService(name: "Gendarmerie", number: "177")]
        ),
        "KE": EmergencyNumbers(general: "999"),
        "TZ": EmergencyNumbers(general: "112")
    ]
}

public extension DashboardSnapshot {
    /// Upper-cased ISO country code of where the user currently is: device location first, then
    /// IP geolocation, then the local info card. Blank codes are skipped.
    var currentCountryCode: String? {
        let candidates = [
            travelContext.deviceLocation?.countryCode,
            travelContext.location?.countryCode,
            localInfo?.countryCode
        ]

        return candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .first { $0.isEmpty == false }
    }
}
