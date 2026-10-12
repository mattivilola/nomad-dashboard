import Foundation
@testable import NomadCore
@testable import NomadUI
import Testing

struct EmbassyCardPresentationTests {
    private static let locale = Locale(identifier: "en_US")
    private static let rabat = (latitude: 34.020, longitude: -6.841)

    private static func mission(
        _ id: String,
        sending: String,
        host: String = "MA",
        kind: DiplomaticMissionKind = .embassy,
        name: String? = nil,
        city: String? = "Rabat",
        latitude: Double = 34.02,
        longitude: Double = -6.84,
        address: String? = nil,
        website: String? = nil,
        approximate: Bool = true
    ) -> DiplomaticMission {
        DiplomaticMission(
            id: id,
            sendingCountry: sending,
            hostCountry: host,
            kind: kind,
            name: name ?? "Embassy of \(sending)",
            city: city,
            latitude: latitude,
            longitude: longitude,
            address: address,
            website: website,
            isApproximateLocation: approximate
        )
    }

    private static let index = DiplomaticMissionIndex(
        missions: [
            mission("FI-RAB", sending: "FI", name: "Embassy of Finland in Rabat", latitude: 34.05, longitude: -6.84, address: "Rue 1, Rabat", website: "https://finlandabroad.fi/rabat", approximate: false),
            mission("FI-CAS", sending: "FI", kind: .honoraryConsulate, name: "Honorary Consulate of Finland in Casablanca", city: "Casablanca", latitude: 33.57, longitude: -7.59),
            mission("SE-RAB", sending: "SE"),
            mission("DE-RAB", sending: "DE"),
            mission("DE-CAS", sending: "DE", kind: .consulateGeneral, city: "Casablanca", latitude: 33.57, longitude: -7.59),
            mission("FR-RAB", sending: "FR"),
            mission("FR-CAS", sending: "FR", kind: .consulateGeneral, city: "Casablanca", latitude: 33.57, longitude: -7.59),
            mission("FR-TNG", sending: "FR", kind: .consulate, city: "Tangier", latitude: 35.77, longitude: -5.80),
            mission("FR-AGA", sending: "FR", kind: .consulate, city: "Agadir", latitude: 30.42, longitude: -9.60),
            mission("SE-ES", sending: "SE", host: "ES", city: "Madrid", latitude: 40.4, longitude: -3.7),
            mission("DE-AU", sending: "DE", host: "AU", city: "Canberra", latitude: -35.3, longitude: 149.1)
        ],
        source: "Wikidata (CC0)",
        generatedAt: "2026-10-05"
    )

    private func presentation(
        _ citizenships: [String],
        host: String?,
        coordinate: (latitude: Double, longitude: Double)? = rabat
    ) -> EmbassyCardPresentation {
        EmbassyCardPresentation(
            citizenships: citizenships,
            hostCountry: host,
            coordinate: coordinate,
            index: Self.index,
            locale: Self.locale
        )
    }

    // MARK: Own missions

    @Test
    func finnInMoroccoSeesTheirEmbassyFirstWithKindCityAndDistance() throws {
        let card = presentation(["FI"], host: "MA")

        #expect(card.state == .abroad)
        #expect(card.subtitle == "Finland in Morocco")
        #expect(card.badge.title == "Listed")
        #expect(card.missions.map(\.id) == ["FI-RAB", "FI-CAS"])

        let embassy = try #require(card.missions.first)
        #expect(embassy.name == "Embassy of Finland in Rabat")
        #expect(embassy.kindTitle == "Embassy")
        #expect(embassy.locationText == "Rabat")
        #expect(embassy.distanceText == "3.3 km")
        #expect(embassy.address == "Rue 1, Rabat")
        #expect(embassy.websiteURL == URL(string: "https://finlandabroad.fi/rabat"))
        #expect(embassy.mapsURL != nil)
        #expect(card.fallbackMissions.isEmpty)
        #expect(card.fallbackNotice == nil)
    }

    @Test
    func approximateLocationsShowRoundedDistanceWithATilde() throws {
        let card = presentation(["FI"], host: "MA")
        let honorary = try #require(card.missions.last)

        #expect(honorary.distanceText == "~85 km")
        #expect(EmbassyCardPresentation.distanceText(kilometers: 4.2, isApproximate: true) == "~4 km")
        #expect(EmbassyCardPresentation.distanceText(kilometers: 0.2, isApproximate: true) == "~1 km")
        #expect(EmbassyCardPresentation.distanceText(kilometers: 4.2, isApproximate: false) == "4.2 km")
        #expect(EmbassyCardPresentation.distanceText(kilometers: 42.4, isApproximate: false) == "42 km")
    }

    @Test
    func distanceIsOmittedWithoutADeviceCoordinate() {
        let card = presentation(["FI"], host: "MA", coordinate: nil)

        #expect(card.missions.isEmpty == false)
        #expect(card.missions.allSatisfy { $0.distanceText == nil })
        #expect(card.summary == "+358 9 1605 5555")
        #expect(card.summaryHelp == "Embassy of Finland in Rabat · +358 9 1605 5555")
    }

    @Test
    func missionsAreCappedAtThree() {
        let card = presentation(["FR"], host: "MA")

        #expect(card.missions.count == 3)
        #expect(card.missions.first?.id == "FR-RAB")
    }

    @Test
    func dualCitizensSeeBothCountriesInTheSubtitleAndBothHotlines() {
        let card = presentation(["FI", "SE"], host: "MA")

        #expect(card.subtitle == "Finland and Sweden in Morocco")
        #expect(card.hotlines.map(\.id) == ["FI", "SE"])
        #expect(card.hotlines.first?.title == "Finland · Ministry for Foreign Affairs")
        #expect(card.links.map(\.id) == ["FI", "SE"])
    }

    @Test
    func dualCitizenshipSkipsTheCountryTheUserIsHomeIn() {
        let card = presentation(["FI", "SE"], host: "FI", coordinate: nil)

        #expect(card.state == .abroad)
        #expect(card.subtitle == "Sweden in Finland")
        #expect(card.hotlines.map(\.id) == ["FI", "SE"])
        #expect(card.links.map(\.id) == ["SE"])
    }

    // MARK: Hotline

    @Test
    func hotlineUsesTheMinistryShortNameAndItsOwnWording() throws {
        let hotline = try #require(presentation(["FI"], host: "MA").hotlines.first)

        #expect(hotline.title == "Ministry for Foreign Affairs")
        #expect(hotline.detail == "24/7 consular line · consular emergencies only, no visa enquiries")
        #expect(hotline.phone == "+358 9 1605 5555")
        #expect(hotline.help.contains("Ministry for Foreign Affairs of Finland"))
    }

    @Test
    func hotlineNeverClaimsAllDayServiceWhereTheNoteSaysOtherwise() {
        #expect(EmbassyCardPresentation.lineDescription(note: "Consular Duty Centre · outside embassy hours") == "Consular Duty Centre · outside embassy hours")
        #expect(EmbassyCardPresentation.lineDescription(note: "Emergency line · outside office hours") == "Emergency line · outside office hours")
        #expect(EmbassyCardPresentation.lineDescription(note: "24/7") == "24/7 consular line")
        #expect(EmbassyCardPresentation.lineDescription(note: "24/7 · Helpline FDFA") == "24/7 consular line · Helpline FDFA")
        #expect(EmbassyCardPresentation.lineDescription(note: nil) == "Consular emergency line")
        #expect(EmbassyCardPresentation.lineDescription(note: "  ") == "Consular emergency line")
    }

    @Test
    func everyBundledMinistryGetsAUsableShortName() {
        var checked = 0
        for region in Locale.Region.isoRegions {
            guard let contacts = ConsularContactsDirectory.contacts(forCitizenship: region.identifier) else {
                continue
            }

            let shortName = EmbassyCardPresentation.shortMinistryName(contacts.ministryName)
            #expect(shortName.isEmpty == false)
            #expect(shortName.hasSuffix(" of") == false)
            #expect(contacts.ministryName.hasPrefix(shortName))
            checked += 1
        }

        #expect(checked > 20)
    }

    @Test
    func shortMinistryNamesDropOnlyTheCountry() {
        #expect(EmbassyCardPresentation.shortMinistryName("Ministry for Foreign Affairs of Finland") == "Ministry for Foreign Affairs")
        #expect(EmbassyCardPresentation.shortMinistryName("Ministry of Foreign Affairs of the Czech Republic") == "Ministry of Foreign Affairs")
        #expect(EmbassyCardPresentation.shortMinistryName("Federal Foreign Office of Germany") == "Federal Foreign Office")
        #expect(EmbassyCardPresentation.shortMinistryName("Ministry of Foreign Affairs, European Union and Cooperation of Spain") == "Ministry of Foreign Affairs, European Union and Cooperation")
        #expect(EmbassyCardPresentation.shortMinistryName("U.S. Department of State") == "U.S. Department of State")
        #expect(EmbassyCardPresentation.shortMinistryName("Global Affairs Canada") == "Global Affairs Canada")
    }

    @Test
    func citizenshipWithoutBundledContactsHasNoHotlineButStillGetsMissions() {
        let card = presentation(["DE"], host: "AU", coordinate: nil)
        // Germany has contacts; Brazil has none.
        let brazil = presentation(["BR"], host: "AU", coordinate: nil)

        #expect(card.hotlines.count == 1)
        #expect(brazil.hotlines.isEmpty)
        #expect(brazil.links.isEmpty)
    }

    // MARK: Fallback

    @Test
    func nordicCitizenWithoutOwnMissionGetsTheNordicNoticeAndSendingCountryNames() throws {
        let card = presentation(["FI"], host: "ES", coordinate: nil)

        #expect(card.missions.isEmpty)
        #expect(card.fallbackNotice == "Finland has no mission listed in Spain. Nearest known Nordic missions help citizens of other Nordic countries when theirs isn't represented.")
        let row = try #require(card.fallbackMissions.first)
        #expect(row.locationText == "Sweden · Madrid")
        #expect(row.reasonCaption == nil)
        #expect(card.badge.title == "Nordic help")
        #expect(card.summary == "+358 9 1605 5555")
    }

    @Test
    func euCitizenGetsTheEUConsularProtectionNotice() {
        let card = presentation(["FR"], host: "AU", coordinate: nil)

        #expect(card.fallbackNotice == "France has no mission listed in Australia. Nearest known EU missions can help under EU consular protection.")
        #expect(card.fallbackMissions.map(\.id) == ["DE-AU"])
        #expect(card.badge.title == "EU help")
        #expect(card.summary == "+33 1 53 59 11 00")
    }

    @Test
    func aFallbackRowWithADifferentArrangementThanTheNoticeSaysSo() {
        // Finland has no mission in Morocco in this dataset variant: Sweden (Nordic) and Germany (EU) can help.
        let index = DiplomaticMissionIndex(missions: [
            Self.mission("SE-RAB", sending: "SE"),
            Self.mission("DE-RAB", sending: "DE", kind: .consulateGeneral)
        ])
        let card = EmbassyCardPresentation(citizenships: ["FI"], hostCountry: "MA", coordinate: nil, index: index, locale: Self.locale)

        #expect(card.fallbackNotice?.contains("Nordic") == true)
        let captions = Dictionary(uniqueKeysWithValues: card.fallbackMissions.map { ($0.id, $0.reasonCaption) })
        #expect(captions["SE-RAB"] == .some(nil))
        #expect(captions["DE-RAB"] == "Under EU consular protection")
    }

    @Test
    func noMissionAtAllSaysSoAndPointsToTheOfficialDirectory() {
        let card = presentation(["FI"], host: "ZZ", coordinate: nil)

        #expect(card.missions.isEmpty)
        #expect(card.fallbackMissions.isEmpty)
        #expect(card.noMissionMessage == "Finland has no mission listed in ZZ, and no EU or Nordic alternative is known. Check the official missions directory.")
        #expect(card.badge.title == "Not listed")
        #expect(card.summary == "+358 9 1605 5555")
    }

    @Test
    func nonEUCitizenWithoutAMissionGetsNoFallback() {
        let card = presentation(["US"], host: "AU", coordinate: nil)

        #expect(card.fallbackNotice == nil)
        #expect(card.fallbackMissions.isEmpty)
        #expect(card.noMissionMessage != nil)
    }

    // MARK: States

    @Test
    func atHomeShowsOneLineAndKeepsTheHotline() {
        let card = presentation(["FI"], host: "FI")

        #expect(card.state == .atHome)
        #expect(card.atHomeMessage == "You're home in Finland — embassy details appear when you travel")
        #expect(card.hotlines.count == 1)
        #expect(card.missions.isEmpty)
        #expect(card.links.isEmpty)
        #expect(card.footer == nil)
        #expect(card.badge.title == "Home")
        #expect(card.summary == "Home in Finland")
    }

    @Test
    func unknownHostCountryAsksForLocationAndKeepsTheHotlineAndLinks() {
        for host in [nil, "", "  "] as [String?] {
            let card = presentation(["FI"], host: host)

            #expect(card.state == .locationNeeded)
            #expect(card.badge.title == "Location Needed")
            #expect(card.hotlines.count == 1)
            #expect(card.links.count == 1)
            #expect(card.summary == "+358 9 1605 5555")
        }

        #expect(EmbassyCardPresentation.locationNeededTitle == "Location needed to find your embassy")
    }

    @Test
    func withoutCitizenshipTheCardIsOff() {
        let card = presentation([], host: "MA")

        #expect(card.state == .off)
        #expect(card.badge.title == "Off")
        #expect(card.summary == "Off")
        #expect(card.hotlines.isEmpty)
        #expect(card.missions.isEmpty)
    }

    @Test
    func hostCodeCaseAndWhitespaceDoNotMatter() {
        #expect(presentation(["fi"], host: " ma ").missions.isEmpty == false)
        #expect(presentation(["FI"], host: "fi").state == .atHome)
    }

    // MARK: Summary

    @Test
    func collapsedSummaryLeadsWithTheConsularLine() {
        let card = presentation(["FI"], host: "MA", coordinate: (34.020, -6.841))

        #expect(card.summary == "+358 9 1605 5555")
        #expect(card.summaryHelp == "Embassy of Finland in Rabat · 3.3 km · +358 9 1605 5555")
    }

    @Test
    func collapsedSummaryFallsBackToTheCityAndDistanceWithoutAConsularLine() {
        let index = DiplomaticMissionIndex(missions: [Self.mission("BR-RAB", sending: "BR", city: "Rabat")])
        let card = EmbassyCardPresentation(citizenships: ["BR"], hostCountry: "MA", coordinate: Self.rabat, index: index, locale: Self.locale)

        #expect(card.hotlines.isEmpty)
        #expect(card.summary == "Rabat ~1 km")
    }

    @Test
    func collapsedSummaryDoesNotRepeatTheBadge() {
        let nordic = presentation(["FI"], host: "ES", coordinate: nil)

        #expect(nordic.badge.title == "Nordic help")
        #expect(nordic.summary.contains("Nordic") == false)
        #expect(nordic.summaryHelp.contains("Nearest known Nordic missions"))
    }

    @Test
    func summaryForAnApproximateMissionKeepsTheTildeDistanceInTheHelp() {
        let card = presentation(["SE"], host: "MA", coordinate: (34.020, -6.841))

        #expect(card.summary == "+46 8 405 50 05")
        #expect(card.summaryHelp.contains("~1 km"))
    }

    // MARK: Links and footer

    @Test
    func linksCarryTheRegistrationServiceAndTheMissionsDirectory() throws {
        let group = try #require(presentation(["FI"], host: "MA").links.first)

        #expect(group.registration?.title == "Travel notification")
        #expect(group.registration?.url == URL(string: "https://matkustusilmoitus.fi/"))
        #expect(group.missionsDirectory?.title == "All missions")
        #expect(group.missionsDirectory?.url == URL(string: "https://finlandabroad.fi/frontpage"))
    }

    @Test
    func countriesWithoutARegistrationServiceStillLinkTheDirectory() throws {
        let group = try #require(presentation(["BG"], host: "MA").links.first)

        #expect(group.registration == nil)
        #expect(group.missionsDirectory != nil)
    }

    @Test
    func footerNamesTheSourceTheDatasetDateAndTheOfficialSiteAdvice() {
        let card = presentation(["FI"], host: "MA")

        #expect(card.footer == "Locations: Wikidata (CC0) · updated Oct 5, 2026 · Check details on the official site before you go")
    }

    @Test
    func footerFallsBackToRawDateAndOmitsMissingOnes() {
        #expect(EmbassyCardPresentation.formattedDate("soon", locale: Self.locale) == "soon")

        let undated = DiplomaticMissionIndex(missions: [Self.mission("FI-RAB", sending: "FI")])
        let card = EmbassyCardPresentation(citizenships: ["FI"], hostCountry: "MA", coordinate: nil, index: undated, locale: Self.locale)
        #expect(card.footer == "Locations: Wikidata (CC0) · Check details on the official site before you go")
    }

    // MARK: Maps

    @Test
    func aPreciseLocationIsPinnedWithItsNameAsLabel() throws {
        let precise = Self.mission("X", sending: "FI", name: "Embassy of Finland", latitude: 34.05, longitude: -6.84, approximate: false)
        let url = try #require(EmbassyMapsLink.url(for: precise))
        let items = queryItems(url)

        #expect(url.scheme == "https")
        #expect(url.host == "maps.apple.com")
        #expect(items["q"] == "Embassy of Finland")
        #expect(items["ll"] == "34.050000,-6.840000")
        #expect(items["sll"] == nil)
    }

    @Test
    func anApproximateLocationIsSearchedByNameAndCityInsteadOfPinned() throws {
        let approximate = Self.mission("X", sending: "FI", name: "Embassy of Finland", city: "Rabat", approximate: true)
        let url = try #require(EmbassyMapsLink.url(for: approximate))
        let items = queryItems(url)

        #expect(items["q"] == "Embassy of Finland, Rabat")
        #expect(items["ll"] == nil)
        #expect(items["sll"] == "34.020000,-6.840000")
    }

    @Test
    func mapsQueryEscapesCharactersThatWouldSplitIt() throws {
        let tricky = Self.mission("X", sending: "BA", name: "Embassy of Bosnia & Herzegovina #1 (a=b+c)", city: "Rabat; MA", approximate: true)
        let url = try #require(EmbassyMapsLink.url(for: tricky))
        let raw = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)

        #expect(raw.contains("&Herzegovina") == false)
        #expect(raw.split(separator: "&").count == 2)
        #expect(queryItems(url)["q"] == "Embassy of Bosnia & Herzegovina #1 (a=b+c), Rabat; MA")
    }

    @Test
    func invalidCoordinatesFallBackToANameOnlySearch() throws {
        let broken = Self.mission("X", sending: "FI", name: "Embassy of Finland", latitude: 999, longitude: 0, approximate: false)
        let items = queryItems(try #require(EmbassyMapsLink.url(for: broken)))

        #expect(items["q"] == "Embassy of Finland")
        #expect(items["ll"] == nil)
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}

struct EmbassyIntegrationTests {
    private func snapshot(countryCode: String?, latitude: Double? = nil, longitude: Double? = nil) -> DashboardSnapshot {
        let base = DashboardSnapshot.preview
        let device = countryCode.map {
            IPLocationSnapshot(
                city: nil, region: nil, country: nil, countryCode: $0, latitude: latitude, longitude: longitude,
                timeZone: nil, provider: "test", fetchedAt: .now
            )
        }
        return DashboardSnapshot(
            network: base.network,
            power: base.power,
            travelContext: TravelContextSnapshot(
                wifi: nil, vpn: nil, timeZoneIdentifier: "UTC", deviceLocation: device, publicIP: nil, location: nil
            ),
            weather: nil,
            emergencyCare: nil,
            appState: base.appState
        )
    }

    @Test
    func cardUsesTheSnapshotCountryAndDeviceCoordinate() {
        let settings = AppSettings(citizenshipCountryCodes: ["FI"])
        let card = EmbassyCardPresentation(
            settings: settings,
            snapshot: snapshot(countryCode: "ES", latitude: 40.4, longitude: -3.7),
            locale: Locale(identifier: "en_US")
        )

        #expect(card.state == .abroad)
        #expect(card.subtitle == "Finland in Spain")
    }

    @Test
    func cardWithoutAnyCountryAsksForLocation() {
        let card = EmbassyCardPresentation(
            settings: AppSettings(citizenshipCountryCodes: ["FI"]),
            snapshot: snapshot(countryCode: nil),
            locale: Locale(identifier: "en_US")
        )

        #expect(card.state == .locationNeeded)
    }

    @Test
    func collapsedSummaryComesFromTheEmbassyPresentation() {
        let settings = AppSettings(citizenshipCountryCodes: ["FI"])
        let summary = DashboardCardSummaryPresentation(
            cardID: .embassy,
            snapshot: snapshot(countryCode: "FI"),
            settings: settings,
            travelAlertPreferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: false, securityEnabled: false),
            timeTracking: .disabled
        )
        let off = DashboardCardSummaryPresentation(
            cardID: .embassy,
            snapshot: snapshot(countryCode: "FI"),
            settings: AppSettings(),
            travelAlertPreferences: TravelAlertPreferences(advisoryEnabled: true, weatherEnabled: false, securityEnabled: false),
            timeTracking: .disabled
        )

        #expect(summary.text.hasPrefix("Home in "))
        #expect(off.text == "Off")
    }

    @Test
    func displayTitleIsYourEmbassy() {
        #expect(DashboardCardID.embassy.displayTitle == "Your Embassy")
    }

    @Test
    func offlineEssentialsListTheHotlineAndTheNearestOwnMission() throws {
        let settings = AppSettings(citizenshipCountryCodes: ["FI"])
        let essentials = try #require(
            OfflineEssentialsPresentation.embassy(settings: settings, snapshot: snapshot(countryCode: "ES", latitude: 40.4, longitude: -3.7))
        )

        #expect(essentials.hotlines == [EmbassyEssentials.Hotline(title: "Ministry for Foreign Affairs", phone: "+358 9 1605 5555")])
        #expect(essentials.nearestMission?.isEmpty == false)
    }

    @Test
    func offlineEssentialsHaveNoEmbassyWithoutCitizenship() {
        #expect(OfflineEssentialsPresentation.embassy(settings: AppSettings(), snapshot: snapshot(countryCode: "ES")) == nil)
    }

    @Test
    func offlineEssentialsKeepTheHotlineWhenHome() throws {
        let essentials = try #require(
            OfflineEssentialsPresentation.embassy(settings: AppSettings(citizenshipCountryCodes: ["FI"]), snapshot: snapshot(countryCode: "FI"))
        )

        #expect(essentials.nearestMission == nil)
        #expect(essentials.hotlines.count == 1)
    }
}

struct CitizenshipSettingsPresentationTests {
    private let locale = Locale(identifier: "en_US")

    @Test
    func countryListJoinsNamesNaturally() {
        #expect(CitizenshipSettingsPresentation.countryList(["FI"], locale: locale) == "Finland")
        #expect(CitizenshipSettingsPresentation.countryList(["FI", "SE"], locale: locale) == "Finland and Sweden")
        #expect(CitizenshipSettingsPresentation.countryList(["FI", "SE", "NO"], locale: locale) == "Finland, Sweden, and Norway")
    }

    @Test
    func pickerListsTwoLetterCountriesSortedByLocalizedName() {
        let countries = CitizenshipSettingsPresentation.allCountries(locale: locale)

        #expect(countries.count > 200)
        #expect(countries.allSatisfy { $0.code.count == 2 && $0.code == $0.code.uppercased() })
        #expect(countries.contains(CitizenshipCountry(code: "FI", name: "Finland")))
        #expect(Set(countries.map(\.code)).count == countries.count)
        #expect(countries.map(\.name) == countries.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test
    func searchMatchesNamesAndCodesIgnoringCaseAndDiacritics() {
        let all = [
            CitizenshipCountry(code: "FI", name: "Finland"),
            CitizenshipCountry(code: "CW", name: "Curaçao"),
            CitizenshipCountry(code: "SE", name: "Sweden")
        ]

        #expect(CitizenshipSettingsPresentation.countries(all, matching: "fin", excluding: []).map(\.code) == ["FI"])
        #expect(CitizenshipSettingsPresentation.countries(all, matching: "curacao", excluding: []).map(\.code) == ["CW"])
        #expect(CitizenshipSettingsPresentation.countries(all, matching: "se", excluding: []).map(\.code) == ["SE"])
        #expect(CitizenshipSettingsPresentation.countries(all, matching: "  ", excluding: []).count == 3)
        #expect(CitizenshipSettingsPresentation.countries(all, matching: "", excluding: ["FI"]).map(\.code) == ["CW", "SE"])
        #expect(CitizenshipSettingsPresentation.countries(all, matching: "nowhere", excluding: []).isEmpty)
    }

    @Test
    func theListIsCappedAtThree() {
        #expect(CitizenshipSettingsPresentation.canAddCountry(to: []))
        #expect(CitizenshipSettingsPresentation.canAddCountry(to: ["FI", "SE"]))
        #expect(CitizenshipSettingsPresentation.canAddCountry(to: ["FI", "SE", "NO"]) == false)
    }

    @Test
    func embassyStatusSaysWhetherTheConsularLineIsBundled() {
        #expect(CitizenshipSettingsPresentation.embassyStatus(forCitizenships: [], locale: locale) == "No citizenship chosen. The Your Embassy card is off.")
        #expect(CitizenshipSettingsPresentation.embassyStatus(forCitizenships: ["FI"], locale: locale) == "Finland · verified consular emergency line included")
        #expect(CitizenshipSettingsPresentation.embassyStatus(forCitizenships: ["BR"], locale: locale) == "Brazil · no verified consular line yet, embassy locations still work")
        #expect(CitizenshipSettingsPresentation.embassyStatus(forCitizenships: ["FI", "BR"], locale: locale) == "Finland and Brazil · verified consular line for Finland")
    }

    @Test
    func footersNameTheLocalOnlyPromiseAndTheSources() {
        #expect(CitizenshipSettingsPresentation.sectionFooter == "Stays on this Mac. Used only to find your embassy and your foreign ministry's emergency line.")
        #expect(CitizenshipSettingsPresentation.embassySectionFooter.contains("Wikidata (CC0)"))
        #expect(CitizenshipSettingsPresentation.embassySectionFooter.contains("not a legal guarantee"))
    }
}
