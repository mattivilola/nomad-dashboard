import Foundation

enum UpdateFeatureConfiguration {
    static var isEnabled: Bool {
        pauseReason == nil
    }

    static var pausedReason: String {
        pauseReason ?? "Update checks are available."
    }

    private static var pauseReason: String? {
#if canImport(Sparkle)
        guard hasValidFeedURL else {
            return "Update checks are unavailable in this build because the Sparkle feed URL is missing or invalid."
        }

        guard hasValidPublicKey else {
            return "Update checks are unavailable in this build because the Sparkle public key is missing or invalid."
        }

        return nil
#else
        return "Update checks are unavailable because Sparkle is not linked in this build."
#endif
    }

    private static var hasValidFeedURL: Bool {
        guard
            let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(string: feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = feedURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            feedURL.host?.isEmpty == false
        else {
            return false
        }

        return true
    }

    private static var hasValidPublicKey: Bool {
        guard
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            let decodedKey = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return false
        }

        return decodedKey.count == 32
    }
}
