import Foundation

// A departure checklist for a planned trip. The suggested items are derived from the trip preview (and, when
// it is available, the online part of it), so they always match the current data; only what the traveller
// did with them is stored (`TripChecklistState`, part of `PlannedTrip`). Everything here is computed on the
// Mac and sends nothing anywhere.

// MARK: - Items

/// Where a suggested item belongs in the list. The case order is the display order.
public enum TripChecklistGroup: String, CaseIterable, Codable, Sendable {
    case beforeYouGo
    case moneyAndPower
    case documents
    case onArrival

    public var title: String {
        switch self {
        case .beforeYouGo: "Before you go"
        case .moneyAndPower: "Money & power"
        case .documents: "Documents"
        case .onArrival: "On arrival"
        }
    }
}

/// What a suggested item is about. The case order is the order within a group.
public enum TripChecklistKind: String, CaseIterable, Codable, Sendable {
    case advisory
    case roaming
    case driving
    case consularLine
    case emergencyNumbers
    case adapter
    case cash
    case registerTrip
    case visaSchengen
    case visaAllowance
    case rhythm
    case holiday
}

public struct TripChecklistItem: Equatable, Sendable, Identifiable {
    /// Stable across refreshes and launches: the kind plus its parameter, for example `"adapter.C-E"` or
    /// `"cash.MAD"`. The checked state is stored by this id.
    public let id: String
    public let kind: TripChecklistKind
    public let title: String
    public let detail: String?
    /// An official page to open for the item, when there is one.
    public let link: URL?
    /// The suggested place in the list; the UI may group differently.
    public let group: TripChecklistGroup

    public init(
        id: String,
        kind: TripChecklistKind,
        title: String,
        detail: String? = nil,
        link: URL? = nil,
        group: TripChecklistGroup
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.link = link
        self.group = group
    }
}

// MARK: - Stored state

/// An item the traveller added to a trip's checklist.
public struct TripChecklistCustomItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The longest title that is kept.
    public static let maximumTitleLength = 120

    public let id: UUID
    public var title: String
    public var isChecked: Bool

    public init(id: UUID = UUID(), title: String, isChecked: Bool = false) {
        self.id = id
        self.title = title
        self.isChecked = isChecked
    }
}

/// What the traveller did with a trip's checklist. Part of `PlannedTrip`, so it is stored and sanitized with
/// the trip. Decoding is lenient: a missing or malformed field is empty.
public struct TripChecklistState: Codable, Equatable, Hashable, Sendable {
    /// The most checked ids that are kept.
    public static let maximumCheckedItemIDs = 100
    /// The most custom items that are kept.
    public static let maximumCustomItems = 30

    /// Ids of suggested items marked done. An id whose item no longer applies stays harmlessly (the item may
    /// come back when the data changes) until the cap is reached.
    public var checkedItemIDs: Set<String>
    public var customItems: [TripChecklistCustomItem]

    public init(checkedItemIDs: Set<String> = [], customItems: [TripChecklistCustomItem] = []) {
        self.checkedItemIDs = checkedItemIDs
        self.customItems = customItems
    }

    private enum CodingKeys: String, CodingKey {
        case checkedItemIDs
        case customItems
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkedItemIDs = (try? container.decodeIfPresent(Set<String>.self, forKey: .checkedItemIDs)) ?? []
        customItems = (try? container.decodeIfPresent([LossyDecodable<TripChecklistCustomItem>].self, forKey: .customItems))?
            .compactMap(\.value) ?? []
    }

    public var isEmpty: Bool {
        checkedItemIDs.isEmpty && customItems.isEmpty
    }

    public func isChecked(itemID: String) -> Bool {
        checkedItemIDs.contains(itemID)
    }

    /// Marks the suggested item with `itemID` done or open.
    public mutating func setChecked(_ checked: Bool, itemID: String) {
        if checked {
            checkedItemIDs.insert(itemID)
        } else {
            checkedItemIDs.remove(itemID)
        }
    }

    /// Adds an item of the traveller's own. Nil, and nothing added, when the title is empty or the list is
    /// full.
    @discardableResult
    public mutating func addCustomItem(title: String) -> TripChecklistCustomItem? {
        guard customItems.count < Self.maximumCustomItems,
              let cleaned = Self.cleanedTitle(title)
        else {
            return nil
        }
        let item = TripChecklistCustomItem(title: cleaned)
        customItems.append(item)
        return item
    }

    /// The state ready to store: custom items with a trimmed title (at most
    /// `TripChecklistCustomItem.maximumTitleLength` characters) and a unique id, empty titles dropped, at most
    /// `maximumCustomItems` of the first kept; empty ids dropped and at most `maximumCheckedItemIDs` ids kept
    /// (the alphabetically first, so which ones stay does not depend on set order).
    func sanitized() -> TripChecklistState {
        var seenIDs = Set<UUID>()
        let items = customItems
            .compactMap { item -> TripChecklistCustomItem? in
                guard let title = Self.cleanedTitle(item.title), seenIDs.insert(item.id).inserted else {
                    return nil
                }
                return TripChecklistCustomItem(id: item.id, title: title, isChecked: item.isChecked)
            }
            .prefix(Self.maximumCustomItems)
        let ids = checkedItemIDs
            .filter { $0.isEmpty == false }
            .sorted()
            .prefix(Self.maximumCheckedItemIDs)
        return TripChecklistState(checkedItemIDs: Set(ids), customItems: Array(items))
    }

    private static func cleanedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        return String(trimmed.prefix(TripChecklistCustomItem.maximumTitleLength))
    }
}

// MARK: - Generation

public enum TripChecklist {
    /// The most public holidays listed; a long trip would otherwise bury the rest of the list.
    public static let maximumHolidayItems = 5

    /// The suggested items for a trip, in display order (by group, then by kind). Only what applies is
    /// listed, and missing data omits an item instead of guessing.
    ///
    /// - Parameters:
    ///   - preview: The offline preview of the trip (`TripPreview.make`).
    ///   - online: Public holidays and the travel advisory, when they have been loaded. Without them those
    ///     two kinds are simply absent.
    ///   - settings: The home country (`effectiveHomeCountryCode`) the destination is compared with, in
    ///     addition to the country the traveller is in now, which the preview already flags.
    ///   - calendar: Reads the dates written into titles and counts the days of the trip.
    ///   - locale: Used for the date format.
    public static func items(
        for preview: TripPreview,
        online: TripPreviewOnline?,
        settings: AppSettings,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> [TripChecklistItem] {
        let home = settings.effectiveHomeCountryCode
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)

        var items: [TripChecklistItem] = []
        items += advisoryItems(online?.advisory)
        items += roamingItems(preview: preview, home: home)
        items += drivingItems(preview: preview, home: home)
        items += consularItems(preview.embassy)
        items += emergencyItems(preview.emergency)
        items += adapterItems(preview: preview, home: home)
        items += cashItems(preview: preview, home: home)
        items += registrationItems(preview.embassy)
        items += visaItems(preview.visa, dayStyle: dayStyle)
        items += rhythmItems(preview: preview, calendar: calendar)
        items += holidayItems(online?.holidays, calendar: calendar, dayStyle: dayStyle)

        let groupOrder = Dictionary(uniqueKeysWithValues: TripChecklistGroup.allCases.enumerated().map { ($1, $0) })
        return items.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (groupOrder[lhs.element.group, default: 0], groupOrder[rhs.element.group, default: 0])
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// How many of the suggested items and of the traveller's own items are done, out of how many. Checked
    /// ids that match no item in `items` are not counted.
    public static func progress(items: [TripChecklistItem], state: TripChecklistState) -> (done: Int, total: Int) {
        let done = items.filter { state.isChecked(itemID: $0.id) }.count + state.customItems.filter(\.isChecked).count
        return (done, items.count + state.customItems.count)
    }

    // MARK: Items

    private static func advisoryItems(_ advisory: TravelAlertSignalSnapshot?) -> [TripChecklistItem] {
        guard let advisory, advisory.severity >= .caution else {
            return []
        }
        return [TripChecklistItem(
            id: "advisory",
            kind: .advisory,
            title: "Read the travel advisory",
            detail: nonEmpty(advisory.summary).map { "\(advisory.sourceName): \($0)" } ?? advisory.sourceName,
            link: advisory.sourceURL,
            group: .beforeYouGo
        )]
    }

    /// Abroad, unless the destination is the home country. Which SIM or plan is the traveller's to decide.
    private static func roamingItems(preview: TripPreview, home: String?) -> [TripChecklistItem] {
        guard preview.countryCode != home else {
            return []
        }
        return [TripChecklistItem(
            id: "roaming",
            kind: .roaming,
            title: "Check roaming or a local SIM",
            detail: "Data Guard can track a capped plan",
            group: .beforeYouGo
        )]
    }

    private static func drivingItems(preview: TripPreview, home: String?) -> [TripChecklistItem] {
        guard let road = preview.road,
              road.changesFromPreviousCountry
              || ArrivalBriefing.road(countryCode: preview.countryCode, comparedWith: home)?.changesFromPreviousCountry == true
        else {
            return []
        }
        let side = road.side == .left ? "left" : "right"
        return [TripChecklistItem(
            id: "driving.\(side)",
            kind: .driving,
            title: "Drive on the \(side) — check rental and insurance",
            group: .beforeYouGo
        )]
    }

    private static func consularItems(_ embassy: TripPreview.Embassy?) -> [TripChecklistItem] {
        guard let embassy, let contacts = embassy.consularContacts else {
            return []
        }
        return [TripChecklistItem(
            id: "consular-line.\(embassy.citizenshipCode)",
            kind: .consularLine,
            title: "Save \(contacts.emergencyPhone) in your phone",
            detail: [contacts.ministryName, contacts.emergencyPhoneNote].compactMap(\.self).joined(separator: " · "),
            group: .beforeYouGo
        )]
    }

    private static func emergencyItems(_ numbers: EmergencyNumbers?) -> [TripChecklistItem] {
        guard let numbers else {
            return []
        }

        var parts = ["Emergency \(numbers.general)"]
        if let police = numbers.police {
            parts.append("Police \(police)")
        }
        switch (numbers.ambulance, numbers.fire) {
        case let (ambulance?, fire?) where ambulance == fire:
            parts.append("Ambulance/fire \(ambulance)")
        case let (ambulance, fire):
            if let ambulance {
                parts.append("Ambulance \(ambulance)")
            }
            if let fire {
                parts.append("Fire \(fire)")
            }
        }
        parts += numbers.other.map { "\($0.name) \($0.number)" }

        return [TripChecklistItem(
            id: "emergency-numbers",
            kind: .emergencyNumbers,
            title: parts.joined(separator: " · "),
            detail: "Note them down in case you have no signal",
            group: .beforeYouGo
        )]
    }

    /// When the plugs, voltage or frequency differ from the country the traveller is in now (flagged by the
    /// preview) or from home.
    private static func adapterItems(preview: TripPreview, home: String?) -> [TripChecklistItem] {
        guard let power = preview.power else {
            return []
        }
        let differsFromHome = TravelReferenceData.electricity(forCountryCode: home).map(power.electricity.differs(from:)) ?? false
        guard power.differsFromPreviousCountry || differsFromHome else {
            return []
        }

        let electricity = power.electricity
        let plugs = electricity.plugTypes
        return [TripChecklistItem(
            id: "adapter.\(plugs.joined(separator: "-"))",
            kind: .adapter,
            title: "Pack a plug adapter for type \(plugs.joined(separator: "/")) (\(electricity.voltage) V)",
            detail: "\(electricity.frequencyHertz) Hz · laptop and phone chargers usually accept 100–240 V, check the label on yours",
            group: .moneyAndPower
        )]
    }

    private static func cashItems(preview: TripPreview, home: String?) -> [TripChecklistItem] {
        guard let money = preview.money,
              money.changesFromPreviousCountry
              || TravelReferenceData.currencyCode(forCountryCode: home).map({ $0 != money.currencyCode }) == true
        else {
            return []
        }
        return [TripChecklistItem(
            id: "cash.\(money.currencyCode)",
            kind: .cash,
            title: "Get some \(money.currencyName ?? "local currency") (\(money.currencyCode))",
            group: .moneyAndPower
        )]
    }

    private static func registrationItems(_ embassy: TripPreview.Embassy?) -> [TripChecklistItem] {
        guard let embassy, let contacts = embassy.consularContacts,
              contacts.travelRegistrationName != nil || contacts.travelRegistrationURL != nil
        else {
            return []
        }
        return [TripChecklistItem(
            id: "register.\(embassy.citizenshipCode)",
            kind: .registerTrip,
            title: contacts.travelRegistrationName.map { "Register your trip (\($0))" } ?? "Register your trip",
            detail: contacts.ministryName,
            link: contacts.travelRegistrationURL,
            group: .documents
        )]
    }

    private static func visaItems(_ visa: TripVisaOutlook, dayStyle: Date.FormatStyle) -> [TripChecklistItem] {
        var items: [TripChecklistItem] = []

        if case let .counting(window) = visa.schengen, let breach = window.firstExceededOn {
            items.append(TripChecklistItem(
                id: "visa.schengen",
                kind: .visaSchengen,
                title: "Your plan exceeds Schengen 90/180 on \(breach.formatted(dayStyle)) — adjust dates",
                group: .documents
            ))
        }

        if let allowance = visa.allowance {
            items.append(TripChecklistItem(
                id: "visa.allowance.\(allowance.countryCode)",
                kind: .visaAllowance,
                title: "Check your entry allowance covers \(dayCount(allowance.tripDays))",
                detail: allowance.overstayDays > 0
                    ? "Your allowance is \(dayCount(allowance.allowanceDays)), \(dayCount(allowance.overstayDays)) short of the trip"
                    : "Your allowance is \(dayCount(allowance.allowanceDays))",
                group: .documents
            ))
        }
        return items
    }

    private static func rhythmItems(preview: TripPreview, calendar: Calendar) -> [TripChecklistItem] {
        let firstDay = preview.trip.firstDay(calendar: calendar)
        var kinds = Set<LocalRhythmKind>()
        return preview.rhythm.compactMap { rhythm in
            guard kinds.insert(rhythm.period.kind).inserted else {
                return nil
            }
            let name = rhythm.period.shortName
            let title: String
            if rhythm.startsDuringTrip {
                let day = PlannedTrip.days(from: firstDay, to: rhythm.period.start, calendar: calendar) + 1
                title = "\(name) starts on day \(day)"
            } else {
                title = "\(name) is on during your trip"
            }
            return TripChecklistItem(
                id: "rhythm.\(rhythm.period.kind.rawValue)",
                kind: .rhythm,
                title: title,
                detail: nonEmpty(rhythm.period.guidance),
                group: .onArrival
            )
        }
    }

    private static func holidayItems(
        _ holidays: [HolidayPeriodSnapshot]?,
        calendar: Calendar,
        dayStyle: Date.FormatStyle
    ) -> [TripChecklistItem] {
        (holidays ?? [])
            .sorted { $0.startDate < $1.startDate }
            .prefix(maximumHolidayItems)
            .map { holiday in
                let start = calendar.startOfDay(for: holiday.startDate)
                let end = calendar.startOfDay(for: holiday.endDate)
                let when = end > start
                    ? "\(start.formatted(dayStyle))–\(end.formatted(dayStyle))"
                    : start.formatted(dayStyle)
                let parts = calendar.dateComponents([.year, .month, .day], from: start)
                return TripChecklistItem(
                    id: String(format: "holiday.%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                    kind: .holiday,
                    title: "Public holiday \(when) (\(holiday.name)) — shops may close",
                    group: .onArrival
                )
            }
    }

    // MARK: Text

    private static func dayCount(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
