import Foundation
import NomadCore
import Testing

struct MeteredUsageOutlookTests {
    private let gigabyte: UInt64 = 1_024 * 1_024 * 1_024
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test
    func usedBytesFollowsTheBillingPeriod() {
        let session = makeSnapshot(billingPeriod: .session, sessionBytes: 3, periodBytes: 7)
        let month = makeSnapshot(billingPeriod: .calendarMonth, sessionBytes: 3, periodBytes: 7)
        let manual = makeSnapshot(billingPeriod: .manual, sessionBytes: 3, periodBytes: 7)

        #expect(session.usedBytes == 3)
        #expect(month.usedBytes == 7)
        #expect(manual.usedBytes == 7)
    }

    @Test
    func remainingBytesSubtractsUsageFromTheCap() {
        let snapshot = makeSnapshot(billingPeriod: .session, sessionBytes: 2 * gigabyte, capBytes: 5 * gigabyte)

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: now).remainingBytes == 3 * gigabyte)
    }

    @Test
    func remainingBytesFloorsAtZeroWhenOverTheCap() {
        let snapshot = makeSnapshot(billingPeriod: .session, sessionBytes: 6 * gigabyte, capBytes: 5 * gigabyte)

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: now).remainingBytes == 0)
    }

    @Test
    func withoutACapThereIsNoRemainingAndNoEstimate() {
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: gigabyte,
            capBytes: nil,
            sessionStartedAt: now.addingTimeInterval(-86_400)
        )
        let outlook = MeteredUsageOutlook(snapshot: snapshot, now: now)

        #expect(outlook.remainingBytes == nil)
        #expect(outlook.estimatedDaysLeft == nil)
    }

    @Test
    func calendarMonthResetsAtTheStartOfNextMonth() throws {
        let calendar = utcCalendar
        let midMonth = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9)))
        let expected = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let snapshot = makeSnapshot(billingPeriod: .calendarMonth, periodBytes: gigabyte, capBytes: 5 * gigabyte)

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: midMonth, calendar: calendar).resetsAt == expected)
    }

    @Test
    func calendarMonthResetRollsOverTheYear() throws {
        let calendar = utcCalendar
        let december = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23)))
        let expected = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let snapshot = makeSnapshot(billingPeriod: .calendarMonth, periodBytes: gigabyte, capBytes: 5 * gigabyte)

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: december, calendar: calendar).resetsAt == expected)
    }

    @Test
    func sessionAndManualPeriodsNeverReset() {
        let session = makeSnapshot(billingPeriod: .session, sessionBytes: gigabyte, capBytes: 5 * gigabyte)
        let manual = makeSnapshot(billingPeriod: .manual, periodBytes: gigabyte, capBytes: 5 * gigabyte)

        #expect(MeteredUsageOutlook(snapshot: session, now: now).resetsAt == nil)
        #expect(MeteredUsageOutlook(snapshot: manual, now: now).resetsAt == nil)
    }

    @Test
    func sessionEstimateUsesSessionPace() throws {
        // 1 GB in 2 days leaves 4 GB of a 5 GB cap, which lasts 8 more days.
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: gigabyte,
            capBytes: 5 * gigabyte,
            sessionStartedAt: now.addingTimeInterval(-2 * 86_400),
            periodStartedAt: now.addingTimeInterval(-20 * 86_400)
        )
        let days = try #require(MeteredUsageOutlook(snapshot: snapshot, now: now).estimatedDaysLeft)

        #expect(abs(days - 8) < 0.0001)
    }

    @Test
    func periodEstimateUsesPeriodStart() throws {
        // 2 GB in 4 days leaves 3 GB of a 5 GB cap, which lasts 6 more days.
        let snapshot = makeSnapshot(
            billingPeriod: .calendarMonth,
            sessionBytes: 9 * gigabyte,
            periodBytes: 2 * gigabyte,
            capBytes: 5 * gigabyte,
            sessionStartedAt: now.addingTimeInterval(-86_400),
            periodStartedAt: now.addingTimeInterval(-4 * 86_400)
        )
        let days = try #require(MeteredUsageOutlook(snapshot: snapshot, now: now).estimatedDaysLeft)

        #expect(abs(days - 6) < 0.0001)
    }

    @Test
    func estimateIsNilWithoutAStartDate() {
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: gigabyte,
            capBytes: 5 * gigabyte,
            sessionStartedAt: nil
        )

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: now).estimatedDaysLeft == nil)
    }

    @Test
    func estimateIsNilWhenLessThanAnHourHasElapsed() {
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: gigabyte,
            capBytes: 5 * gigabyte,
            sessionStartedAt: now.addingTimeInterval(-3_599)
        )

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: now).estimatedDaysLeft == nil)
    }

    @Test
    func estimateStartsAtExactlyOneHour() throws {
        // 1 GB in one hour is 24 GB per day, so 4 GB remaining lasts 1/6 day.
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: gigabyte,
            capBytes: 5 * gigabyte,
            sessionStartedAt: now.addingTimeInterval(-3_600)
        )
        let days = try #require(MeteredUsageOutlook(snapshot: snapshot, now: now).estimatedDaysLeft)

        #expect(abs(days - 1.0 / 6.0) < 0.0001)
    }

    @Test
    func estimateIsNilWhenNothingWasUsed() {
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: 0,
            capBytes: 5 * gigabyte,
            sessionStartedAt: now.addingTimeInterval(-86_400)
        )
        let outlook = MeteredUsageOutlook(snapshot: snapshot, now: now)

        #expect(outlook.estimatedDaysLeft == nil)
        #expect(outlook.remainingBytes == 5 * gigabyte)
    }

    @Test
    func estimateIsZeroOnceTheCapIsExhausted() {
        let snapshot = makeSnapshot(
            billingPeriod: .session,
            sessionBytes: 5 * gigabyte,
            capBytes: 5 * gigabyte,
            sessionStartedAt: now.addingTimeInterval(-86_400)
        )

        #expect(MeteredUsageOutlook(snapshot: snapshot, now: now).estimatedDaysLeft == 0)
    }

    private func makeSnapshot(
        billingPeriod: MeteredBillingPeriod,
        sessionBytes: UInt64 = 0,
        periodBytes: UInt64 = 0,
        capBytes: UInt64? = nil,
        sessionStartedAt: Date? = nil,
        periodStartedAt: Date? = nil
    ) -> MeteredUsageSnapshot {
        MeteredUsageSnapshot(
            isFeatureEnabled: true,
            isMonitoringActive: true,
            networkKey: "wifi:Hotspot",
            networkDisplayName: "Hotspot",
            meteredInterfaceName: "en0",
            sessionStartedAt: sessionStartedAt,
            sessionBytesReceived: sessionBytes,
            sessionBytesSent: 0,
            periodStartedAt: periodStartedAt,
            periodBytesReceived: periodBytes,
            periodBytesSent: 0,
            capBytes: capBytes,
            usageFraction: nil,
            isCapReached: false,
            billingPeriod: billingPeriod,
            manualSessionEnabled: false,
            isKnownMeteredNetwork: true,
            networkNameSource: .liveSSID,
            isWiFiConnected: true,
            needsLocationForWiFiNames: false,
            statusMessage: nil,
            capAlertSignal: nil
        )
    }
}
