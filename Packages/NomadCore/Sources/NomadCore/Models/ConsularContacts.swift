import Foundation

// Bundled, offline consular contact data for a traveller's home country (citizenship): the foreign
// ministry's emergency line for citizens abroad, its trip-registration service and the official
// list of its embassies and consulates.
//
// Safety-critical data: a wrong number is worse than none, so a country is only listed when its
// emergency number was read from the ministry's or government's own website. Where the number is
// confirmed but no official trip-registration service exists or could be confirmed, the
// registration fields are nil. Where a ministry publishes its line only as an out-of-hours
// emergency number, the note says so.
//
// Verified 2026-10
//
// Excluded (the lookup returns nil):
//  - Belgium: no central emergency line for Belgians abroad; diplomatie.belgium.be lists only the
//    switchboard (+32 2 501 81 11, office hours) and per-embassy out-of-hours numbers.
//  - Croatia: mvep.gov.hr publishes only per-mission duty numbers; the Zagreb number is not
//    described as a 24-hour line.
//  - Cyprus: gov.cy lists +357 22 801000 for emergencies but only with 08:30-15:00 hours; the
//    after-hours mobile appears only in older crisis-specific advisories.
//  - Greece: mfa.gr names the switchboard (+30 210 368 1000) for urgent help abroad but does not
//    state that it is staffed around the clock; duty-officer lines are listed without hours.
//  - Lithuania: urm.lt and keliauk.urm.lt sit behind bot protection and could not be read
//    directly; the number could not be confirmed first-hand.
//  - Poland: the Zintegrowany Telefon Dyzurny only runs 17:00-09:00 per host country and the
//    information line has set hours; no single 24/7 number is published on gov.pl.
//  - Romania: mae.ro sits behind bot protection and publishes no single national emergency number
//    (calls are routed through each mission's number to a call centre).
//
// Sources (emergency line | trip registration | missions list):
//  - Austria (AT): https://www.bmeia.gv.at/reise-services/auslandsservice/notfalltipps |
//    https://auslandsregistrierung.bmeia.gv.at/ |
//    https://www.bmeia.gv.at/en/embassies-consulates/search-for-austrian-representations
//  - Bulgaria (BG): https://www.mfa.bg/en/7 (emergency hotline, 24/7 service) | none |
//    https://www.mfa.bg/en/embassyinfo
//  - Canada (CA): https://travel.gc.ca/assistance/emergency-assistance |
//    https://travel.gc.ca/travelling/registration |
//    https://travel.gc.ca/assistance/embassies-consulates
//  - Czech Republic (CZ): https://mzv.gov.cz/jnp/cz/udalosti_a_media/tiskove_zpravy/mzv_zavadi_jednotnou_nouzovou_linku_pro.html
//    and https://mzv.gov.cz/lima/cz/Viza_a_konzularni_informace/pomoc_v_nouzi/index.html |
//    https://drozd.mzv.gov.cz/ (page: https://mzv.gov.cz/jnp/cz/cestujeme/drozd/index.html) |
//    https://mzv.gov.cz/jnp/en/diplomatic_missions/index.html
//  - Denmark (DK): https://um.dk/rejse-og-ophold/ | https://danskerlisten.um.dk/ |
//    https://um.dk/om-os/kontakt/find-os-i-verden/
//  - Estonia (EE): https://reisitargalt.vm.ee/ | https://reisitargalt.vm.ee/registreeri-reis/ |
//    https://vm.ee/en/consular-visa-and-travel-information/estonian-representations-around-world
//  - Finland (FI): https://um.fi/service-24/7 | https://um.fi/matkustusilmoitus
//    (service: https://matkustusilmoitus.fi/) | https://finlandabroad.fi/frontpage
//  - France (FR): https://www.diplomatie.gouv.fr/fr/services/faq/voyage/a-l-etranger-si-j-ai-un-probleme-qui-puis-je-contacter
//    and https://www.diplomatie.gouv.fr/fr/conseils-aux-voyageurs (CDCS active 24/7) |
//    https://fildariane.diplomatie.gouv.fr/fildariane-internet/accueil |
//    https://www.diplomatie.gouv.fr/fr/services/j-ai-une-question/annuaire-et-contacts
//  - Germany (DE): https://www.auswaertiges-amt.de/de/service/fragenkatalog-node/15-notrufnummer/606090
//    (switchboard staffed 24 hours) and https://www.auswaertiges-amt.de/de/aamt/krisenreaktionszentrum-node |
//    https://krisenvorsorgeliste.diplo.de/ |
//    https://www.auswaertiges-amt.de/en/about-us/auslandsvertretungen/deutsche-auslandsvertretungen
//  - Hungary (HU): https://konzinfo.mfa.gov.hu/bajban-kulfoldon/elerhetosegek (Consular
//    Information and Duty Centre, out of office hours) |
//    https://konzinfo.mfa.gov.hu/regisztralja-kulfoldi-utazasat |
//    https://konzinfo.mfa.gov.hu/kulkepviseletek/osszes
//  - Iceland (IS): https://www.government.is/topics/foreign-affairs/consular-affairs/ | none |
//    https://www.government.is/ministries/diplomatic-missions/
//  - Ireland (IE): https://www.ireland.ie/en/dfa/overseas-travel/contact-dfa-consular-assistance/
//    (out-of-hours emergency line) | https://citizensregistration.dfa.ie/ |
//    https://www.ireland.ie/en/dfa/embassies/
//  - Italy (IT): https://www.esteri.it/en/unita_crisi/ | https://www.dovesiamonelmondo.it/ |
//    https://www.esteri.it/en/ministero/struttura/laretediplomatica/
//  - Latvia (LV): https://www.mfa.gov.lv/en/assistance-emergency-situations-abroad | none |
//    https://www.mfa.gov.lv/en/latvias-embassies-and-consulates
//  - Luxembourg (LU): https://mae.gouvernement.lu/fr/services-aux-citoyens/voyages/assistance-consulaire.html
//    (permanence for nationals, emergencies outside office hours) |
//    https://guichet.public.lu/en/citoyens/loisirs/tourisme/droits-voyageurs/sejour-etranger/declaration-sejour-etranger.html |
//    https://mae.gouvernement.lu/en/missions-diplomatiques/missions-diplomatiques-et-consulaires-luxembourgeoises.html
//  - Malta (MT): https://foreign.gov.mt/service/assistance-to-maltese-citizens-in-distress-whilst-abroad/ |
//    none | https://foreign.gov.mt/ministry/representations/
//  - Netherlands (NL): https://www.netherlandsworldwide.nl/contact/contacting-the-24-7-bz-contact-centre |
//    https://www.netherlandsworldwide.nl/information-service |
//    https://www.netherlandsworldwide.nl/contact/embassies-consulates-general
//  - New Zealand (NZ): https://www.govt.nz/browse/leaving-nz/emergency-help-when-youre-overseas/ and
//    https://www.safetravel.govt.nz/ | https://www.safetravel.govt.nz/register |
//    https://www.safetravel.govt.nz/destinations
//  - Norway (NO): https://www.norway.no/es/spain/for-nordmenn/reise--og-sikkerhetsinformasjon/sikkerhetsinformasjon/informasjon-om-uds-krisehandtering/
//    (operations centre, 24 hours a day) and
//    https://www.norway.no/en/jordan/for-nordmenn/ambassadens-tjenester2/bistand-til-norske-borgere/ |
//    https://www.reiseregistrering.no/ | https://www.norway.no/en/
//  - Portugal (PT): https://haia.embaixadaportugal.mne.gov.pt/pt/seccao-consular/assistencia-situacoes-emergencia
//    (GEC, 24 hours a day) | https://portaldascomunidades.mne.gov.pt/pt/vai-viajar/registo-do-viajante |
//    https://portaldascomunidades.mne.gov.pt/pt/rede-consular
//  - Slovakia (SK): https://www.mzv.sk/en/services/travel-abroad/emergency-abroad (operational
//    crisis centre, non-stop) |
//    https://www.mzv.sk/en/services/travel-abroad/registration-before-traveling-abroad |
//    https://www.mzv.sk/en/services/long-term-abroad/embassies-list
//  - Slovenia (SI): https://e-uprava.gov.si/en/podrocja/travel/travel-information/recommendations-for-your-stay-abroad.html
//    (emergency service, 24 hours) and https://www.gov.si/en/representations/embassy-manila/consular-information/ |
//    https://www.gov.si/zbirke/storitve/elastovka/ | https://www.gov.si/en/representations/
//  - Spain (ES): https://www.exteriores.gob.es/es/ServiciosAlCiudadano/Paginas/Telefonos-de-Asistencia-consular.aspx
//    (listed +34 910001249 for consular emergency, contactable 24 hours) |
//    https://registroviajeros.exteriores.gob.es/ | https://www.exteriores.gob.es/en/EmbajadasConsulados
//  - Sweden (SE): https://www.regeringen.se/uds-reseinformation/hjalp-till-svenskar-utomlands/kontakta-ud-och-ambassaderna/
//    (UD-jouren, staffed around the clock) |
//    https://www.swedenabroad.se/sv/om-utlandet-f%C3%B6r-svenska-medborgare/reseinformation/inf%C3%B6r-resan/anm%C3%A4l-dig-till-svensklistan/ |
//    https://www.swedenabroad.se/en/embassies/
//  - Switzerland (CH): https://www.schweiz-vereinigteskoenigreich.eda.admin.ch/en/contact-helpline-fdfa
//    (Helpline FDFA, 365 days a year, around the clock) |
//    https://www.eda.admin.ch/en/travel-admin-app-en | https://www.eda.admin.ch/en/countryterritory-overview
//  - United Kingdom (GB): https://www.gov.uk/guidance/consular-assistance-how-the-foreign-commonwealth-development-office-provides-support
//    | none (travel advice email alerts only) | https://www.gov.uk/world/organisations
//  - United States (US): https://www.state.gov/travelers (+1 202 501 4444 from overseas; the
//    toll-free 1 888 407 4747 only works from the US and Canada) | https://step.state.gov/ |
//    https://www.usembassy.gov/
//  - Australia (AU): https://www.smartraveller.gov.au/i-need-urgent-help |
//    https://www.smartraveller.gov.au/our-role/smartraveller-subscription |
//    https://www.dfat.gov.au/about-us/our-locations/missions/Pages/our-embassies-and-consulates-overseas.aspx

/// How a traveller's home-country foreign ministry can be reached from abroad.
public struct ConsularContacts: Equatable, Sendable {
    public let ministryName: String
    /// International format, ready to display and dial.
    public let emergencyPhone: String
    /// Short caveat about when or for whom the line applies, for example "24/7 · for citizens in distress abroad".
    public let emergencyPhoneNote: String?
    /// The ministry's own trip-registration or traveller-notification service, when one exists.
    public let travelRegistrationURL: URL?
    public let travelRegistrationName: String?
    /// The official list of the country's embassies and consulates.
    public let missionsDirectoryURL: URL?

    public init(
        ministryName: String,
        emergencyPhone: String,
        emergencyPhoneNote: String? = nil,
        travelRegistrationURL: URL? = nil,
        travelRegistrationName: String? = nil,
        missionsDirectoryURL: URL? = nil
    ) {
        self.ministryName = ministryName
        self.emergencyPhone = emergencyPhone
        self.emergencyPhoneNote = emergencyPhoneNote
        self.travelRegistrationURL = travelRegistrationURL
        self.travelRegistrationName = travelRegistrationName
        self.missionsDirectoryURL = missionsDirectoryURL
    }
}

public enum ConsularContactsDirectory {
    /// Consular contacts for an ISO 3166-1 alpha-2 citizenship code (case-insensitive), or nil when unknown.
    public static func contacts(forCitizenship code: String?) -> ConsularContacts? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return entries[normalized]
    }

    private static func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private static let entries: [String: ConsularContacts] = [
        // European Union
        "AT": ConsularContacts(
            ministryName: "Federal Ministry for European and International Affairs of Austria",
            emergencyPhone: "+43 1 90115 4411",
            emergencyPhoneNote: "24/7 · emergencies abroad",
            travelRegistrationURL: url("https://auslandsregistrierung.bmeia.gv.at/"),
            travelRegistrationName: "Travel registration",
            missionsDirectoryURL: url("https://www.bmeia.gv.at/en/embassies-consulates/search-for-austrian-representations")
        ),
        "BG": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Bulgaria",
            emergencyPhone: "+359 2 948 24 04",
            emergencyPhoneNote: "24/7 · emergency hotline",
            missionsDirectoryURL: url("https://www.mfa.bg/en/embassyinfo")
        ),
        "CZ": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of the Czech Republic",
            emergencyPhone: "+420 222 420 222",
            emergencyPhoneNote: "24/7 · urgent cases for citizens abroad",
            travelRegistrationURL: url("https://drozd.mzv.gov.cz/"),
            travelRegistrationName: "DROZD voluntary registration",
            missionsDirectoryURL: url("https://mzv.gov.cz/jnp/en/diplomatic_missions/index.html")
        ),
        "DK": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Denmark",
            emergencyPhone: "+45 3392 1112",
            emergencyPhoneNote: "24/7 · Global Duty Centre",
            travelRegistrationURL: url("https://danskerlisten.um.dk/"),
            travelRegistrationName: "Danskerlisten",
            missionsDirectoryURL: url("https://um.dk/om-os/kontakt/find-os-i-verden/")
        ),
        "EE": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Estonia",
            emergencyPhone: "+372 5301 9999",
            emergencyPhoneNote: "24/7 · emergencies abroad",
            travelRegistrationURL: url("https://reisitargalt.vm.ee/registreeri-reis/"),
            travelRegistrationName: "Reisi Targalt trip registration",
            missionsDirectoryURL: url("https://vm.ee/en/consular-visa-and-travel-information/estonian-representations-around-world")
        ),
        "FI": ConsularContacts(
            ministryName: "Ministry for Foreign Affairs of Finland",
            emergencyPhone: "+358 9 1605 5555",
            emergencyPhoneNote: "24/7 · consular emergencies only, no visa enquiries",
            travelRegistrationURL: url("https://matkustusilmoitus.fi/"),
            travelRegistrationName: "Travel notification",
            missionsDirectoryURL: url("https://finlandabroad.fi/frontpage")
        ),
        "FR": ConsularContacts(
            ministryName: "Ministry for Europe and Foreign Affairs of France",
            emergencyPhone: "+33 1 53 59 11 00",
            emergencyPhoneNote: "24/7 · Crisis and Support Centre",
            travelRegistrationURL: url("https://fildariane.diplomatie.gouv.fr/fildariane-internet/accueil"),
            travelRegistrationName: "Ariane",
            missionsDirectoryURL: url("https://www.diplomatie.gouv.fr/fr/services/j-ai-une-question/annuaire-et-contacts")
        ),
        "DE": ConsularContacts(
            ministryName: "Federal Foreign Office of Germany",
            emergencyPhone: "+49 30 5000 0",
            emergencyPhoneNote: "24/7 · emergencies only, no visa enquiries",
            travelRegistrationURL: url("https://krisenvorsorgeliste.diplo.de/"),
            travelRegistrationName: "Crisis preparedness list (ELEFAND)",
            missionsDirectoryURL: url("https://www.auswaertiges-amt.de/en/about-us/auslandsvertretungen/deutsche-auslandsvertretungen")
        ),
        "HU": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Hungary",
            emergencyPhone: "+36 80 36 80 36",
            emergencyPhoneNote: "Consular Duty Centre · outside embassy hours",
            travelRegistrationURL: url("https://konzinfo.mfa.gov.hu/regisztralja-kulfoldi-utazasat"),
            travelRegistrationName: "Travel registration",
            missionsDirectoryURL: url("https://konzinfo.mfa.gov.hu/kulkepviseletek/osszes")
        ),
        "IE": ConsularContacts(
            ministryName: "Department of Foreign Affairs of Ireland",
            emergencyPhone: "+353 1 408 2000",
            emergencyPhoneNote: "Emergency line · outside office hours",
            travelRegistrationURL: url("https://citizensregistration.dfa.ie/"),
            travelRegistrationName: "Citizen Registration",
            missionsDirectoryURL: url("https://www.ireland.ie/en/dfa/embassies/")
        ),
        "IT": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs and International Cooperation of Italy",
            emergencyPhone: "+39 06 36225",
            emergencyPhoneNote: "24/7 · Crisis Unit operations room",
            travelRegistrationURL: url("https://www.dovesiamonelmondo.it/"),
            travelRegistrationName: "Dove siamo nel mondo",
            missionsDirectoryURL: url("https://www.esteri.it/en/ministero/struttura/laretediplomatica/")
        ),
        "LV": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Latvia",
            emergencyPhone: "+371 2633 7711",
            emergencyPhoneNote: "24/7 · consular officer on call",
            missionsDirectoryURL: url("https://www.mfa.gov.lv/en/latvias-embassies-and-consulates")
        ),
        "LU": ConsularContacts(
            ministryName: "Ministry of Foreign and European Affairs of Luxembourg",
            emergencyPhone: "+352 247 72300",
            emergencyPhoneNote: "Luxembourg nationals · emergencies outside office hours",
            travelRegistrationURL: url("https://guichet.public.lu/en/citoyens/loisirs/tourisme/droits-voyageurs/sejour-etranger/declaration-sejour-etranger.html"),
            travelRegistrationName: "Declare your stay abroad (LamA)",
            missionsDirectoryURL: url("https://mae.gouvernement.lu/en/missions-diplomatiques/missions-diplomatiques-et-consulaires-luxembourgeoises.html")
        ),
        "MT": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Malta",
            emergencyPhone: "+356 21 242 191",
            emergencyPhoneNote: "24/7 · emergency consular assistance",
            missionsDirectoryURL: url("https://foreign.gov.mt/ministry/representations/")
        ),
        "NL": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of the Netherlands",
            emergencyPhone: "+31 247 247 247",
            emergencyPhoneNote: "24/7 · BZ Contact Centre",
            travelRegistrationURL: url("https://www.netherlandsworldwide.nl/information-service"),
            travelRegistrationName: "Ministry of Foreign Affairs Information Service",
            missionsDirectoryURL: url("https://www.netherlandsworldwide.nl/contact/embassies-consulates-general")
        ),
        "PT": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Portugal",
            emergencyPhone: "+351 217 929 714",
            emergencyPhoneNote: "24/7 · Consular Emergency Office",
            travelRegistrationURL: url("https://portaldascomunidades.mne.gov.pt/pt/vai-viajar/registo-do-viajante"),
            travelRegistrationName: "Registo Viajante",
            missionsDirectoryURL: url("https://portaldascomunidades.mne.gov.pt/pt/rede-consular")
        ),
        "SK": ConsularContacts(
            ministryName: "Ministry of Foreign and European Affairs of the Slovak Republic",
            emergencyPhone: "+421 2 5978 5978",
            emergencyPhoneNote: "24/7 · International Operational Crisis Centre",
            travelRegistrationURL: url("https://www.mzv.sk/en/services/travel-abroad/registration-before-traveling-abroad"),
            travelRegistrationName: "Registration before travelling abroad",
            missionsDirectoryURL: url("https://www.mzv.sk/en/services/long-term-abroad/embassies-list")
        ),
        "SI": ConsularContacts(
            ministryName: "Ministry of Foreign and European Affairs of Slovenia",
            emergencyPhone: "+386 1 478 22 19",
            emergencyPhoneNote: "24/7 · ministry emergency service",
            travelRegistrationURL: url("https://www.gov.si/zbirke/storitve/elastovka/"),
            travelRegistrationName: "eLastovka",
            missionsDirectoryURL: url("https://www.gov.si/en/representations/")
        ),
        "ES": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs, European Union and Cooperation of Spain",
            emergencyPhone: "+34 910 001 249",
            emergencyPhoneNote: "24/7 · Consular Emergency Unit",
            travelRegistrationURL: url("https://registroviajeros.exteriores.gob.es/"),
            travelRegistrationName: "Registro de Viajeros",
            missionsDirectoryURL: url("https://www.exteriores.gob.es/en/EmbajadasConsulados")
        ),
        "SE": ConsularContacts(
            ministryName: "Ministry for Foreign Affairs of Sweden",
            emergencyPhone: "+46 8 405 50 05",
            emergencyPhoneNote: "24/7 · UD-jouren, urgent consular emergencies",
            travelRegistrationURL: url("https://www.swedenabroad.se/sv/om-utlandet-f%C3%B6r-svenska-medborgare/reseinformation/inf%C3%B6r-resan/anm%C3%A4l-dig-till-svensklistan/"),
            travelRegistrationName: "Svensklistan",
            missionsDirectoryURL: url("https://www.swedenabroad.se/en/embassies/")
        ),

        // Other European countries
        "NO": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs of Norway",
            emergencyPhone: "+47 23 95 00 00",
            emergencyPhoneNote: "24/7 · Operations Centre",
            travelRegistrationURL: url("https://www.reiseregistrering.no/"),
            travelRegistrationName: "Travel registration",
            missionsDirectoryURL: url("https://www.norway.no/en/")
        ),
        "IS": ConsularContacts(
            ministryName: "Ministry for Foreign Affairs of Iceland",
            emergencyPhone: "+354 545 0112",
            emergencyPhoneNote: "24/7 · Consular Affairs Unit",
            missionsDirectoryURL: url("https://www.government.is/ministries/diplomatic-missions/")
        ),
        "CH": ConsularContacts(
            ministryName: "Federal Department of Foreign Affairs of Switzerland",
            emergencyPhone: "+41 58 465 33 33",
            emergencyPhoneNote: "24/7 · Helpline FDFA",
            travelRegistrationURL: url("https://www.eda.admin.ch/en/travel-admin-app-en"),
            travelRegistrationName: "Travel Admin",
            missionsDirectoryURL: url("https://www.eda.admin.ch/en/countryterritory-overview")
        ),
        "GB": ConsularContacts(
            ministryName: "Foreign, Commonwealth & Development Office of the United Kingdom",
            emergencyPhone: "+44 20 7008 5000",
            emergencyPhoneNote: "24/7 · choose \"Consular services for British nationals\"",
            missionsDirectoryURL: url("https://www.gov.uk/world/organisations")
        ),

        // North America and Asia-Pacific
        "US": ConsularContacts(
            ministryName: "U.S. Department of State",
            emergencyPhone: "+1 202 501 4444",
            emergencyPhoneNote: "Overseas Citizens Services · from outside the US and Canada",
            travelRegistrationURL: url("https://step.state.gov/"),
            travelRegistrationName: "Smart Traveler Enrollment Program (STEP)",
            missionsDirectoryURL: url("https://www.usembassy.gov/")
        ),
        "CA": ConsularContacts(
            ministryName: "Global Affairs Canada",
            emergencyPhone: "+1 613 996 8885",
            emergencyPhoneNote: "24/7 · Emergency Watch and Response Centre, call collect where available",
            travelRegistrationURL: url("https://travel.gc.ca/travelling/registration"),
            travelRegistrationName: "Registration of Canadians Abroad",
            missionsDirectoryURL: url("https://travel.gc.ca/assistance/embassies-consulates")
        ),
        "AU": ConsularContacts(
            ministryName: "Department of Foreign Affairs and Trade of Australia",
            emergencyPhone: "+61 2 6261 3305",
            emergencyPhoneNote: "24/7 · Consular Emergency Centre, from overseas",
            travelRegistrationURL: url("https://www.smartraveller.gov.au/our-role/smartraveller-subscription"),
            travelRegistrationName: "Smartraveller subscription",
            missionsDirectoryURL: url("https://www.dfat.gov.au/about-us/our-locations/missions/Pages/our-embassies-and-consulates-overseas.aspx")
        ),
        "NZ": ConsularContacts(
            ministryName: "Ministry of Foreign Affairs and Trade of New Zealand",
            emergencyPhone: "+64 99 20 20 20",
            emergencyPhoneNote: "24/7 · Consular Emergency Assistance",
            travelRegistrationURL: url("https://www.safetravel.govt.nz/register"),
            travelRegistrationName: "SafeTravel registration",
            missionsDirectoryURL: url("https://www.safetravel.govt.nz/destinations")
        )
    ]
}
