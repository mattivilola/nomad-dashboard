import Foundation

#if canImport(TelemetryDeck)
import TelemetryDeck

public final class LiveAnalyticsClient: AnalyticsClient {
    private let context: AnalyticsContext

    public init(context: AnalyticsContext) {
        self.context = context

        if let appID = context.resolvedAppID {
            TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        }
    }

    public func track(_ event: AnalyticsEvent, properties: [String: String]) {
        TelemetryDeck.signal(
            event.rawValue,
            parameters: context.baseProperties.merging(properties) { _, newValue in newValue }
        )
    }
}
#else
public final class LiveAnalyticsClient: AnalyticsClient {
    public init(context: AnalyticsContext) {}

    public func track(_ event: AnalyticsEvent, properties: [String: String]) {}
}
#endif
