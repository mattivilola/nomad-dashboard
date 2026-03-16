import Foundation
import NomadCore
import Testing

@MainActor
struct AppAnalyticsTests {
    @Test
    func firstLaunchTracksInstallAndLaunch() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let analytics = analytics(defaults: defaults, keyPrefix: "first-launch", client: recorder, now: day(2026, 3, 16))

        analytics.recordAppLaunch()

        #expect(recorder.events.map(\.event) == [.appInstallFirstSeen, .appLaunch])
    }

    @Test
    func relaunchTracksLaunchOnlyAfterFirstSeen() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let analytics = analytics(defaults: defaults, keyPrefix: "relaunch", client: recorder, now: day(2026, 3, 16))

        analytics.recordAppLaunch()
        analytics.recordAppLaunch()

        #expect(recorder.events.map(\.event) == [.appInstallFirstSeen, .appLaunch, .appLaunch])
    }

    @Test
    func activeDayTracksOncePerLocalDay() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let keyPrefix = "active-day"

        let firstDayAnalytics = analytics(defaults: defaults, keyPrefix: keyPrefix, client: recorder, now: day(2026, 3, 16))
        firstDayAnalytics.recordPrimaryUIOpened(analyticsEnabled: true)
        firstDayAnalytics.recordPrimaryUIOpened(analyticsEnabled: true)

        let secondDayAnalytics = analytics(defaults: defaults, keyPrefix: keyPrefix, client: recorder, now: day(2026, 3, 17))
        secondDayAnalytics.recordSettingsOpened(analyticsEnabled: true)

        #expect(recorder.events.map(\.event) == [
            .appActiveDay,
            .primaryUIOpened,
            .primaryUIOpened,
            .appActiveDay,
            .settingsOpened
        ])
    }

    @Test
    func backgroundActiveDayTracksOncePerLocalDay() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let keyPrefix = "background-day"

        let firstDayAnalytics = analytics(defaults: defaults, keyPrefix: keyPrefix, client: recorder, now: day(2026, 3, 16))
        firstDayAnalytics.recordBackgroundActiveDay()
        firstDayAnalytics.recordBackgroundActiveDay()

        let secondDayAnalytics = analytics(defaults: defaults, keyPrefix: keyPrefix, client: recorder, now: day(2026, 3, 17))
        secondDayAnalytics.recordBackgroundActiveDay()

        #expect(recorder.events.map(\.event) == [
            .appBackgroundActiveDay,
            .appBackgroundActiveDay
        ])
    }

    @Test
    func disabledAnalyticsSuppressesGatedEventsButNotLaunch() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let analytics = analytics(defaults: defaults, keyPrefix: "disabled", client: recorder, now: day(2026, 3, 16))

        analytics.recordPrimaryUIOpened(analyticsEnabled: false)
        analytics.recordSettingsOpened(analyticsEnabled: false)
        analytics.recordAppLaunch()

        #expect(recorder.events.map(\.event) == [.appInstallFirstSeen, .appLaunch])
    }

    @Test
    func backgroundActiveDayIsNotBlockedByDisabledUIAnalytics() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let analytics = analytics(defaults: defaults, keyPrefix: "background-with-disabled-ui", client: recorder, now: day(2026, 3, 16))

        analytics.recordPrimaryUIOpened(analyticsEnabled: false)
        analytics.recordBackgroundActiveDay()

        #expect(recorder.events.map(\.event) == [.appBackgroundActiveDay])
    }

    @Test
    func reEnablingAnalyticsResumesGatedEventsWithoutDuplicatingInstall() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let keyPrefix = "reenable"

        let disabledAnalytics = analytics(defaults: defaults, keyPrefix: keyPrefix, client: recorder, now: day(2026, 3, 16))
        disabledAnalytics.recordAppLaunch()
        disabledAnalytics.recordPrimaryUIOpened(analyticsEnabled: false)

        let enabledAnalytics = analytics(defaults: defaults, keyPrefix: keyPrefix, client: recorder, now: day(2026, 3, 17))
        enabledAnalytics.recordAppLaunch()
        enabledAnalytics.recordPrimaryUIOpened(analyticsEnabled: true)

        #expect(recorder.events.map(\.event) == [
            .appInstallFirstSeen,
            .appLaunch,
            .appLaunch,
            .appActiveDay,
            .primaryUIOpened
        ])
    }

    @Test
    func backgroundActiveDayDoesNotInterfereWithLaunchOrUIActivityMarkers() throws {
        let defaults = try isolatedDefaults()
        let recorder = RecordingAnalyticsClient()
        let analytics = analytics(defaults: defaults, keyPrefix: "independent-markers", client: recorder, now: day(2026, 3, 16))

        analytics.recordAppLaunch()
        analytics.recordBackgroundActiveDay()
        analytics.recordPrimaryUIOpened(analyticsEnabled: true)

        #expect(recorder.events.map(\.event) == [
            .appInstallFirstSeen,
            .appLaunch,
            .appBackgroundActiveDay,
            .appActiveDay,
            .primaryUIOpened
        ])
    }

    private func analytics(
        defaults: UserDefaults,
        keyPrefix: String,
        client: some AnalyticsClient,
        now: Date
    ) -> AppAnalytics {
        AppAnalytics(
            client: client,
            defaults: defaults,
            keyPrefix: keyPrefix,
            calendar: Calendar(identifier: .gregorian),
            now: { now }
        )
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day, hour: 12)
        return components.date!
    }
}

@MainActor
private final class RecordingAnalyticsClient: @unchecked Sendable, AnalyticsClient {
    struct EventRecord: Sendable, Equatable {
        let event: AnalyticsEvent
        let properties: [String: String]
    }

    private(set) var events: [EventRecord] = []

    func track(_ event: AnalyticsEvent, properties: [String: String]) {
        events.append(EventRecord(event: event, properties: properties))
    }
}
