import Foundation

public enum AppRuntimeConfiguration {
    public static func resolveHUDUserAPIToken(
        userSetting: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let environmentValue = trimmed(environment["HUDUSER_API_TOKEN"]) {
            return environmentValue
        }

        return trimmed(userSetting)
    }

    public static func resolveTankerkonigAPIKey(
        userSetting: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let environmentValue = trimmed(environment["TANKERKOENIG_APIKEY"]) {
            return environmentValue
        }

        return trimmed(userSetting)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
