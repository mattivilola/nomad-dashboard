import Foundation

public enum AnalyticsEvent: String, Sendable, CaseIterable {
    case appInstallFirstSeen = "app_install_first_seen"
    case appLaunch = "app_launch"
    case appActiveDay = "app_active_day"
    case primaryUIOpened = "primary_ui_opened"
    case settingsOpened = "settings_opened"
}

public enum AnalyticsDistributionChannel: String, Sendable {
    case directSparkle = "direct_sparkle"
    case appStore = "app_store"
    case debug
    case test
}

public enum AnalyticsAppType: String, Sendable {
    case menuBar = "menu_bar"
    case windowed
}

public struct AnalyticsContext: Sendable, Equatable {
    public let appID: String?
    public let appName: String
    public let appVersion: String
    public let buildNumber: String
    public let distributionChannel: AnalyticsDistributionChannel
    public let appType: AnalyticsAppType

    public init(
        appID: String?,
        appName: String,
        appVersion: String,
        buildNumber: String,
        distributionChannel: AnalyticsDistributionChannel,
        appType: AnalyticsAppType
    ) {
        self.appID = appID
        self.appName = appName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.distributionChannel = distributionChannel
        self.appType = appType
    }

    public var resolvedAppID: String? {
        let trimmedValue = appID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue?.isEmpty == false ? trimmedValue : nil
    }

    public var baseProperties: [String: String] {
        [
            "app_name": appName,
            "app_version": appVersion,
            "build_number": buildNumber,
            "distribution_channel": distributionChannel.rawValue,
            "app_type": appType.rawValue
        ]
    }
}

@MainActor
public protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent, properties: [String: String])
}

public final class NoopAnalyticsClient: AnalyticsClient {
    public init() {}

    public func track(_ event: AnalyticsEvent, properties: [String: String]) {}
}

public enum AnalyticsClientFactory {
    @MainActor
    public static func makeClient(context: AnalyticsContext) -> any AnalyticsClient {
        guard context.distributionChannel != .test, context.resolvedAppID != nil else {
            return NoopAnalyticsClient()
        }

        return LiveAnalyticsClient(context: context)
    }
}

@MainActor
public final class AppAnalytics {
    private let client: any AnalyticsClient
    private let stateStore: AnalyticsStateStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        client: any AnalyticsClient,
        defaults: UserDefaults = .standard,
        keyPrefix: String = "NomadDashboard.Analytics",
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        stateStore = AnalyticsStateStore(defaults: defaults, keyPrefix: keyPrefix)
        self.calendar = calendar
        self.now = now
    }

    public func recordAppLaunch() {
        if stateStore.markFirstLaunchSeenIfNeeded() {
            client.track(.appInstallFirstSeen, properties: [:])
        }

        client.track(.appLaunch, properties: [:])
    }

    public func recordPrimaryUIOpened(analyticsEnabled: Bool) {
        recordUserActivity(event: .primaryUIOpened, analyticsEnabled: analyticsEnabled)
    }

    public func recordSettingsOpened(analyticsEnabled: Bool) {
        recordUserActivity(event: .settingsOpened, analyticsEnabled: analyticsEnabled)
    }

    private func recordUserActivity(event: AnalyticsEvent, analyticsEnabled: Bool) {
        guard analyticsEnabled else {
            return
        }

        let dayStart = calendar.startOfDay(for: now())
        if stateStore.markActiveDayIfNeeded(dayStart: dayStart) {
            client.track(.appActiveDay, properties: [:])
        }

        client.track(event, properties: [:])
    }
}

final class AnalyticsStateStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let firstLaunchSeenKey: String
    private let lastActiveDayKey: String

    init(defaults: UserDefaults, keyPrefix: String) {
        self.defaults = defaults
        firstLaunchSeenKey = "\(keyPrefix).firstLaunchSeen"
        lastActiveDayKey = "\(keyPrefix).lastActiveDaySent"
    }

    func markFirstLaunchSeenIfNeeded() -> Bool {
        if defaults.bool(forKey: firstLaunchSeenKey) {
            return false
        }

        defaults.set(true, forKey: firstLaunchSeenKey)
        return true
    }

    func markActiveDayIfNeeded(dayStart: Date) -> Bool {
        if let lastDay = defaults.object(forKey: lastActiveDayKey) as? Date, lastDay == dayStart {
            return false
        }

        defaults.set(dayStart, forKey: lastActiveDayKey)
        return true
    }
}
