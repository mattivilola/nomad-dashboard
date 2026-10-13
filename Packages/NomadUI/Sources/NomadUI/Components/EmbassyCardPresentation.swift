import Foundation
import NomadCore

/// Everything the "Your Embassy" card shows, decided from the user's citizenships, the country they
/// are in and (optionally) their device coordinate.
///
/// Citizenship is sensitive: it is only compared with the bundled offline dataset here and never
/// leaves the Mac. The dataset is incomplete, so the wording says "listed" and "nearest known".
struct EmbassyCardPresentation {
    enum State: Equatable {
        /// No citizenship chosen, so the card is switched off.
        case off
        /// The user is in the country they hold citizenship of.
        case atHome
        /// The country they are in is not known yet.
        case locationNeeded
        /// Abroad: show missions, or the fallback.
        case abroad
    }

    /// The foreign ministry's consular emergency line for one citizenship.
    struct Hotline: Identifiable, Equatable {
        /// Citizenship code.
        let id: String
        /// Short ministry name, prefixed with the country when the user has several citizenships.
        let title: String
        /// "24/7 consular line · Crisis and Support Centre", worded from the ministry's own note.
        let detail: String
        let phone: String
        /// Hover and VoiceOver text with the ministry's full name and note.
        let help: String
    }

    struct MissionRow: Identifiable, Equatable {
        let id: String
        let name: String
        let kindTitle: String
        /// "Rabat", or "Sweden · Rabat" for a mission of another state.
        let locationText: String
        /// "~4 km" for a city-centre coordinate, "4.2 km" for a precise one, nil without a device position.
        let distanceText: String?
        /// Only set on a fallback row whose arrangement differs from the one in the card's notice.
        let reasonCaption: String?
        let mapsURL: URL?
        let websiteURL: URL?
        let address: String?

        var accessibilityLabel: String {
            [name, kindTitle, locationText, distanceText].compactMap(\.self).filter { $0.isEmpty == false }.joined(separator: ", ")
        }
    }

    struct Link: Equatable {
        let title: String
        let url: URL
    }

    /// The official links of one citizenship.
    struct LinkGroup: Identifiable, Equatable {
        /// Citizenship code.
        let id: String
        let countryName: String
        let registration: Link?
        let missionsDirectory: Link?
    }

    static let allMissionsTitle = "All missions"
    static let atHomeSuffix = "embassy details appear when you travel"
    static let locationNeededTitle = "Location needed to find your embassy"
    static let locationNeededMessage = "Allow location or turn on the public IP lookup so the card knows which country you are in."
    static let offTitle = "Your Embassy Off"
    static let offMessage = "Add your citizenship in Settings to find your embassy and your foreign ministry's emergency line."
    static let unverifiedFooter = "Check details on the official site before you go"

    let state: State
    let subtitle: String
    let badge: PillBadge
    let hotlines: [Hotline]
    /// Missions of the user's own state(s), nearest first, at most three.
    let missions: [MissionRow]
    /// Why `fallbackMissions` are shown, nil when there are none.
    let fallbackNotice: String?
    let fallbackMissions: [MissionRow]
    /// Shown when the dataset lists neither an own mission nor a fallback.
    let noMissionMessage: String?
    /// One line replacing the missions while the user is home.
    let atHomeMessage: String?
    let links: [LinkGroup]
    let footer: String?
    /// One line for the collapsed card.
    let summary: String
    let summaryHelp: String

    init(
        citizenships: [String],
        hostCountry: String?,
        coordinate: (latitude: Double, longitude: Double)?,
        index: DiplomaticMissionIndex = .bundled,
        locale: Locale = .current
    ) {
        let codes = AppSettings.sanitizedCitizenshipCodes(citizenships)
        let host = hostCountry?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let names = { (codes: [String]) in CitizenshipSettingsPresentation.countryList(codes, locale: locale) }

        guard codes.isEmpty == false else {
            state = .off
            subtitle = "Find your embassy and consular line abroad"
            badge = PillBadge(title: "Off", symbolName: "building.columns", tint: NomadTheme.primaryText)
            hotlines = []
            missions = []
            fallbackNotice = nil
            fallbackMissions = []
            noMissionMessage = nil
            atHomeMessage = nil
            links = []
            footer = nil
            summary = "Off"
            summaryHelp = "Off"
            return
        }

        let hotlines = Self.hotlines(for: codes, locale: locale)
        self.hotlines = hotlines
        let hostName = CountryNames.displayName(forCode: host, locale: locale)

        if host.isEmpty {
            state = .locationNeeded
            subtitle = names(codes)
            badge = PillBadge(title: "Location Needed", symbolName: "location.slash.fill", tint: NomadTheme.sand)
            missions = []
            fallbackNotice = nil
            fallbackMissions = []
            noMissionMessage = nil
            atHomeMessage = nil
            links = Self.links(for: codes, locale: locale)
            footer = nil
            summary = hotlines.first?.phone ?? "Location needed"
            summaryHelp = [Self.locationNeededTitle, hotlines.first?.phone].compactMap(\.self).joined(separator: " · ")
            return
        }

        if codes.allSatisfy({ $0 == host }) {
            state = .atHome
            subtitle = names(codes)
            badge = PillBadge(title: "Home", symbolName: "house", tint: NomadTheme.primaryText)
            missions = []
            fallbackNotice = nil
            fallbackMissions = []
            noMissionMessage = nil
            atHomeMessage = "You're home in \(hostName) — \(Self.atHomeSuffix)"
            links = []
            footer = nil
            summary = "Home in \(hostName)"
            summaryHelp = summary
            return
        }

        state = .abroad
        let abroad = codes.filter { $0 != host }
        subtitle = "\(names(abroad)) in \(hostName)"
        links = Self.links(for: abroad, locale: locale)
        atHomeMessage = nil

        let lookup = EmbassyLookup(citizenships: codes, hostCountry: host, coordinate: coordinate, index: index)
        let noticeReason = lookup.fallbackReason
        missions = lookup.ownMatches.map { Self.row(for: $0, lookup: nil, noticeReason: nil, locale: locale) }
        fallbackMissions = lookup.fallbackMatches.map {
            Self.row(for: $0, lookup: lookup, noticeReason: noticeReason, locale: locale)
        }
        fallbackNotice = noticeReason.map { Self.fallbackNotice($0, citizenships: abroad, host: hostName, locale: locale) }
        noMissionMessage = lookup.isEmpty
            ? "\(Self.noMissionSentence(citizenships: abroad, host: hostName, locale: locale)), and no EU or Nordic alternative is known. Check the official missions directory."
            : nil
        footer = Self.footer(for: index, locale: locale)

        let phone = (lookup.ownMatches.first.flatMap { match in hotlines.first { $0.id == match.mission.sendingCountry } }
            ?? hotlines.first)?.phone

        // The collapsed line is only about 22 characters wide and never repeats the badge. The consular
        // line is what a traveller in trouble needs first, so it leads and is never cut off.
        if let nearest = lookup.ownMatches.first {
            badge = PillBadge(title: "Listed", symbolName: "building.columns", tint: NomadTheme.primaryText)
            let place = [nearest.mission.city ?? nearest.mission.name, missions.first?.distanceText]
                .compactMap(\.self)
                .joined(separator: " ")
            summary = phone ?? place
            summaryHelp = [nearest.mission.name, missions.first?.distanceText, phone]
                .compactMap(\.self)
                .joined(separator: " · ")
        } else if let noticeReason {
            badge = PillBadge(title: "\(Self.helpLabel(noticeReason)) help", symbolName: "building.columns", tint: NomadTheme.primaryText)
            summary = phone ?? "Not listed here"
            summaryHelp = [fallbackNotice, phone].compactMap(\.self).joined(separator: " ")
        } else {
            badge = PillBadge(title: "Not listed", symbolName: "mappin.slash", tint: NomadTheme.primaryText)
            summary = phone ?? "Not listed here"
            summaryHelp = ["Not listed here", phone].compactMap(\.self).joined(separator: " · ")
        }
    }

    init(settings: AppSettings, snapshot: DashboardSnapshot, index: DiplomaticMissionIndex = .bundled, locale: Locale = .current) {
        let device = snapshot.travelContext.deviceLocation
        let coordinate: (latitude: Double, longitude: Double)? = if let latitude = device?.latitude, let longitude = device?.longitude {
            (latitude, longitude)
        } else {
            nil
        }

        self.init(
            citizenships: settings.citizenshipCountryCodes,
            hostCountry: snapshot.currentCountryCode,
            coordinate: coordinate,
            index: index,
            locale: locale
        )
    }

    // MARK: - Hotlines

    static func hotlines(for codes: [String], locale: Locale) -> [Hotline] {
        codes.compactMap { code in
            guard let contacts = ConsularContactsDirectory.contacts(forCitizenship: code) else {
                return nil
            }

            let shortName = shortMinistryName(contacts.ministryName)
            let countryName = CountryNames.displayName(forCode: code, locale: locale)
            let note = contacts.emergencyPhoneNote
            return Hotline(
                id: code,
                title: codes.count > 1 ? "\(countryName) · \(shortName)" : shortName,
                detail: lineDescription(note: note),
                phone: contacts.emergencyPhone,
                help: [contacts.ministryName, note].compactMap(\.self).joined(separator: " · ")
            )
        }
    }

    /// Words the ministry's own note: "24/7 consular line" only where the note itself says 24/7,
    /// otherwise the note's wording ("Emergency line · outside office hours").
    static func lineDescription(note: String?) -> String {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), note.isEmpty == false else {
            return "Consular emergency line"
        }

        let allDay = "24/7"
        guard note.hasPrefix(allDay) else {
            return note
        }

        let rest = note.dropFirst(allDay.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
        return rest.isEmpty ? "24/7 consular line" : "24/7 consular line · \(rest)"
    }

    /// "Ministry for Foreign Affairs of Finland" becomes "Ministry for Foreign Affairs". The country is
    /// only dropped when what remains is a complete ministry name; "U.S. Department of State" stays whole.
    static func shortMinistryName(_ name: String) -> String {
        guard let range = name.range(of: " of ", options: .backwards) else {
            return name
        }

        let head = String(name[..<range.lowerBound])
        let completeEndings = ["Affairs", "Office", "Trade", "Cooperation", "Relations"]
        guard completeEndings.contains(where: { head.hasSuffix($0) }) else {
            return name
        }

        return head
    }

    // MARK: - Missions

    private static func row(
        for match: DiplomaticMissionMatch,
        lookup: EmbassyLookup?,
        noticeReason: EmbassyLookup.FallbackReason?,
        locale: Locale
    ) -> MissionRow {
        let reason = lookup?.fallbackReason(for: match.mission)
        return row(
            for: match,
            isFallback: lookup != nil,
            reasonCaption: reason.flatMap { $0 == noticeReason ? nil : reasonCaption($0) },
            locale: locale
        )
    }

    /// One mission row. A fallback mission names the state that runs it, since it is not the user's own.
    static func row(
        for match: DiplomaticMissionMatch,
        isFallback: Bool,
        reasonCaption: String?,
        locale: Locale
    ) -> MissionRow {
        let mission = match.mission
        let place = mission.city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let locationText = if isFallback {
            [CountryNames.displayName(forCode: mission.sendingCountry, locale: locale), place]
                .compactMap(\.self)
                .joined(separator: " · ")
        } else {
            place ?? ""
        }

        return MissionRow(
            id: mission.id,
            name: mission.name,
            kindTitle: mission.kind.title,
            locationText: locationText,
            distanceText: distanceText(kilometers: match.distanceKilometers, isApproximate: mission.isApproximateLocation),
            reasonCaption: reasonCaption,
            mapsURL: EmbassyMapsLink.url(for: mission),
            websiteURL: mission.websiteURL,
            address: mission.address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    /// "~4 km" when the mission's coordinate is only the city centre, "4.2 km" when it is precise.
    static func distanceText(kilometers: Double?, isApproximate: Bool) -> String? {
        guard let kilometers, kilometers.isFinite, kilometers >= 0 else {
            return nil
        }

        if isApproximate {
            return "~\(max(1, Int(kilometers.rounded()))) km"
        }

        return NomadFormatters.kilometers(kilometers)
    }

    // MARK: - Fallback wording

    static func noMissionSentence(citizenships: [String], host: String, locale: Locale) -> String {
        let verb = citizenships.count == 1 ? "has" : "have"
        return "\(CitizenshipSettingsPresentation.countryList(citizenships, locale: locale)) \(verb) no mission listed in \(host)"
    }

    static func fallbackNotice(
        _ reason: EmbassyLookup.FallbackReason,
        citizenships: [String],
        host: String,
        locale: Locale
    ) -> String {
        let lead = noMissionSentence(citizenships: citizenships, host: host, locale: locale)
        switch reason {
        case .euConsularProtection:
            return "\(lead). Nearest known EU missions can help under EU consular protection."
        case .nordicCooperation:
            return "\(lead). Nearest known Nordic missions help citizens of other Nordic countries when theirs isn't represented."
        }
    }

    private static func helpLabel(_ reason: EmbassyLookup.FallbackReason) -> String {
        switch reason {
        case .euConsularProtection: "EU"
        case .nordicCooperation: "Nordic"
        }
    }

    private static func reasonCaption(_ reason: EmbassyLookup.FallbackReason) -> String {
        switch reason {
        case .euConsularProtection: "Under EU consular protection"
        case .nordicCooperation: "Under Nordic cooperation"
        }
    }

    // MARK: - Links and footer

    static func links(for codes: [String], locale: Locale) -> [LinkGroup] {
        codes.compactMap { code in
            guard let contacts = ConsularContactsDirectory.contacts(forCitizenship: code) else {
                return nil
            }

            let registration = contacts.travelRegistrationURL.flatMap { url in
                contacts.travelRegistrationName.map { Link(title: $0, url: url) }
            }
            let directory = contacts.missionsDirectoryURL.map { Link(title: allMissionsTitle, url: $0) }
            guard registration != nil || directory != nil else {
                return nil
            }

            return LinkGroup(
                id: code,
                countryName: CountryNames.displayName(forCode: code, locale: locale),
                registration: registration,
                missionsDirectory: directory
            )
        }
    }

    /// "Locations: Wikidata (CC0) · updated 5 Oct 2026 · Check details on the official site before you go".
    static func footer(for index: DiplomaticMissionIndex, locale: Locale) -> String {
        var parts = ["Locations: \(index.source ?? DiplomaticMissionDataset.wikidataSource)"]
        if let generatedAt = index.generatedAt, generatedAt.isEmpty == false {
            parts.append("updated \(formattedDate(generatedAt, locale: locale))")
        }
        parts.append(unverifiedFooter)
        return parts.joined(separator: " · ")
    }

    /// The dataset's `yyyy-MM-dd` date in the user's format, or the raw text when it does not parse.
    static func formattedDate(_ isoDate: String, locale: Locale) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: isoDate) else {
            return isoDate
        }

        let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: utc))
    }
}

/// Apple Maps links for a mission.
enum EmbassyMapsLink {
    /// A precise coordinate is pinned (`q` labels the pin, `ll` places it). A city-centre coordinate
    /// would drop the pin in the wrong street, so those missions are searched by name and city instead,
    /// with `sll` only steering the search towards the right area.
    ///
    /// The query is percent-encoded by hand because `URLQueryItem` leaves `&`, `+` and `;` alone, which
    /// would split a mission name such as "Embassy of Bosnia & Herzegovina" into two parameters.
    static func url(for mission: DiplomaticMission) -> URL? {
        let hasValidCoordinate = (-90.0...90.0).contains(mission.latitude)
            && (-180.0...180.0).contains(mission.longitude)
            && mission.latitude.isFinite && mission.longitude.isFinite
        let coordinate = String(format: "%.6f,%.6f", mission.latitude, mission.longitude)

        var items: [(String, String)]
        if mission.isApproximateLocation {
            let place = mission.city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            items = [("q", [mission.name, place].compactMap(\.self).joined(separator: ", "))]
            if hasValidCoordinate {
                items.append(("sll", coordinate))
            }
        } else {
            items = [("q", mission.name)]
            if hasValidCoordinate {
                items.append(("ll", coordinate))
            }
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.percentEncodedQuery = items
            .map { "\($0.0)=\(encode($0.1))" }
            .joined(separator: "&")
        return components.url
    }

    /// Unreserved characters stay, everything else is escaped; the comma of a coordinate pair stays literal.
    private static func encode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~,"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
