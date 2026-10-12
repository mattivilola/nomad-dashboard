import Foundation
import NomadCore

/// Everything the "Stays & Visas" card shows, derived from the days Nomad recorded on this Mac, the
/// country the Mac is in and the user's stay settings.
///
/// Visited countries and citizenship are sensitive: everything here is computed locally and is never
/// part of analytics.
struct StaysCardPresentation {
    /// The run of days in the current country: "Morocco · day 23" since "since 2 Jan".
    struct CurrentStay: Equatable {
        let title: String
        let since: String
        /// Set when the stay bridges days that have no record.
        let gapNote: String?
    }

    /// The user-set allowance for the current country (a visa or an entry stamp).
    struct Allowance: Equatable {
        let title: String
        /// "67 of 90 days".
        let usage: String
        /// "leave by 3 Mar", "last day today" or "3 days over · ended 28 Feb".
        let deadline: String
        let progress: Double
        let tone: SummaryTileTone

        var text: String {
            "\(usage) · \(deadline)"
        }
    }

    struct Schengen: Equatable {
        enum Kind: Equatable {
            /// A citizenship with free movement: no limit applies.
            case exempt
            /// No citizenship is set, so it is unknown whether the limit applies.
            case citizenshipUnknown
            case counting
        }

        let kind: Kind
        let title: String
        /// "61 of 90 days used (rolling 180 days)"; the reason for the missing limit when exempt.
        let usage: String
        /// "leave by 14 Mar", only while in Schengen and the limit applies.
        let deadline: String?
        let hint: String?
        let progress: Double?
        let tone: SummaryTileTone

        /// The whole row as one line.
        var line: String {
            switch kind {
            case .exempt: "\(title): \(usage)"
            case .citizenshipUnknown, .counting: [usage, deadline].compactMap(\.self).joined(separator: " · ")
            }
        }
    }

    struct CountryDays: Identifiable, Equatable {
        let id: String
        let name: String
        /// "97 days".
        let daysText: String
        /// Days against the tax residence threshold, 0...1.
        let progress: Double
        let tone: SummaryTileTone
    }

    /// This year's days per country against the tax residence threshold.
    struct TaxYear: Equatable {
        let heading: String
        /// "Threshold 183 days".
        let thresholdText: String
        /// The countries with the most days, at most `StaysCardPresentation.taxCountryLimit`.
        let countries: [CountryDays]
        /// "Unrecorded days this year: 12", nil when every day has a record.
        let unrecordedText: String?
        let emptyText: String?
    }

    static let taxCountryLimit = 5

    static let taxFooter = "Based on days Nomad recorded on this Mac · not tax or legal advice"
    static let reviewDaysTitle = "Review days"
    static let citizenshipActionTitle = "Set citizenship"
    static let citizenshipHint = "Set your citizenship to check if this applies"
    static let schengenExemptReason = "no limit for EU/EEA/Swiss citizens"
    static let subtitle = "Days recorded on this Mac"
    static let offTitle = "Stays & Visas Off"
    static let offMessage = "Turn on “Save visited places locally” in Settings to count your days in each country."
    static let locationPendingText = "Current country not known yet"

    let isEnabled: Bool
    let badge: PillBadge
    let currentStay: CurrentStay?
    let allowance: Allowance?
    let schengen: Schengen?
    let taxYear: TaxYear?
    /// One line for the collapsed card.
    let summary: String
    let summaryHelp: String

    init(
        settings: AppSettings,
        countryDays: [VisitedCountryDay],
        currentCountryCode: String?,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        guard DashboardCardID.stays.isFeatureEnabled(in: settings) else {
            isEnabled = false
            badge = PillBadge(title: "Off", symbolName: "calendar.badge.clock", tint: NomadTheme.primaryText)
            currentStay = nil
            allowance = nil
            schengen = nil
            taxYear = nil
            summary = "Off"
            summaryHelp = "Off"
            return
        }

        isEnabled = true
        let code = Self.normalizedCode(currentCountryCode)
        let calculator = StayCalculator(days: countryDays, now: now, calendar: calendar, liveCountryCode: code)
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        let dayText = { (date: Date) in date.formatted(dayStyle) }
        let todayText = { (date: Date) in calendar.isDate(date, inSameDayAs: now) }

        let stay = code.flatMap { calculator.currentStay(in: $0) }
        let countryName = code.map { CitizenshipSettingsPresentation.countryName(for: $0, locale: locale) }

        currentStay = stay.flatMap { stay in
            countryName.map { name in
                CurrentStay(
                    title: "\(name) · day \(stay.dayCount)",
                    since: "since \(dayText(stay.startDate))",
                    gapNote: Self.gapNote(days: stay.unrecordedGapDays)
                )
            }
        }

        let allowanceStatus = code.flatMap { code in
            settings.stayAllowances[code].flatMap { calculator.allowanceStatus(country: code, allowanceDays: $0) }
        }
        allowance = allowanceStatus.flatMap { status in
            countryName.map { name in
                Self.allowance(status, countryName: name, dayText: dayText, isToday: todayText)
            }
        }

        let schengenStatus = settings.schengenCounterEnabled
            ? calculator.schengenStatus(citizenships: settings.citizenshipCountryCodes)
            : nil
        schengen = schengenStatus.map { Self.schengen($0, dayText: dayText, isToday: todayText) }

        taxYear = settings.taxResidenceDaysEnabled
            ? Self.taxYear(
                calculator.taxYearDays(year: calendar.component(.year, from: now)),
                threshold: settings.taxResidenceThresholdDays,
                locale: locale
            )
            : nil

        let tones = [allowance?.tone, schengen?.tone] + (taxYear?.countries.map(\.tone) ?? [])
        let urgent = tones.compactMap(\.self).max { $0.urgency < $1.urgency } ?? .neutral
        badge = Self.badge(
            tone: urgent,
            isOverLimit: (allowanceStatus?.overstayDays ?? 0) > 0 || Self.schengenIsExceeded(schengenStatus)
        )

        summary = Self.summaryLine(
            stayPhrase: stay.flatMap { stay in countryName.map { "\($0) day \(stay.dayCount)" } },
            allowance: allowanceStatus,
            schengen: schengenStatus,
            isInSchengen: code.map(SchengenArea.isMember) ?? false,
            taxYear: taxYear
        )
        summaryHelp = Self.summaryHelp(summary: summary, currentStay: currentStay, allowance: allowance, schengen: schengen)
    }

    // MARK: Sections

    private static func normalizedCode(_ code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), code.count == 2 else {
            return nil
        }

        return code
    }

    private static func dayCount(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    private static func gapNote(days: Int) -> String? {
        guard days > 0 else {
            return nil
        }

        return "Includes \(dayCount(days)) without a record, counted as spent here"
    }

    private static func tone(daysLeft: Int, isOver: Bool) -> SummaryTileTone {
        if isOver || daysLeft <= StayWarningThresholds.attentionDays {
            return .attention
        }

        return daysLeft <= StayWarningThresholds.cautionDays ? .caution : .neutral
    }

    private static func allowance(
        _ status: StayAllowanceStatus,
        countryName: String,
        dayText: (Date) -> String,
        isToday: (Date) -> Bool
    ) -> Allowance {
        let deadline: String
        if status.overstayDays > 0 {
            deadline = "\(dayCount(status.overstayDays)) over · ended \(dayText(status.lastPermittedDay))"
        } else if isToday(status.lastPermittedDay) {
            deadline = "last day today"
        } else {
            deadline = "leave by \(dayText(status.lastPermittedDay))"
        }

        return Allowance(
            title: "\(countryName) allowance",
            usage: "\(status.usedDays) of \(dayCount(status.allowanceDays))",
            deadline: deadline,
            progress: Double(status.usedDays) / Double(status.allowanceDays),
            tone: tone(daysLeft: status.remainingDays, isOver: status.overstayDays > 0)
        )
    }

    private static func schengen(
        _ status: SchengenStatus,
        dayText: (Date) -> String,
        isToday: (Date) -> Bool
    ) -> Schengen {
        let title = "Schengen"
        switch status {
        case .exempt:
            return Schengen(
                kind: .exempt,
                title: title,
                usage: schengenExemptReason,
                deadline: nil,
                hint: nil,
                progress: nil,
                tone: .neutral
            )
        case let .counting(allowance):
            let deadline = allowance.mustLeaveBy.map { date in
                isToday(date) ? "leave today" : "leave by \(dayText(date))"
            }
            return Schengen(
                kind: .counting,
                title: title,
                usage: usage(allowance),
                deadline: deadline,
                hint: nil,
                progress: progress(allowance),
                // Only a stay inside Schengen can run into the limit; outside it the count is for planning.
                tone: allowance.mustLeaveBy == nil
                    ? .neutral
                    : tone(daysLeft: allowance.remainingDays, isOver: allowance.usedDays > SchengenArea.maximumStayDays)
            )
        case let .unknownCitizenship(allowance):
            return Schengen(
                kind: .citizenshipUnknown,
                title: title,
                usage: usage(allowance),
                deadline: nil,
                hint: citizenshipHint,
                progress: progress(allowance),
                tone: .neutral
            )
        }
    }

    private static func usage(_ allowance: SchengenAllowance) -> String {
        "\(allowance.usedDays) of \(SchengenArea.maximumStayDays) days used (rolling \(SchengenArea.windowDays) days)"
    }

    private static func progress(_ allowance: SchengenAllowance) -> Double {
        Double(allowance.usedDays) / Double(SchengenArea.maximumStayDays)
    }

    private static func schengenIsExceeded(_ status: SchengenStatus?) -> Bool {
        guard case let .counting(allowance) = status else {
            return false
        }

        return allowance.mustLeaveBy != nil && allowance.usedDays > SchengenArea.maximumStayDays
    }

    private static func taxYear(_ days: TaxYearDays, threshold: Int, locale: Locale) -> TaxYear {
        let countries = days.countries.prefix(taxCountryLimit).map { entry in
            CountryDays(
                id: entry.id,
                name: entry.countryCode.map { CitizenshipSettingsPresentation.countryName(for: $0, locale: locale) }
                    ?? entry.country,
                daysText: dayCount(entry.days),
                progress: Double(entry.days) / Double(max(threshold, 1)),
                tone: entry.days >= threshold - StayWarningThresholds.taxResidenceCautionLeadDays ? .caution : .neutral
            )
        }

        return TaxYear(
            heading: "Days in \(days.year)",
            thresholdText: "Threshold \(dayCount(threshold))",
            countries: Array(countries),
            unrecordedText: days.unrecordedDays > 0 ? "Unrecorded days this year: \(days.unrecordedDays)" : nil,
            emptyText: countries.isEmpty ? "No days recorded yet this year" : nil
        )
    }

    // MARK: Badge and summary

    /// The collapsed line spelled out for hover and VoiceOver.
    private static func summaryHelp(
        summary: String,
        currentStay: CurrentStay?,
        allowance: Allowance?,
        schengen: Schengen?
    ) -> String {
        let parts = [
            currentStay.map { "\($0.title) (\($0.since))" },
            allowance.map { "\($0.title): \($0.text)" },
            schengen.map(\.line)
        ]
        .compactMap(\.self)
        return parts.isEmpty ? summary : parts.joined(separator: ". ")
    }

    private static func badge(tone: SummaryTileTone, isOverLimit: Bool) -> PillBadge {
        switch tone {
        case .attention:
            PillBadge(
                title: isOverLimit ? "Over Limit" : "Limit Near",
                symbolName: "exclamationmark.triangle.fill",
                tint: NomadTheme.coral
            )
        case .caution:
            PillBadge(title: "Limit Near", symbolName: "exclamationmark.circle.fill", tint: NomadTheme.sand)
        default:
            PillBadge(title: "Tracking", symbolName: "calendar.badge.clock", tint: NomadTheme.primaryText)
        }
    }

    /// "Morocco day 23 · 67/90", or "Schengen 61/90" while in Schengen where the limit counts. The busiest
    /// tax-year country stands in when neither is known.
    private static func summaryLine(
        stayPhrase: String?,
        allowance: StayAllowanceStatus?,
        schengen: SchengenStatus?,
        isInSchengen: Bool,
        taxYear: TaxYear?
    ) -> String {
        // The collapsed line is short, so inside Schengen the 90-day count is the news, not the day number.
        if allowance == nil, let used = schengen?.allowance?.usedDays, isInSchengen || stayPhrase == nil {
            return "Schengen \(used)/\(SchengenArea.maximumStayDays)"
        }

        var parts: [String] = []
        if let stayPhrase {
            parts.append(stayPhrase)
        }

        if let allowance {
            parts.append("\(allowance.usedDays)/\(allowance.allowanceDays)")
        }

        if parts.isEmpty, let top = taxYear?.countries.first {
            parts.append("\(top.name) \(top.daysText)")
        }

        return parts.isEmpty ? "Collecting" : parts.joined(separator: " · ")
    }
}

extension SummaryTileTone {
    /// Ranks the tones that carry a status: attention over caution over everything else.
    fileprivate var urgency: Int {
        switch self {
        case .attention, .critical: 2
        case .caution: 1
        default: 0
        }
    }
}
