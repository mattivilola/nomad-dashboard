import Foundation

// Offline "local rhythm" calendar: cultural and religious periods that visibly change daily life for a
// visitor (opening hours, closures, traffic, etiquette). Everything is computed or looked up on the
// Mac; there is no network access.
//
// A country is only listed for a period when a visitor would notice it. Unverified countries and
// years are deliberately absent, and the calendar returns nothing for them instead of guessing.
//
// Verified 2026-10
//
// MARK: Date sources
//
//  - Ramadan, Eid al-Fitr, Eid al-Adha: `Calendar(identifier: .islamicUmmAlQura)`. Ramadan is all of
//    month 9, Eid al-Fitr is Shawwal 1-3, Eid al-Adha is Dhu al-Hijjah 10-13. Cross-checked against the
//    AlAdhan.com Umm al-Qura tables (https://aladhan.com/hijri-gregorian-calendar/9/1447 and the 10/12
//    month pages for 1447 and 1448). Actual dates follow local moon sighting and differ by a day between
//    countries (for example Indonesia and Singapore have Eid al-Adha on 17 May 2027, Umm al-Qura gives
//    16 May), so the confidence is `.expected`.
//  - Lunar New Year: `Calendar(identifier: .chinese)`, month 1 day 1 (not a leap month). Cross-checked
//    against the Hong Kong and Singapore public holiday lists: 17 Feb 2026 and 6 Feb 2027
//    (https://www.gov.hk/en/about/abouthk/holiday/2026.htm, https://www.mom.gov.sg/employment-practices/public-holidays).
//    Holiday spans are kept to the statutory core, as offsets from the first day of the new year:
//      CN  eve to day 7 (8 days): State Council notice on 2026 holidays, Spring Festival 15-23 Feb 2026 (9 days,
//          LNY 17 Feb, i.e. day -2 to day +6); the 2025 holiday was 28 Jan - 4 Feb (eve to day +6) as well.
//      TW  eve-1 to day 3 (5 days): Executive Yuan rule, the 2026 break was 14-22 Feb (9 days with weekends
//          and make-up days; Taiwan News / CNA, 2025).
//      VN  eve plus the first 4 days (5 days): Labour Code 2019, Article 112 (Tet is 5 days: 1 day at the
//          end of the old year and 4 days at the start of the new one).
//      KR  eve, day 1, day 2 (3 days): Seollal public holiday (substitute holidays are not modelled).
//      SG  days 1-2 (2 days): MOM public holidays, 17-18 Feb 2026 and 6-7 Feb 2027.
//      MY  days 1-2 (2 days): federal public holidays, 17-18 Feb 2026.
//      HK  days 1-3 (3 days): gov.hk general holidays, 17-19 Feb 2026 (2027 swaps day 2 for day 4 because
//          day 2 is a Sunday; only the conservative first three days are modelled).
//      MO  days 1-3 (3 days): the three obligatory Lunar New Year holidays under Macao labour law.
//  - Holy Week: Western Easter by the Anonymous Gregorian (Meeus/Jones/Butcher) computus, Palm Sunday
//    to Easter Sunday. Easter 5 Apr 2026 and 28 Mar 2027 (Indonesian SKB 2027 lists Paskah on 28 Mar;
//    Philippine Proclamation 1006 lists Good Friday 3 Apr 2026).
//  - Yom Kippur: `Calendar(identifier: .hebrew)`, 10 Tishrei. 21 Sep 2026 and 11 Oct 2027 (publicholidays.com,
//    timeanddate.com/holidays/israel/yom-kippur). It begins at sunset on the previous evening.
//  - Songkran (13-15 Apr, TH), Golden Week (29 Apr - 5 May, JP) and Ferragosto (15 Aug, IT) are fixed dates.
//  - Nyepi (ID): the date follows the Balinese Saka calendar and is set by decree. Only years with an
//    official decree are listed: 19 Mar 2026 (SKB 3 Menteri No. 1497/2025, 2/2025, 5/2025, signed
//    19 Sep 2025; https://www.setneg.go.id/baca/index/inilah_skb_3_menteri_libur_nasional_dan_cuti_bersama_2026)
//    and 8 Mar 2027 (SKB 3 Menteri No. 1205/2026, 3/2026, 2/2026, signed 15 Sep 2026;
//    https://setneg.go.id/baca/index/inilah_skb_3_menteri_libur_nasional_dan_cuti_bersama_2027).
//    Secondary lists (Wikipedia citing news.com.au) give 9 Mar 2027 and 26 Mar 2028, 15 Mar 2029,
//    5 Mar 2030; the 2027 value contradicts the decree, so 2028 onwards is left out until a decree exists.
//  - Diwali: the main day (Lakshmi Puja) is a table. India: Drik Panchang
//    (https://www.drikpanchang.com/diwali/diwali-puja-calendar.html?year=2026 and following years) and
//    https://www.qppstudio.net/global-holidays-observances/northern-deepavali-diwali-amavasya.htm, with
//    2032 from https://www.shreekundli.com/diwali-puja-calendar/strand/2032 and AstroSage. The date can
//    differ by a day between regions (Drik Panchang for London lists 28 Oct 2027, Delhi 29 Oct), hence
//    `.expected`. Nepal (Laxmi Puja, national holiday): 8 Nov 2026 per officeholidays.com/calendarific, 29 Oct
//    2027 per vedicmarga/officeholidays; the Nepal Panchang committee has not issued 2084 BS. Singapore:
//    MOM public holidays, 8 Nov 2026 and 28 Oct 2027. Malaysia: 8 Nov 2026 (federal holiday); the 2027
//    gazette marks Deepavali as provisional, so it is not listed.
//
// MARK: Country applicability
//
//  - Ramadan and both Eids: countries where the month is publicly observed and shapes opening hours.
//    Muslim-majority countries with secular daytime life (AZ, UZ, KZ, XK, AL, BA) are left out because a
//    visitor sees little change. The guidance differs by country: Saudi-style conservative (public eating
//    is discouraged or restricted), mixed (tourist areas keep serving), relaxed (UAE, TR) and Asia/Africa
//    (shorter hours, lively evenings).
//  - Holy Week: countries where Holy Thursday and/or Good Friday are public holidays or non-working days
//    and processions are widespread (Bloomberg Linea, 2025-26; Proclamation 1006 for PH): ES, PT, IT, MT,
//    MX, GT, CO, PE, EC, PH, CR, SV, VE, PY. Honduras, Nicaragua and the Dominican Republic are left out
//    until their rules are verified. Countries on the Orthodox calendar follow another Easter date.
//  - Lunar New Year: CN, HK, MO, TW, SG, MY, VN, KR (public holidays).
//  - Yom Kippur: IL only. Songkran: TH. Golden Week: JP. Ferragosto: IT. Nyepi: ID (Bali). Diwali: IN, NP
//    (as Tihar), SG, MY.

/// A kind of local cultural or religious period.
public enum LocalRhythmKind: String, CaseIterable, Sendable {
    case ramadan
    case eidAlFitr
    case eidAlAdha
    case lunarNewYear
    case holyWeek
    case yomKippur
    case songkran
    case goldenWeek
    case nyepi
    case diwali
    case ferragosto
}

/// How reliable the date of a period is.
public enum LocalRhythmDateConfidence: Sendable {
    /// The same civil date every year.
    case fixed
    /// Computed from a calendar or taken from an official decree.
    case computed
    /// Computed, but the actual date may shift by about a day (moon sighting, regional practice).
    case expected
}

/// One period that changes daily life in a country.
public struct LocalRhythmPeriod: Equatable, Sendable, Identifiable {
    public let kind: LocalRhythmKind
    /// Name for an English-speaking traveller, e.g. "Ramadan", "Tết (Lunar New Year)".
    public let name: String
    public let countryCode: String
    /// Start of the first day in the calendar's time zone.
    public let start: Date
    /// The last second of the last day in the calendar's time zone.
    public let end: Date
    public let confidence: LocalRhythmDateConfidence
    /// One or two short practical sentences for a visitor.
    public let guidance: String

    public var id: String {
        "\(kind.rawValue).\(countryCode).\(Int(start.timeIntervalSince1970))"
    }

    public init(
        kind: LocalRhythmKind,
        name: String,
        countryCode: String,
        start: Date,
        end: Date,
        confidence: LocalRhythmDateConfidence,
        guidance: String
    ) {
        self.kind = kind
        self.name = name
        self.countryCode = countryCode
        self.start = start
        self.end = end
        self.confidence = confidence
        self.guidance = guidance
    }
}

public enum LocalRhythmCalendar {
    /// Periods that are active on `now` or start within `lookaheadDays`, for one country, earliest first.
    ///
    /// Days are civil days in `calendar`'s time zone: the same Gregorian dates apply wherever the
    /// traveller is, and `start` and `end` are expressed in the zone of `calendar`.
    /// Returns an empty array for a missing or unknown country.
    public static func periods(
        forCountryCode countryCode: String?,
        around now: Date,
        lookaheadDays: Int = 14,
        calendar: Calendar
    ) -> [LocalRhythmPeriod] {
        guard let country = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !country.isEmpty
        else {
            return []
        }

        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone

        let horizon = local.date(byAdding: .day, value: max(0, lookaheadDays), to: now) ?? now
        let firstYear = local.component(.year, from: now) - 1
        let lastYear = local.component(.year, from: horizon) + 1

        return RhythmRules.spans(forCountry: country, years: firstYear...lastYear)
            .compactMap { span -> LocalRhythmPeriod? in
                guard let start = local.startOfDay(for: span.first),
                      let endExclusive = local.startOfDay(for: span.first.adding(days: span.dayCount)),
                      endExclusive > now, start <= horizon
                else {
                    return nil
                }
                return LocalRhythmPeriod(
                    kind: span.kind,
                    name: span.name,
                    countryCode: country,
                    start: start,
                    end: endExclusive.addingTimeInterval(-1),
                    confidence: span.confidence,
                    guidance: span.guidance
                )
            }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                let order = LocalRhythmKind.allCases
                return (order.firstIndex(of: lhs.kind) ?? 0) < (order.firstIndex(of: rhs.kind) ?? 0)
            }
    }
}

// MARK: - Civil dates

/// A Gregorian calendar date without a time zone.
private struct CivilDate: Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Julian day number (Fliegel and Van Flandern).
    var dayNumber: Int {
        let a = (month - 14) / 12
        return (1461 * (year + 4800 + a)) / 4
            + (367 * (month - 2 - 12 * a)) / 12
            - (3 * ((year + 4900 + a) / 100)) / 4
            + day - 32075
    }

    init(dayNumber: Int) {
        var l = dayNumber + 68569
        let n = (4 * l) / 146097
        l -= (146097 * n + 3) / 4
        let i = (4000 * (l + 1)) / 1461001
        l = l - (1461 * i) / 4 + 31
        let j = (80 * l) / 2447
        let d = l - (2447 * j) / 80
        l = j / 11
        self.year = 100 * (n - 49) + i + l
        self.month = j + 2 - 12 * l
        self.day = d
    }

    func adding(days: Int) -> CivilDate {
        CivilDate(dayNumber: dayNumber + days)
    }
}

private extension Calendar {
    /// Start of the civil day in this calendar's time zone, robust against zones that skip midnight.
    func startOfDay(for civil: CivilDate) -> Date? {
        guard let noon = date(from: DateComponents(year: civil.year, month: civil.month, day: civil.day, hour: 12)) else {
            return nil
        }
        return startOfDay(for: noon)
    }
}

// MARK: - Rules

private struct RhythmSpan: Sendable {
    let kind: LocalRhythmKind
    let name: String
    let first: CivilDate
    let dayCount: Int
    let confidence: LocalRhythmDateConfidence
    let guidance: String
}

private struct MonthDay: Sendable {
    let month: Int
    let day: Int
}

private enum RhythmRules {
    // MARK: Ramadan and Eids

    enum RamadanStyle: Sendable {
        /// Daytime eating is discouraged or restricted and many venues close.
        case conservative
        /// Many local venues close by day, but tourist areas and hotels keep serving.
        case mixed
        /// Daily life carries on; hours shrink and evenings are busy.
        case relaxed
        /// Shorter hours, lively evenings, discretion outside tourist areas.
        case regional
    }

    static let ramadanStyles: [String: RamadanStyle] = [
        "SA": .conservative, "KW": .conservative, "QA": .conservative, "BH": .conservative,
        "OM": .conservative, "IR": .conservative, "IQ": .conservative, "LY": .conservative,
        "MR": .conservative, "PK": .conservative, "JO": .conservative,
        "MA": .mixed, "DZ": .mixed, "TN": .mixed, "EG": .mixed,
        "AE": .relaxed, "TR": .relaxed,
        "ID": .regional, "MY": .regional, "BN": .regional, "BD": .regional, "MV": .regional, "SN": .regional
    ]

    static func ramadanGuidance(_ style: RamadanStyle) -> String {
        switch style {
        case .conservative:
            "Many cafés and restaurants close during daylight and shops keep shorter hours; traffic peaks just before sunset. Avoid eating, drinking or smoking in public during the day."
        case .mixed:
            "Shops and offices keep shorter hours and traffic peaks just before sunset, while evenings are lively. Some cafés and restaurants close or screen their windows by day, though hotels and tourist areas mostly keep serving. Be discreet eating, drinking or smoking in public during the day."
        case .relaxed:
            "Everyday life carries on and most restaurants and cafés in cities and tourist areas stay open, but office hours are shorter and traffic peaks before sunset. Be discreet about eating, drinking or smoking in public during the day, especially outside big cities."
        case .regional:
            "Expect shorter working hours and heavy traffic before sunset. Some local eateries close or screen their windows by day, while evening food stalls and markets are lively. Be discreet eating, drinking or smoking in public by day, especially outside tourist areas."
        }
    }

    static let eidAlFitrGuidance = "Offices, banks and many shops close for several days, and cities empty as people travel to family. Bus, train and flight tickets sell out early, so book ahead and check opening hours; some places stay closed for a week or longer."

    static let eidAlAdhaGuidance = "Offices, banks and many shops close for several days while families gather and travel, so book transport early. Expect livestock markets in the days before and quiet streets on the day itself."

    // MARK: Lunar New Year

    struct LunarNewYearRule: Sendable {
        let name: String
        /// Offset in days from the first day of the new year to the first holiday day (-1 is the eve).
        let firstDayOffset: Int
        let dayCount: Int
        let guidance: String
    }

    static let regionalLunarNewYearGuidance = "Offices and banks close and many small shops and restaurants shut for a few days, while malls and tourist areas mostly stay open. Transport is busy as people travel to family, so book ahead."

    static let lunarNewYearRules: [String: LunarNewYearRule] = [
        "CN": LunarNewYearRule(
            name: "Spring Festival (Lunar New Year)",
            firstDayOffset: -1,
            dayCount: 8,
            guidance: "The biggest travel period of the year: trains, flights and roads are packed, so book early. Many shops and restaurants close for a week or more, and fireworks are common on New Year's Eve and the first days where permitted."
        ),
        "TW": LunarNewYearRule(name: "Lunar New Year", firstDayOffset: -2, dayCount: 5, guidance: regionalLunarNewYearGuidance),
        "HK": LunarNewYearRule(name: "Lunar New Year", firstDayOffset: 0, dayCount: 3, guidance: regionalLunarNewYearGuidance),
        "MO": LunarNewYearRule(name: "Lunar New Year", firstDayOffset: 0, dayCount: 3, guidance: regionalLunarNewYearGuidance),
        "SG": LunarNewYearRule(name: "Lunar New Year", firstDayOffset: 0, dayCount: 2, guidance: regionalLunarNewYearGuidance),
        "MY": LunarNewYearRule(name: "Lunar New Year", firstDayOffset: 0, dayCount: 2, guidance: regionalLunarNewYearGuidance),
        "VN": LunarNewYearRule(
            name: "Tết (Lunar New Year)",
            firstDayOffset: -1,
            dayCount: 5,
            guidance: "Vietnam's biggest holiday: many shops, restaurants and services close for several days or a week, and trains, buses and flights sell out well ahead. Stock up on essentials and book transport early."
        ),
        "KR": LunarNewYearRule(
            name: "Seollal (Lunar New Year)",
            firstDayOffset: -1,
            dayCount: 3,
            guidance: "Offices, banks and many small shops and restaurants close for the three-day holiday, and trains and expressways are very busy. Convenience stores and large chains usually stay open."
        )
    ]

    // MARK: Holy Week

    static let holyWeekCountries: Set<String> = [
        "ES", "PT", "IT", "MT", "MX", "GT", "CO", "PE", "EC", "PH", "CR", "SV", "VE", "PY"
    ]

    static func holyWeekName(_ country: String) -> String {
        switch country {
        case "IT": "Settimana Santa (Holy Week)"
        case "MT": "Holy Week"
        default: "Semana Santa (Holy Week)"
        }
    }

    static func holyWeekGuidance(_ country: String) -> String {
        switch country {
        case "IT":
            "Processions and church services fill historic centres and close some streets. Shops and offices mostly stay open, but Easter Monday is a public holiday and trains and hotels are busy, so book ahead."
        case "MT":
            "Processions fill the streets of towns and villages, with the largest on Good Friday, a public holiday when shops and offices close. Expect road closures and book ahead for transport and accommodation."
        case "MX":
            "Holy Week and the week after are school holidays, so beaches, resorts and colonial towns are packed and prices rise. Processions and Passion plays close streets, and some offices and businesses close on Thursday and Friday."
        case "PH":
            "Maundy Thursday and Good Friday are national holidays: most offices, banks and many shops close and Metro Manila empties. Buses, ferries and flights sell out, so book early; processions and church services close some streets."
        default:
            "Processions fill the streets and often close roads for hours. Banks, offices and many shops close on Good Friday and often on Holy Thursday, and travel and accommodation are in high demand, so book ahead."
        }
    }

    // MARK: Single-country periods

    static let yomKippurGuidance = "Starts the evening before. For about 25 hours almost everything stops — shops, public transport and most traffic. Ben Gurion Airport closes too, so plan food, transport and cash ahead."

    static let songkranGuidance = "Thailand's New Year is a national holiday with street water fights: expect to get soaked outdoors, so protect phones and papers. Many shops and offices close, and buses, trains and flights are packed as people travel home."

    static let goldenWeekGuidance = "Japan's peak domestic travel week: trains, flights and hotels are booked out and pricier, and popular sights are crowded. Most shops and restaurants stay open, but some offices, banks and small businesses close, so reserve transport and lodging early."

    static let ferragostoGuidance = "A public holiday on 15 August. Many shops, restaurants and small businesses close for a week or two around mid-August, especially in cities, while beaches and resorts are packed. Check opening hours and book ahead."

    static let nyepiGuidance = "Bali's Day of Silence: the island shuts down for 24 hours from 6 am, including the airport. Stay at your accommodation and keep lights low."

    /// Nyepi dates with an official decree (SKB 3 Menteri). Never extrapolated.
    static let nyepiDates: [Int: MonthDay] = [
        2026: MonthDay(month: 3, day: 19),
        2027: MonthDay(month: 3, day: 8)
    ]

    // MARK: Diwali

    struct DiwaliRule: Sendable {
        let name: String
        /// Offset in days from the main day to the first day of the period.
        let firstDayOffset: Int
        let dayCount: Int
        let confidence: LocalRhythmDateConfidence
        let guidance: String
        let dates: [Int: MonthDay]
    }

    /// Lakshmi Puja (the main day of Diwali) in India.
    static let indiaDiwaliDates: [Int: MonthDay] = [
        2026: MonthDay(month: 11, day: 8),
        2027: MonthDay(month: 10, day: 29),
        2028: MonthDay(month: 10, day: 17),
        2029: MonthDay(month: 11, day: 5),
        2030: MonthDay(month: 10, day: 26),
        2031: MonthDay(month: 11, day: 14),
        2032: MonthDay(month: 11, day: 2)
    ]

    static let publicHolidayDiwaliGuidance = "A public holiday: offices and banks close, while malls, restaurants and public transport mostly keep running. Hindu temples and Indian neighbourhoods are festive and crowded."

    static let diwaliRules: [String: DiwaliRule] = [
        "IN": DiwaliRule(
            name: "Diwali",
            firstDayOffset: -1,
            dayCount: 3,
            confidence: .expected,
            guidance: "The festival of lights: banks, offices and many shops close, markets are packed with shoppers beforehand, and trains and flights are booked out. Expect fireworks and noise late into the night, and poor air quality in some cities.",
            dates: indiaDiwaliDates
        ),
        "NP": DiwaliRule(
            name: "Tihar (Festival of Lights)",
            firstDayOffset: 0,
            dayCount: 3,
            confidence: .expected,
            guidance: "Offices and banks close for a few days, houses and streets are lit with lamps, and there are firecrackers and groups singing from door to door. Travel in and out of Kathmandu is busy.",
            dates: [
                2026: MonthDay(month: 11, day: 8),
                2027: MonthDay(month: 10, day: 29)
            ]
        ),
        "SG": DiwaliRule(
            name: "Deepavali",
            firstDayOffset: 0,
            dayCount: 1,
            confidence: .computed,
            guidance: publicHolidayDiwaliGuidance,
            dates: [
                2026: MonthDay(month: 11, day: 8),
                2027: MonthDay(month: 10, day: 28)
            ]
        ),
        "MY": DiwaliRule(
            name: "Deepavali",
            firstDayOffset: 0,
            dayCount: 1,
            confidence: .computed,
            guidance: publicHolidayDiwaliGuidance,
            dates: [
                2026: MonthDay(month: 11, day: 8)
            ]
        )
    ]

    // MARK: Calendars

    private static let islamic: Calendar = utcCalendar(.islamicUmmAlQura)
    private static let chinese: Calendar = utcCalendar(.chinese)
    private static let hebrew: Calendar = utcCalendar(.hebrew)
    private static let gregorian: Calendar = utcCalendar(.gregorian)

    private static func utcCalendar(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = .gmt
        return calendar
    }

    /// The Gregorian date of a date given in another calendar.
    private static func civilDate(in calendar: Calendar, year: Int, month: Int, day: Int) -> CivilDate? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            return nil
        }
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return CivilDate(year: y, month: m, day: d)
    }

    // MARK: Spans

    static func spans(forCountry country: String, years: ClosedRange<Int>) -> [RhythmSpan] {
        var spans: [RhythmSpan] = []

        if let style = ramadanStyles[country] {
            spans += islamicSpans(style: style, years: years)
        }
        if let rule = lunarNewYearRules[country] {
            spans += lunarNewYearSpans(rule: rule, years: years)
        }
        if holyWeekCountries.contains(country) {
            spans += holyWeekSpans(country: country, years: years)
        }
        if let rule = diwaliRules[country] {
            spans += diwaliSpans(rule: rule, years: years)
        }

        for year in years {
            switch country {
            case "IL":
                if let day = civilDate(in: hebrew, year: year + 3761, month: 1, day: 10) {
                    spans.append(RhythmSpan(
                        kind: .yomKippur, name: "Yom Kippur", first: day, dayCount: 1,
                        confidence: .computed, guidance: yomKippurGuidance
                    ))
                }
            case "TH":
                spans.append(RhythmSpan(
                    kind: .songkran, name: "Songkran (Thai New Year)",
                    first: CivilDate(year: year, month: 4, day: 13), dayCount: 3,
                    confidence: .fixed, guidance: songkranGuidance
                ))
            case "JP":
                spans.append(RhythmSpan(
                    kind: .goldenWeek, name: "Golden Week",
                    first: CivilDate(year: year, month: 4, day: 29), dayCount: 7,
                    confidence: .fixed, guidance: goldenWeekGuidance
                ))
            case "IT":
                spans.append(RhythmSpan(
                    kind: .ferragosto, name: "Ferragosto",
                    first: CivilDate(year: year, month: 8, day: 15), dayCount: 1,
                    confidence: .fixed, guidance: ferragostoGuidance
                ))
            case "ID":
                if let date = nyepiDates[year] {
                    spans.append(RhythmSpan(
                        kind: .nyepi, name: "Nyepi (Bali Day of Silence)",
                        first: CivilDate(year: year, month: date.month, day: date.day), dayCount: 1,
                        confidence: .computed, guidance: nyepiGuidance
                    ))
                }
            default:
                break
            }
        }

        return spans
    }

    private static func islamicSpans(style: RamadanStyle, years: ClosedRange<Int>) -> [RhythmSpan] {
        guard let firstJan = gregorian.date(from: DateComponents(year: years.lowerBound, month: 1, day: 1, hour: 12)),
              let lastDec = gregorian.date(from: DateComponents(year: years.upperBound, month: 12, day: 31, hour: 12))
        else {
            return []
        }
        let hijriYears = islamic.component(.year, from: firstJan)...islamic.component(.year, from: lastDec)

        var spans: [RhythmSpan] = []
        for hijriYear in hijriYears {
            if let first = civilDate(in: islamic, year: hijriYear, month: 9, day: 1),
               let shawwal = civilDate(in: islamic, year: hijriYear, month: 10, day: 1) {
                spans.append(RhythmSpan(
                    kind: .ramadan, name: "Ramadan", first: first,
                    dayCount: shawwal.dayNumber - first.dayNumber,
                    confidence: .expected, guidance: ramadanGuidance(style)
                ))
                spans.append(RhythmSpan(
                    kind: .eidAlFitr, name: "Eid al-Fitr", first: shawwal, dayCount: 3,
                    confidence: .expected, guidance: eidAlFitrGuidance
                ))
            }
            if let adha = civilDate(in: islamic, year: hijriYear, month: 12, day: 10) {
                spans.append(RhythmSpan(
                    kind: .eidAlAdha, name: "Eid al-Adha", first: adha, dayCount: 4,
                    confidence: .expected, guidance: eidAlAdhaGuidance
                ))
            }
        }
        return spans
    }

    private static func lunarNewYearSpans(rule: LunarNewYearRule, years: ClosedRange<Int>) -> [RhythmSpan] {
        years.compactMap { year in
            lunarNewYear(inGregorianYear: year).map { newYear in
                RhythmSpan(
                    kind: .lunarNewYear, name: rule.name,
                    first: newYear.adding(days: rule.firstDayOffset), dayCount: rule.dayCount,
                    confidence: .computed, guidance: rule.guidance
                )
            }
        }
    }

    /// First day of the first lunar month in a Gregorian year; it always falls between 21 Jan and 21 Feb.
    private static func lunarNewYear(inGregorianYear year: Int) -> CivilDate? {
        guard var date = gregorian.date(from: DateComponents(year: year, month: 1, day: 19, hour: 12)) else {
            return nil
        }
        for _ in 0..<40 {
            let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
            if parts.month == 1, parts.day == 1, parts.isLeapMonth != true {
                let civil = gregorian.dateComponents([.year, .month, .day], from: date)
                guard let y = civil.year, let m = civil.month, let d = civil.day else { return nil }
                return CivilDate(year: y, month: m, day: d)
            }
            guard let next = gregorian.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }
        return nil
    }

    private static func holyWeekSpans(country: String, years: ClosedRange<Int>) -> [RhythmSpan] {
        years.map { year in
            let easter = westernEaster(year: year)
            return RhythmSpan(
                kind: .holyWeek, name: holyWeekName(country),
                first: easter.adding(days: -7), dayCount: 8,
                confidence: .computed, guidance: holyWeekGuidance(country)
            )
        }
    }

    private static func diwaliSpans(rule: DiwaliRule, years: ClosedRange<Int>) -> [RhythmSpan] {
        years.compactMap { year in
            rule.dates[year].map { date in
                RhythmSpan(
                    kind: .diwali, name: rule.name,
                    first: CivilDate(year: year, month: date.month, day: date.day).adding(days: rule.firstDayOffset),
                    dayCount: rule.dayCount, confidence: rule.confidence, guidance: rule.guidance
                )
            }
        }
    }

    /// Western Easter Sunday by the Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    private static func westernEaster(year: Int) -> CivilDate {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return CivilDate(year: year, month: month, day: day)
    }
}
