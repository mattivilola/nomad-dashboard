import Foundation
@testable import NomadCore
@testable import NomadUI
import Testing

// MARK: Sparkline

struct SparklinePresentationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func points(_ values: [Double], every interval: TimeInterval = 60) -> [MetricPoint] {
        values.enumerated().map { index, value in
            MetricPoint(timestamp: start.addingTimeInterval(Double(index) * interval), value: value)
        }
    }

    @Test
    func fewerThanThreePointsCollectAndExplainThemselves() {
        let presentation = SparklinePresentation(points: points([10, 12]), title: "Latency")

        #expect(presentation.kind == .collecting)
        #expect(presentation.samples.isEmpty)
        #expect(presentation.helpText == "Collecting trend…")
        #expect(presentation.accessibilityLabel == "Latency: Collecting trend…")
    }

    @Test
    func aFlatSeriesIsSteadyNotCollecting() {
        let presentation = SparklinePresentation(
            points: points([100, 100, 100, 100]),
            title: "Charge",
            format: { String(format: "%.0f%%", $0) }
        )

        #expect(presentation.kind == .steady)
        #expect(presentation.helpText == "Last 3 min · steady at 100%")
    }

    @Test
    func aTrendNormalizesIntoTheUnitSquare() {
        let presentation = SparklinePresentation(
            points: points([20, 40, 30, 10], every: 120),
            title: "Latency",
            format: { String(format: "%.0f ms", $0) }
        )

        #expect(presentation.kind == .trend)
        #expect(presentation.minimum == 10)
        #expect(presentation.maximum == 40)
        #expect(presentation.latest == 10)
        #expect(presentation.samples.count == 4)
        #expect(presentation.samples.first == CGPoint(x: 0, y: (20.0 - 10) / 30))
        #expect(presentation.samples.last == CGPoint(x: 1, y: 0))
        #expect(presentation.samples.map(\.y).max() == 1)
        #expect(presentation.helpText == "Last 6 min · min 10 ms · max 40 ms · now 10 ms")
        #expect(presentation.accessibilityLabel == "Latency over the last 6 min: minimum 10 ms, maximum 40 ms, latest 10 ms")
    }

    @Test
    func pointsAreOrderedByTimeBeforeDrawing() {
        let shuffled = [
            MetricPoint(timestamp: start.addingTimeInterval(120), value: 3),
            MetricPoint(timestamp: start, value: 1),
            MetricPoint(timestamp: start.addingTimeInterval(60), value: 2)
        ]
        let presentation = SparklinePresentation(points: shuffled)

        #expect(presentation.samples.map(\.y) == [0, 0.5, 1])
        #expect(presentation.latest == 3)
    }

    @Test
    func timeSpansUseTheCoarsestReadableUnit() {
        #expect(SparklinePresentation.spanText(0) == "1 s")
        #expect(SparklinePresentation.spanText(45) == "45 s")
        #expect(SparklinePresentation.spanText(8 * 60) == "8 min")
        #expect(SparklinePresentation.spanText(89 * 60) == "89 min")
        #expect(SparklinePresentation.spanText(2 * 3_600) == "2 h")
        #expect(SparklinePresentation.spanText(2.5 * 3_600) == "2.5 h")
    }
}

// MARK: Card packing

struct DashboardCardPackingTests {
    @Test
    func twoAdjacentNarrowCardsShareARowAtHalfWidth() {
        let rows = DashboardCardPacking.rows(
            order: [.connectivity, .power, .weather],
            widthModes: [.connectivity: .narrow, .power: .narrow]
        )

        #expect(rows.count == 2)
        #expect(rows[0].items.map(\.cardID) == [.connectivity, .power])
        #expect(rows[0].items.map(\.renderWidth) == [.half, .half])
        #expect(rows[0].items.map(\.layoutWidthMode) == [.narrow, .narrow])
    }

    @Test
    func aNarrowCardWithoutANarrowPartnerRendersWideAtFullWidthButKeepsItsPreference() {
        let rows = DashboardCardPacking.rows(
            order: [.connectivity, .power],
            widthModes: [.connectivity: .narrow, .power: .wide]
        )

        #expect(rows.count == 2)
        let lone = rows[0].items[0]
        #expect(lone.cardID == .connectivity)
        #expect(lone.renderWidth == .full)
        #expect(lone.layoutWidthMode == .wide)
        #expect(lone.preferredWidthMode == .narrow)
    }

    @Test
    func aTrailingNarrowCardRendersWide() {
        let rows = DashboardCardPacking.rows(
            order: [.connectivity, .power],
            widthModes: [.power: .narrow]
        )

        #expect(rows.map(\.items.count) == [1, 1])
        #expect(rows[1].items[0].layoutWidthMode == .wide)
    }

    @Test
    func threeNarrowCardsPackAPairAndLeaveTheThirdWide() {
        let rows = DashboardCardPacking.rows(
            order: [.connectivity, .power, .weather],
            widthModes: [.connectivity: .narrow, .power: .narrow, .weather: .narrow]
        )

        #expect(rows.map(\.items.count) == [2, 1])
        #expect(rows[1].items[0].cardID == .weather)
        #expect(rows[1].items[0].layoutWidthMode == .wide)
    }

    @Test
    func cardsDefaultToWide() {
        let rows = DashboardCardPacking.rows(order: [.connectivity, .power], widthModes: [:])

        #expect(rows.map(\.items.count) == [1, 1])
        #expect(rows.flatMap(\.items).allSatisfy { $0.layoutWidthMode == .wide })
    }
}

// MARK: Time tracking allocation

struct TimeTrackingAllocationPresentationTests {
    private func summary(
        buckets: [TimeTrackingBucketDuration],
        unallocated: TimeInterval,
        interruptions: Int = 0
    ) -> TimeTrackingDaySummary {
        let allocated = buckets.filter { $0.bucket != .unallocated }.reduce(0) { $0 + $1.duration }
        let focusLoss = TimeTrackingFocusMetrics.estimatedFocusLoss(for: interruptions)
        return TimeTrackingDaySummary(
            dayStart: Date(timeIntervalSinceReferenceDate: 800_000_000),
            bucketDurations: buckets,
            totalTrackedDuration: allocated + unallocated,
            totalAllocatedDuration: allocated,
            unallocatedDuration: unallocated,
            interruptionCount: interruptions,
            estimatedFocusLossDuration: focusLoss,
            focusAdjustedDuration: max(allocated + unallocated - focusLoss, 0),
            lastInterruptionAt: nil
        )
    }

    private func title(_ bucket: TimeTrackingBucket) -> String {
        switch bucket {
        case .project:
            "Project"
        case .other:
            "Other"
        case .unallocated:
            "Unallocated"
        }
    }

    @Test
    func barSegmentsSplitAllocatedBucketsAndThePendingRemainder() {
        let projectID = UUID()
        let presentation = TimeTrackingAllocationPresentation(
            summary: summary(
                buckets: [
                    TimeTrackingBucketDuration(bucket: .project(projectID), duration: 3 * 3_600),
                    TimeTrackingBucketDuration(bucket: .other, duration: 1 * 3_600),
                    TimeTrackingBucketDuration(bucket: .unallocated, duration: 4 * 3_600)
                ],
                unallocated: 4 * 3_600
            ),
            bucketTitle: title
        )

        #expect(presentation.segments.map(\.title) == ["Project", "Other", "Pending"])
        #expect(presentation.segments.map(\.fraction) == [0.375, 0.125, 0.5])
        #expect(presentation.segments.map(\.kind) == [.allocated(toneIndex: 0), .allocated(toneIndex: 1), .pending])
        #expect(presentation.legend.map(\.durationText) == ["3h", "1h", "4h"])
        #expect(presentation.hiddenLegendCount == 0)
        #expect(presentation.barHelpText == "Allocated 4h of 8h tracked today · 4h pending")
    }

    @Test
    func legendShowsAtMostFourBucketsAndCountsTheRest() {
        let buckets = (1...6).map {
            TimeTrackingBucketDuration(bucket: .project(UUID()), duration: Double(7 - $0) * 600)
        }
        let presentation = TimeTrackingAllocationPresentation(
            summary: summary(buckets: buckets, unallocated: 0),
            bucketTitle: title
        )

        #expect(presentation.legend.count == TimeTrackingAllocationPresentation.maxLegendEntries)
        #expect(presentation.hiddenLegendCount == 2)
        // Every allocated bucket still has its bar segment, only the legend is capped.
        #expect(presentation.segments.count == 6)
    }

    @Test
    func emptyDayHasNoSegmentsAndNoLegend() {
        let presentation = TimeTrackingAllocationPresentation(
            summary: summary(buckets: [], unallocated: 0),
            bucketTitle: title
        )

        #expect(presentation.segments.isEmpty)
        #expect(presentation.legend.isEmpty)
        #expect(presentation.focusLossCaption == nil)
    }

    @Test
    func interruptionsAreSummarisedAsLostFocusAndDetailedPerBucket() {
        let presentation = TimeTrackingAllocationPresentation(
            summary: summary(
                buckets: [TimeTrackingBucketDuration(bucket: .other, duration: 2 * 3_600, interruptionCount: 1)],
                unallocated: 0,
                interruptions: 1
            ),
            bucketTitle: title
        )

        let lost = TimeTrackingDurationFormatting.text(TimeTrackingFocusMetrics.estimatedFocusLoss(for: 1))
        #expect(presentation.focusLossCaption == "≈\(lost) focus lost")
        #expect(presentation.legend.first?.helpText.contains("1 interruption") == true)
    }

    @Test
    func durationsDropEmptyParts() {
        #expect(TimeTrackingDurationFormatting.text(42 * 60) == "42m")
        #expect(TimeTrackingDurationFormatting.text(3 * 3_600) == "3h")
        #expect(TimeTrackingDurationFormatting.text(6 * 3_600 + 58 * 60) == "6h 58m")
    }
}

// MARK: Travel context

struct TravelContextPresentationTests {
    private func location(city: String? = "Valencia", country: String? = "Spain") -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: city,
            region: nil,
            country: country,
            countryCode: "ES",
            latitude: nil,
            longitude: nil,
            timeZone: "Europe/Madrid",
            provider: "test",
            fetchedAt: .now
        )
    }

    private func context(
        wifi: WiFiSnapshot? = nil,
        vpn: VPNStatusSnapshot? = nil,
        publicIP: String? = "203.0.113.42",
        location: IPLocationSnapshot? = nil
    ) -> TravelContextSnapshot {
        TravelContextSnapshot(
            wifi: wifi,
            vpn: vpn,
            timeZoneIdentifier: "Europe/Madrid",
            deviceLocation: nil,
            publicIP: publicIP.map { PublicIPSnapshot(address: $0, provider: "test", fetchedAt: .now) },
            location: location
        )
    }

    @Test
    func wifiNameSignalAndRateShareOneRow() {
        let presentation = TravelContextPresentation(
            travelContext: context(
                wifi: WiFiSnapshot(interfaceName: "en0", ssid: "Nomad Hub", rssi: -56, noise: -91, transmitRateMbps: 720)
            ),
            issues: [],
            isPublicIPLocationEnabled: true
        )

        #expect(presentation.wifi == "Nomad Hub · \u{2212}56 dBm · 720 Mbps")
        #expect(presentation.wifiHelp == "Signal \u{2212}56 dBm · Noise \u{2212}91 dBm · Transmit rate 720 Mbps")
    }

    @Test
    func wifiWithoutNameOrSnapshotStaysHonest() {
        let unnamed = TravelContextPresentation(
            travelContext: context(wifi: WiFiSnapshot(interfaceName: "en0", ssid: nil, rssi: -60, noise: nil, transmitRateMbps: nil)),
            issues: [],
            isPublicIPLocationEnabled: true
        )
        #expect(unnamed.wifi == "Connected · \u{2212}60 dBm")

        let none = TravelContextPresentation(travelContext: context(), issues: [], isPublicIPLocationEnabled: true)
        #expect(none.wifi == "Not connected")
        #expect(none.wifiHelp == nil)
    }

    @Test
    func vpnShowsServiceNamesThenInterfacesThenActive() {
        func vpn(_ snapshot: VPNStatusSnapshot?) -> String {
            TravelContextPresentation(travelContext: context(vpn: snapshot), issues: [], isPublicIPLocationEnabled: true).vpn
        }

        #expect(vpn(nil) == "Inactive")
        #expect(vpn(VPNStatusSnapshot(isActive: false, interfaceNames: ["utun3"])) == "Inactive")
        #expect(vpn(VPNStatusSnapshot(isActive: true, interfaceNames: ["utun3"], serviceNames: ["Mullvad"])) == "Mullvad")
        #expect(vpn(VPNStatusSnapshot(isActive: true, interfaceNames: ["utun3"])) == "utun3")
        #expect(vpn(VPNStatusSnapshot(isActive: true, interfaceNames: [])) == "Active")
    }

    @Test
    func locationCarriesTheTimeZone() {
        let resolved = TravelContextPresentation(
            travelContext: context(location: location()),
            issues: [],
            isPublicIPLocationEnabled: true
        )
        #expect(resolved.location == "Valencia, Spain · Europe/Madrid")

        let off = TravelContextPresentation(travelContext: context(), issues: [], isPublicIPLocationEnabled: false)
        #expect(off.location == "Location off · Europe/Madrid")

        let failed = TravelContextPresentation(
            travelContext: context(),
            issues: [.ipLocationUnavailable],
            isPublicIPLocationEnabled: true
        )
        #expect(failed.location == "Lookup unavailable · Europe/Madrid")
    }

    @Test
    func publicIPFallsBackToStatusText() {
        let known = TravelContextPresentation(travelContext: context(), issues: [], isPublicIPLocationEnabled: true)
        #expect(known.publicIP == "203.0.113.42")
        #expect(known.hasPublicIP)

        let missing = TravelContextPresentation(
            travelContext: context(publicIP: nil),
            issues: [.publicIPLookupUnavailable],
            isPublicIPLocationEnabled: true
        )
        #expect(missing.publicIP == "Lookup unavailable")
        #expect(missing.hasPublicIP == false)

        let refreshing = TravelContextPresentation(
            travelContext: context(publicIP: nil),
            issues: [],
            isPublicIPLocationEnabled: true
        )
        #expect(refreshing.publicIP == "Refreshing…")
    }
}

// MARK: Local info

struct LocalInfoCompactRowsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2_026, month: 10, day: 12, hour: 12)) ?? .now
    }

    private func date(_ month: Int, _ day: Int, year: Int = 2_026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    private func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func presentation(
        status: LocalInfoStatus = .ready,
        publicHoliday: LocalHolidayStatus,
        schoolHoliday: LocalHolidayStatus? = nil,
        prices: LocalPriceLevelSnapshot? = nil,
        detail: String? = nil
    ) -> LocalInfoSectionPresentation {
        var settings = AppSettings()
        settings.localInfoEnabled = true

        let localInfo = LocalInfoSnapshot(
            status: status,
            locality: "Valencia",
            administrativeRegion: "Valencian Community",
            countryCode: "ES",
            countryName: "Spain",
            timeZoneIdentifier: "Europe/Madrid",
            subdivisionCode: nil,
            publicHolidayStatus: publicHoliday,
            schoolHolidayStatus: schoolHoliday,
            localPriceLevel: prices,
            sources: [HolidaySourceAttribution(name: "Nager.Date", url: nil)],
            fetchedAt: .now,
            detail: detail,
            note: nil
        )
        let base = DashboardSnapshot.preview
        let snapshot = DashboardSnapshot(
            network: base.network,
            power: base.power,
            travelContext: base.travelContext,
            travelAlerts: base.travelAlerts,
            weather: base.weather,
            localInfo: localInfo,
            marine: base.marine,
            appState: base.appState
        )

        return LocalInfoSectionPresentation(
            settings: settings,
            snapshot: snapshot,
            locationStatusDetail: nil,
            now: now,
            calendar: calendar
        )
    }

    private func upcoming(_ name: String, from start: Date, to end: Date? = nil) -> LocalHolidayStatus {
        LocalHolidayStatus(
            state: .upcoming,
            currentPeriod: nil,
            nextPeriod: HolidayPeriodSnapshot(name: name, startDate: start, endDate: end ?? start),
            note: nil
        )
    }

    private func priceRow(
        _ kind: LocalPriceIndicatorKind,
        value: String,
        detail: String,
        difference: Double? = nil
    ) -> LocalPriceIndicatorRow {
        LocalPriceIndicatorRow(
            kind: kind,
            value: value,
            detail: detail,
            precision: .countryFallback,
            source: LocalPriceSourceAttribution(name: "Eurostat", url: nil),
            differenceFromEUPercent: difference
        )
    }

    @Test
    func publicHolidayValueCarriesTheDateAndCountdown() throws {
        let start = date(10, 24)
        let result = presentation(publicHoliday: upcoming("Labour Day", from: start))
        let row = try #require(result.rows.first(where: { $0.id == "public-holiday" }))

        #expect(row.value == "\(day(start)) · in 12 days")
        #expect(row.detail == "Labour Day")
    }

    @Test
    func publicHolidayTomorrowSaysTomorrow() throws {
        let start = date(10, 13)
        let result = presentation(publicHoliday: upcoming("Labour Day", from: start))
        let row = try #require(result.rows.first { $0.id == "public-holiday" })

        #expect(row.value == "\(day(start)) · tomorrow")
    }

    @Test
    func schoolBreakValueIsTheDateRange() throws {
        let start = date(12, 21)
        let end = date(3, 1, year: 2_027)
        let result = presentation(
            publicHoliday: upcoming("Labour Day", from: date(10, 24)),
            schoolHoliday: upcoming("Summer holidays", from: start, to: end)
        )
        let row = try #require(result.rows.first(where: { $0.id == "school-holiday" }))

        #expect(row.value == "\(day(start)) – \(day(end))")
        #expect(row.detail == "Summer holidays")
    }

    @Test
    func euPriceIndicatorsCollapseIntoOnePricesRow() throws {
        let prices = LocalPriceLevelSnapshot(
            status: .ready,
            summaryBand: .medium,
            countryCode: "ES",
            countryName: "Spain",
            rows: [
                priceRow(.mealOut, value: "Moderate", detail: "ignored", difference: -4),
                priceRow(.groceries, value: "Moderate", detail: "ignored", difference: 3),
                priceRow(.overall, value: "Below Avg", detail: "ignored", difference: -1)
            ],
            sources: [],
            fetchedAt: .now,
            detail: nil,
            note: nil
        )
        let result = presentation(publicHoliday: upcoming("Labour Day", from: date(10, 24)), prices: prices)
        let priceRows = result.rows.filter { $0.id.hasPrefix("price") }

        #expect(priceRows.count == 1)
        let row = try #require(priceRows.first)
        #expect(row.title == "Prices vs EU")
        #expect(row.value == "Below Avg")
        #expect(row.detail == "Meals \u{2212}4% · Groceries +3% · Overall ≈ EU")
        #expect(row.help == "Country fallback · Eurostat")
    }

    @Test
    func pricesRowFallsBackToTheSummaryBandWithoutAnOverallIndicator() throws {
        let prices = LocalPriceLevelSnapshot(
            status: .partial,
            summaryBand: .high,
            countryCode: "ES",
            countryName: "Spain",
            rows: [priceRow(.mealOut, value: "Above Avg", detail: "4% above EU average")],
            sources: [],
            fetchedAt: .now,
            detail: nil,
            note: nil
        )
        let result = presentation(publicHoliday: upcoming("Labour Day", from: date(10, 24)), prices: prices)
        let row = try #require(result.rows.first(where: { $0.id == "prices-vs-eu" }))

        #expect(row.value == "High")
        #expect(row.detail == "Meals Above Avg")
    }

    @Test
    func rentBenchmarkKeepsItsOwnValueAndDetailRow() throws {
        let prices = LocalPriceLevelSnapshot(
            status: .partial,
            summaryBand: .limited,
            countryCode: "US",
            countryName: "United States",
            rows: [priceRow(.rentOneBedroom, value: "$1,450/mo", detail: "Metro benchmark · Austin · 2025")],
            sources: [],
            fetchedAt: .now,
            detail: nil,
            note: nil
        )
        let result = presentation(publicHoliday: upcoming("Labour Day", from: date(10, 24)), prices: prices)
        let row = try #require(result.rows.first(where: { $0.title == "1BR Rent" }))

        #expect(row.value == "$1,450/mo")
        #expect(row.detail == "Metro benchmark · Austin · 2025")
        #expect(result.rows.contains(where: { $0.id == "prices-vs-eu" }) == false)
    }

    @Test
    func locationMovesIntoTheSubtitleAndHealthyCardsDropFillerText() {
        let result = presentation(
            publicHoliday: upcoming("Labour Day", from: date(10, 24)),
            detail: "Compact local context with holidays and price signals."
        )

        #expect(result.subtitle == "Valencia · Valencian Community, Spain · Europe/Madrid")
        #expect(result.rows.contains(where: { $0.title == "Location" }) == false)
        #expect(result.note == nil)
        #expect(result.sourceLine == "Sources: Nager.Date")
    }

    @Test
    func degradedCardsKeepTheirExplanation() {
        let result = presentation(
            status: .partial,
            publicHoliday: upcoming("Labour Day", from: date(10, 24)),
            detail: "Some local signals are limited right now."
        )

        #expect(result.note == "Some local signals are limited right now.")
    }
}

// MARK: Metric values

struct FormattedMetricTests {
    @Test
    func formattersReturnNumberAndUnitApart() {
        #expect(NomadFormatters.megabitsPerSecondParts(96) == FormattedMetric(number: "96.0", unit: "Mbps"))
        #expect(NomadFormatters.latencyParts(28.4) == FormattedMetric(number: "28", unit: "ms"))
        #expect(NomadFormatters.wattsParts(11.44) == FormattedMetric(number: "11.4", unit: "W"))
    }

    @Test
    func missingValuesHaveNoUnit() {
        #expect(NomadFormatters.megabitsPerSecondParts(nil) == FormattedMetric(number: "n/a"))
        #expect(NomadFormatters.latencyParts(nil).unit == nil)
        #expect(NomadFormatters.wattsParts(nil).unit == nil)
    }

    @Test
    func plainStringFormattersStayInSync() {
        #expect(NomadFormatters.megabitsPerSecond(96) == "96.0 Mbps")
        #expect(NomadFormatters.latency(28) == "28 ms")
        #expect(NomadFormatters.watts(11.4) == "11.4 W")
        #expect(NomadFormatters.megabitsPerSecond(nil) == "n/a")
        #expect(FormattedMetric(number: "5").text == "5")
    }
}
