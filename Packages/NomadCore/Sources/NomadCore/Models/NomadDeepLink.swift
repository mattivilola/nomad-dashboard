import Foundation

/// Links the widgets use to open the app. The scheme differs between the release and the development
/// build (`nomaddashboard` and `nomaddashboard-dev`) so the two apps never answer each other's links.
public enum NomadDeepLink: Equatable, Sendable {
    /// Info.plist key that carries this build's URL scheme.
    public static let schemeInfoKey = "NomadURLScheme"

    /// Open the dashboard popover.
    case dashboard

    private static let dashboardHost = "dashboard"

    public static func scheme(bundle: Bundle = .main) -> String? {
        let value = (bundle.object(forInfoDictionaryKey: schemeInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    public func url(scheme: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        switch self {
        case .dashboard:
            components.host = Self.dashboardHost
        }
        return components.url
    }

    /// Recognises a link addressed to the given scheme; anything else is ignored.
    public init?(url: URL, scheme: String) {
        guard url.scheme?.lowercased() == scheme.lowercased() else {
            return nil
        }

        switch url.host?.lowercased() {
        case Self.dashboardHost:
            self = .dashboard
        default:
            return nil
        }
    }
}
