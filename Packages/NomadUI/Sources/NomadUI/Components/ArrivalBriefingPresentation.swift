import Foundation
import NomadCore

/// The "Welcome to Morocco" card shown on the first day in a new country, as compact rows. Only sections
/// the briefing has data for appear.
struct ArrivalBriefingPresentation {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable {
            case time, emergency, embassy, road, power, money, holiday, advisory, rhythm, dataGuard
        }

        let id: String
        let kind: Kind
        let symbolName: String
        let title: String
        let text: String
        let detail: String?
        /// Sand for something that changed or needs care, coral for a serious advisory; neutral otherwise.
        let tone: SummaryTileTone
        /// "Changed" when plugs, currency or driving side differ from the previous country.
        let flag: String?
        /// Whether the text can be selected and copied (phone numbers).
        let isSelectable: Bool
    }

    static let acknowledgeTitle = "Got it"
    static let changedFlag = "Changed"
    static let startMonitoringTitle = "Start monitoring"

    let title: String
    /// "Arrived from Spain", nil when the previous country is the same or unknown.
    let subtitle: String?
    let rows: [Row]
    /// What the collapsed card says after the title: "Emergency 112 · Drive on the left".
    let collapsedSummary: String

    init(
        briefing: ArrivalBriefing,
        previousCountryCode: String?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        title = briefing.title
        subtitle = previousCountryCode
            .map { CitizenshipSettingsPresentation.countryName(for: $0, locale: locale) }
            .flatMap { $0 == briefing.countryName ? nil : "Arrived from \($0)" }

        var rows: [Row] = []
        if let time = briefing.time {
            rows.append(Self.timeRow(time, now: now, locale: locale))
        }
        if let emergency = briefing.emergency {
            rows.append(Row(
                id: "emergency",
                kind: .emergency,
                symbolName: "phone.arrow.up.right.fill",
                title: "Emergency",
                text: emergency.general,
                detail: emergency.othersText,
                tone: .neutral,
                flag: nil,
                isSelectable: true
            ))
        }
        if let embassy = briefing.embassy, let row = Self.embassyRow(embassy, locale: locale) {
            rows.append(row)
        }
        if let road = briefing.road {
            rows.append(Row(
                id: "road",
                kind: .road,
                symbolName: "car.fill",
                title: "Driving",
                text: road.text,
                detail: nil,
                tone: road.changesFromPreviousCountry ? .caution : .neutral,
                flag: road.changesFromPreviousCountry ? Self.changedFlag : nil,
                isSelectable: false
            ))
        }
        if let power = briefing.power {
            rows.append(Row(
                id: "power",
                kind: .power,
                symbolName: "powerplug.fill",
                title: "Power",
                text: Self.powerText(power.electricity),
                detail: nil,
                tone: .neutral,
                flag: power.differsFromPreviousCountry ? Self.changedFlag : nil,
                isSelectable: false
            ))
        }
        if let money = briefing.money {
            rows.append(Row(
                id: "money",
                kind: .money,
                symbolName: "banknote.fill",
                title: "Currency",
                text: money.currencyName.map { "\($0) (\(money.currencyCode))" } ?? money.currencyCode,
                detail: nil,
                tone: .neutral,
                flag: money.changesFromPreviousCountry ? Self.changedFlag : nil,
                isSelectable: false
            ))
        }
        if let holiday = briefing.holiday {
            rows.append(Row(
                id: "holiday",
                kind: .holiday,
                symbolName: "calendar",
                title: "Public holiday",
                text: "\(holiday.name) \(holiday.daysFromToday == 0 ? "today" : "tomorrow")",
                detail: "Shops and offices may be closed",
                tone: .neutral,
                flag: nil,
                isSelectable: false
            ))
        }
        if let advisory = briefing.advisory {
            rows.append(Row(
                id: "advisory",
                kind: .advisory,
                symbolName: "exclamationmark.triangle.fill",
                title: "Travel advisory",
                text: advisory.summary,
                detail: advisory.sourceName,
                tone: SummaryTileTone(severity: advisory.severity),
                flag: nil,
                isSelectable: false
            ))
        }
        for period in briefing.rhythm {
            let model = LocalRhythmRowModel(period: period, now: now, calendar: calendar, locale: locale)
            rows.append(Row(
                id: "rhythm-\(model.id)",
                kind: .rhythm,
                symbolName: "calendar.badge.clock",
                title: model.name,
                text: model.dates,
                detail: model.guidance,
                tone: .neutral,
                flag: model.timing,
                isSelectable: false
            ))
        }
        if let hint = briefing.dataGuardHint {
            rows.append(Row(
                id: "dataGuard",
                kind: .dataGuard,
                symbolName: "antenna.radiowaves.left.and.right",
                title: "Data Guard",
                text: hint,
                detail: nil,
                tone: .neutral,
                flag: nil,
                isSelectable: false
            ))
        }

        self.rows = rows
        collapsedSummary = [
            briefing.emergency.map { "Emergency \($0.general)" },
            briefing.road.flatMap { $0.changesFromPreviousCountry ? $0.text : nil }
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    // MARK: Rows

    /// "Local 10:42 (UTC+0) · Home (Helsinki) is 2 h ahead".
    private static func timeRow(_ time: ArrivalBriefing.Time, now: Date, locale: Locale) -> Row {
        let zone = TimeZone(identifier: time.timeZoneIdentifier)
        let clock = zone.map { now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: $0)) }
        let local = [clock.map { "Local \($0)" } ?? "Local time", "(\(time.utcOffsetText))"].joined(separator: " ")
        return Row(
            id: "time",
            kind: .time,
            symbolName: "clock.fill",
            title: "Time",
            text: [local, time.home?.differenceText].compactMap(\.self).joined(separator: " · "),
            detail: nil,
            tone: .neutral,
            flag: nil,
            isSelectable: false
        )
    }

    /// The nearest mission and the ministry hotline; nil when neither is known.
    private static func embassyRow(_ embassy: ArrivalBriefing.Embassy, locale: Locale) -> Row? {
        let mission = embassy.nearestMission?.mission
        let missionText = mission.map { mission in
            [mission.name, mission.city.flatMap { mission.name.contains($0) ? nil : $0 }]
                .compactMap(\.self)
                .joined(separator: " · ")
        }
        let hotline = embassy.consularContacts.map {
            "\(EmbassyCardPresentation.shortMinistryName($0.ministryName)) \($0.emergencyPhone)"
        }
        let reason = embassy.fallbackReason.map { reason in
            switch reason {
            case .euConsularProtection: "Under EU consular protection"
            case .nordicCooperation: "Under Nordic cooperation"
            }
        }

        guard let text = missionText ?? hotline else {
            return nil
        }

        return Row(
            id: "embassy",
            kind: .embassy,
            symbolName: "building.columns.fill",
            title: "Your embassy",
            text: text,
            detail: [missionText == nil ? nil : hotline, reason].compactMap(\.self).joined(separator: " · ").nilIfEmpty,
            tone: .neutral,
            flag: nil,
            isSelectable: true
        )
    }

    /// "Plug C, E · 230 V · 50 Hz".
    static func powerText(_ electricity: CountryElectricity) -> String {
        let plugs = electricity.plugTypes.joined(separator: ", ")
        return [
            plugs.isEmpty ? nil : "Plug \(plugs)",
            "\(electricity.voltage) V",
            "\(electricity.frequencyHertz) Hz"
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}

/// Decides which arrival to brief: the detected one, or one the user asked for from the menu.
public enum ArrivalBriefingEvents {
    /// The arrival to brief now. A briefing the user re-opened from the menu wins while it still belongs
    /// to the country they are in (and even if briefings are switched off or were acknowledged).
    public static func event(
        reopened: ArrivalEvent?,
        countryDays: [VisitedCountryDay],
        currentCountryCode: String?,
        settings: AppSettings,
        now: Date,
        calendar: Calendar
    ) -> ArrivalEvent? {
        if let reopened, reopened.countryCode.caseInsensitiveCompare(currentCountryCode ?? "") == .orderedSame {
            return reopened
        }

        return ArrivalDetector.arrival(
            countryDays: countryDays,
            currentCountryCode: currentCountryCode,
            settings: settings,
            now: now,
            calendar: calendar
        )
    }

    /// An event for re-opening the briefing of the current country, for example after "Got it". The
    /// previous country is the most recent different country in the history, else the current country
    /// itself (so nothing is flagged as changed). Nil without a current country.
    public static func reopened(
        countryDays: [VisitedCountryDay],
        currentCountryCode: String?,
        now: Date,
        calendar: Calendar
    ) -> ArrivalEvent? {
        guard let current = currentCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              current.count == 2
        else {
            return nil
        }

        let today = VisitedCountryDayStamp(date: now, calendar: calendar)
        let previous = countryDays
            .filter { $0.day < today }
            .sorted { $0.day > $1.day }
            .compactMap { $0.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .first { $0.count == 2 && $0 != current }
        return ArrivalEvent(countryCode: current, previousCountryCode: previous ?? current, arrivedOn: today)
    }
}
