import Foundation
import NomadCore

/// Where the holidays and the travel advisory of a trip stand. They need the network, so they arrive after
/// the rest of the preview.
enum TripOnlineState: Equatable {
    case loading
    case loaded(TripPreviewOnline)
    /// Nothing could be loaded and nothing is saved.
    case unavailable
}

/// Where the price comparison with home stands.
enum TripPriceState: Equatable {
    case loading
    /// No home country, the same country, or no Eurostat data on either side: the section is hidden.
    case unavailable
    case loaded([PriceLevelDifference])
}

/// Everything the Trip Planner shows for the selected trip. The offline sections are composed at once; the
/// online ones and the price comparison join when they load. Planned trips, the home country and
/// citizenship are sensitive: all of it is computed locally and never part of analytics.
struct TripPreviewPresentation {
    typealias Row = ArrivalBriefingPresentation.Row

    /// "Holidays and advisory" status line.
    enum OnlineStatus: Equatable {
        case loading
        /// "Updated 12 Oct 2026, 14:03".
        case updated(String)
        /// "Not available offline".
        case unavailable(String)
    }

    struct Embassy: Equatable {
        let hotline: EmbassyCardPresentation.Hotline?
        /// The traveller's own missions in the destination, best first; no distances.
        let missions: [EmbassyCardPresentation.MissionRow]
        /// Explains `fallbackMissions` or, with no mission at all, says so.
        let notice: String?
        let fallbackMissions: [EmbassyCardPresentation.MissionRow]
        let links: [EmbassyCardPresentation.LinkGroup]
        let footer: String
    }

    struct OnlineSection: Equatable {
        let status: OnlineStatus
        let holidays: [Row]
        let advisory: Row?
    }

    struct Prices: Equatable {
        let lines: [String]
        let caption: String
    }

    struct VisaItem: Identifiable, Equatable {
        let id: String
        let title: String
        let text: String
        /// Under the text, for example the peak of a Schengen window that exceeds the limit.
        let detail: String?
        let progress: Double?
        /// Sand or coral carry a status; every other tone reads neutral.
        let tone: SummaryTileTone
    }

    struct Visa: Equatable {
        let items: [VisaItem]
        let footer: String
    }

    static let pricesCaption = "Eurostat price levels · annual"
    static let pricesTitle = "Prices vs home"
    static let visaTitle = "Visa what-if"
    static let embassyTitle = "Your embassy"
    static let basicsTitle = "Before you go"
    static let rhythmTitle = "Local rhythm during your trip"
    static let onlineTitle = "Holidays and advisory"
    static let loadingText = "Checking holidays and advisory…"
    static let editTitle = "Edit"

    /// "Morocco".
    let title: String
    /// "12–26 Jan 2027 · 14 days (13 nights) · in 92 days".
    let subtitle: String
    let note: String?
    let schedule: TripPreview.Schedule
    /// The whole header on one line: "Morocco · 12–26 Jan 2027 · 14 days (13 nights) · in 92 days".
    var headerLine: String {
        "\(title) · \(subtitle)"
    }

    /// Time difference, emergency numbers, driving side, plugs and currency.
    let basics: [Row]
    let embassy: Embassy?
    let rhythm: [Row]
    let online: OnlineSection
    let prices: Prices?
    let visa: Visa?
    let footer = TripPlannerText.footer

    init(
        preview: TripPreview,
        online: TripOnlineState,
        prices: TripPriceState,
        policy: DashboardResourcePolicy,
        homeCountryCode: String?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current,
        missionIndex: DiplomaticMissionIndex = .bundled
    ) {
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        let dayText = { (date: Date) in date.formatted(dayStyle) }

        title = preview.title
        subtitle = [
            TripDateFormatting.range(of: preview.trip, calendar: calendar, locale: locale),
            TripDateFormatting.length(dayCount: preview.schedule.dayCount, nightCount: preview.schedule.nightCount),
            TripTiming.text(daysUntilStart: preview.schedule.daysUntilStart, daysSinceEnd: preview.schedule.daysSinceEnd)
        ].joined(separator: " · ")
        note = preview.trip.note
        schedule = preview.schedule

        var basics: [Row] = []
        if let difference = preview.timeDifference {
            basics.append(Row(
                id: "time",
                kind: .time,
                symbolName: "clock.fill",
                title: "Time",
                text: difference.text,
                detail: nil,
                tone: .neutral,
                flag: nil,
                isSelectable: false
            ))
        }
        if let emergency = preview.emergency {
            basics.append(ArrivalBriefingPresentation.emergencyRow(emergency))
        }
        if let road = preview.road {
            basics.append(ArrivalBriefingPresentation.roadRow(road))
        }
        if let power = preview.power {
            basics.append(ArrivalBriefingPresentation.powerRow(power))
        }
        if let money = preview.money {
            basics.append(ArrivalBriefingPresentation.moneyRow(money))
        }
        self.basics = basics

        embassy = preview.embassy.map {
            Self.embassy($0, hostName: preview.countryName, locale: locale, missionIndex: missionIndex)
        }
        rhythm = preview.rhythm.map { Self.rhythmRow($0, now: now, calendar: calendar, locale: locale) }
        self.online = Self.onlineSection(online, policy: policy, locale: locale, calendar: calendar)
        self.prices = Self.prices(prices, homeCountryCode: homeCountryCode, locale: locale)
        visa = Self.visa(preview, dayText: dayText)
    }

    // MARK: Embassy

    private static func embassy(
        _ embassy: TripPreview.Embassy,
        hostName: String,
        locale: Locale,
        missionIndex: DiplomaticMissionIndex
    ) -> Embassy {
        let code = embassy.citizenshipCode
        let hasMissions = embassy.ownMissions.isEmpty == false || embassy.fallbackMissions.isEmpty == false
        let notice: String? = if embassy.ownMissions.isEmpty == false {
            nil
        } else if let reason = embassy.fallbackReason, embassy.fallbackMissions.isEmpty == false {
            EmbassyCardPresentation.fallbackNotice(reason, citizenships: [code], host: hostName, locale: locale)
        } else if hasMissions == false {
            "\(EmbassyCardPresentation.noMissionSentence(citizenships: [code], host: hostName, locale: locale)), and no EU or Nordic alternative is known. Check the official missions directory."
        } else {
            nil
        }

        return Embassy(
            hotline: EmbassyCardPresentation.hotlines(for: [code], locale: locale).first,
            missions: embassy.ownMissions.map {
                EmbassyCardPresentation.row(for: $0, isFallback: false, reasonCaption: nil, locale: locale)
            },
            notice: notice,
            fallbackMissions: embassy.fallbackMissions.map {
                EmbassyCardPresentation.row(for: $0, isFallback: true, reasonCaption: nil, locale: locale)
            },
            links: EmbassyCardPresentation.links(for: [code], locale: locale),
            footer: EmbassyCardPresentation.footer(for: missionIndex, locale: locale)
        )
    }

    // MARK: Local rhythm

    /// "Starts mid-trip" or "Ends mid-trip"; "During your trip" when it both starts and ends within it, and
    /// "All trip long" when it is on for all of it.
    static func rhythmFlag(startsDuringTrip: Bool, endsDuringTrip: Bool) -> String {
        switch (startsDuringTrip, endsDuringTrip) {
        case (true, true): "During your trip"
        case (true, false): "Starts mid-trip"
        case (false, true): "Ends mid-trip"
        case (false, false): "All trip long"
        }
    }

    private static func rhythmRow(_ period: TripPreview.RhythmPeriod, now: Date, calendar: Calendar, locale: Locale) -> Row {
        let model = LocalRhythmRowModel(period: period.period, now: now, calendar: calendar, locale: locale)
        return Row(
            id: "rhythm-\(model.id)",
            kind: .rhythm,
            symbolName: "calendar.badge.clock",
            title: model.name,
            text: model.dates,
            detail: model.guidance,
            tone: .neutral,
            flag: rhythmFlag(startsDuringTrip: period.startsDuringTrip, endsDuringTrip: period.endsDuringTrip),
            isSelectable: false
        )
    }

    // MARK: Holidays and advisory

    /// "Not available offline", "Not available in Low Data mode" or "Not available right now".
    static func unavailableText(policy: DashboardResourcePolicy) -> String {
        if policy.isOffline {
            return "Not available offline"
        }

        return policy.isLowData ? "Not available in Low Data mode" : "Not available right now"
    }

    private static func onlineSection(
        _ state: TripOnlineState,
        policy: DashboardResourcePolicy,
        locale: Locale,
        calendar: Calendar
    ) -> OnlineSection {
        switch state {
        case .loading:
            return OnlineSection(status: .loading, holidays: [], advisory: nil)
        case .unavailable:
            return OnlineSection(status: .unavailable(unavailableText(policy: policy)), holidays: [], advisory: nil)
        case let .loaded(online):
            let stamp = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return OnlineSection(
                status: .updated("Updated \(online.fetchedAt.formatted(stamp))"),
                holidays: holidayRows(online.holidays, policy: policy, calendar: calendar, locale: locale),
                advisory: online.advisory.map {
                    ArrivalBriefingPresentation.advisoryRow(summary: $0.summary, sourceName: $0.sourceName, severity: $0.severity)
                }
            )
        }
    }

    private static func holidayRows(
        _ holidays: [HolidayPeriodSnapshot]?,
        policy: DashboardResourcePolicy,
        calendar: Calendar,
        locale: Locale
    ) -> [Row] {
        func row(id: String, title: String, text: String, detail: String?) -> Row {
            Row(
                id: id,
                kind: .holiday,
                symbolName: "calendar",
                title: title,
                text: text,
                detail: detail,
                tone: .neutral,
                flag: nil,
                isSelectable: false
            )
        }

        guard let holidays else {
            return [row(id: "holidays", title: "Public holidays", text: unavailableText(policy: policy), detail: nil)]
        }
        guard holidays.isEmpty == false else {
            return [row(id: "holidays", title: "Public holidays", text: "None during your trip", detail: nil)]
        }

        let weekdayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        return holidays.enumerated().map { offset, holiday in
            let sameDay = calendar.isDate(holiday.startDate, inSameDayAs: holiday.endDate)
            let dates = sameDay
                ? holiday.startDate.formatted(weekdayStyle)
                : "\(holiday.startDate.formatted(dayStyle)) – \(holiday.endDate.formatted(dayStyle))"
            return row(id: "holiday-\(offset)", title: "Public holiday", text: holiday.name, detail: dates)
        }
    }

    // MARK: Prices

    private static func prices(_ state: TripPriceState, homeCountryCode: String?, locale: Locale) -> Prices? {
        guard case let .loaded(differences) = state, differences.isEmpty == false, let homeCountryCode else {
            return nil
        }

        return Prices(
            lines: differences.map { PriceLevelComparison.text(for: $0, homeCountryCode: homeCountryCode, locale: locale) },
            caption: pricesCaption
        )
    }

    // MARK: Visa what-if

    private static func visa(_ preview: TripPreview, dayText: (Date) -> String) -> Visa? {
        var items: [VisaItem] = []

        if let schengen = preview.visa.schengen {
            items.append(schengenItem(schengen, dayText: dayText))
        }
        if let allowance = preview.visa.allowance {
            items.append(allowanceItem(allowance, countryName: preview.countryName, dayText: dayText))
        }
        for year in preview.visa.taxYears {
            items.append(taxYearItem(year, countryName: preview.countryName, dayText: dayText))
        }

        return items.isEmpty ? nil : Visa(items: items, footer: StaysCardPresentation.taxFooter)
    }

    private static func schengenItem(_ projection: SchengenProjection, dayText: (Date) -> String) -> VisaItem {
        let title = "Schengen"
        guard let window = projection.window else {
            return VisaItem(
                id: "schengen",
                title: title,
                text: StaysCardPresentation.schengenExemptReason,
                detail: nil,
                progress: nil,
                tone: .neutral
            )
        }

        let limit = SchengenArea.maximumStayDays
        let peak = "Peak \(window.peakUsedDays) of \(limit) days" + (window.peakDay.map { " on \(dayText($0))" } ?? "")
        let progress = Double(window.peakUsedDays) / Double(limit)

        if let exceeded = window.firstExceededOn {
            return VisaItem(
                id: "schengen",
                title: title,
                text: "Exceeds \(limit)/\(SchengenArea.windowDays) on \(dayText(exceeded))",
                detail: peak,
                progress: progress,
                tone: .attention
            )
        }

        if case .unknownCitizenship = projection {
            return VisaItem(
                id: "schengen",
                title: title,
                text: peak,
                detail: StaysCardPresentation.citizenshipHint,
                progress: progress,
                tone: .neutral
            )
        }

        return VisaItem(
            id: "schengen",
            title: title,
            text: peak,
            detail: nil,
            progress: progress,
            tone: StaysCardPresentation.tone(daysLeft: window.remainingDaysAtPeak, isOver: false)
        )
    }

    private static func allowanceItem(_ allowance: StayAllowanceProjection, countryName: String, dayText: (Date) -> String) -> VisaItem {
        let usage = "\(allowance.tripDays) of \(StaysCardPresentation.dayCount(allowance.allowanceDays))"
        let isOver = allowance.overstayDays > 0
        return VisaItem(
            id: "allowance",
            title: "\(countryName) allowance",
            text: isOver
                ? "\(usage) · \(StaysCardPresentation.dayCount(allowance.overstayDays)) over"
                : usage,
            detail: isOver ? "Last permitted day \(dayText(allowance.lastPermittedDay))" : nil,
            progress: Double(allowance.tripDays) / Double(allowance.allowanceDays),
            tone: StaysCardPresentation.tone(daysLeft: allowance.remainingDays, isOver: isOver)
        )
    }

    private static func taxYearItem(_ year: TaxYearProjection, countryName: String, dayText: (Date) -> String) -> VisaItem {
        let isNear = year.totalDays >= year.thresholdDays - StayWarningThresholds.taxResidenceCautionLeadDays
        return VisaItem(
            id: "tax-\(year.year)",
            title: "\(countryName) \(year.year)",
            text: "\(year.plannedDays) planned + \(year.recordedDays) recorded days of \(year.thresholdDays)",
            detail: year.thresholdReachedOn.map { "Reaches \(year.thresholdDays) days on \(dayText($0))" },
            progress: Double(year.totalDays) / Double(max(year.thresholdDays, 1)),
            tone: isNear ? .caution : .neutral
        )
    }
}
