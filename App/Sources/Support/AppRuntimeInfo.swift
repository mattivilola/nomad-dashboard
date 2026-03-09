import AppKit
import Foundation
import Security

enum AppRuntimeInfo {
    private static let productionBundleIdentifier = "com.iloapps.NomadDashboard"

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? productionBundleIdentifier
    }

    static var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    static var isProductionIdentity: Bool {
        bundleIdentifier == productionBundleIdentifier
    }

    static var isSigned: Bool {
        signingCertificates.isEmpty == false
    }

    static var hasWeatherKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let key = "com.apple.developer.weatherkit" as CFString
        let value = SecTaskCopyValueForEntitlement(task, key, nil)
        return (value as? Bool) == true
    }

    static var buildFlavorDescription: String {
        var parts = ["v\(marketingVersion) (\(buildNumber))"]

        if isDebugBuild || isProductionIdentity == false {
            parts.append("DEV")
        }

        parts.append(isSigned ? "signed" : "unsigned")
        return parts.joined(separator: " · ")
    }

    static var headerFlavorBadgeTitle: String? {
        if isDebugBuild || isProductionIdentity == false {
            return "DEV"
        }

        if isSigned == false {
            return "Unsigned"
        }

        return nil
    }

    static var weatherAvailabilityExplanation: String? {
        guard hasWeatherKitEntitlement else {
            return "WeatherKit is unavailable in this build because the WeatherKit entitlement is missing."
        }

        guard isSigned else {
            return "WeatherKit is unavailable in this build because the app is not signed for WeatherKit access."
        }

        return nil
    }

    static var versionDescription: String {
        buildFlavorDescription
    }

    static var applicationIconImage: NSImage {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 512, height: 512)
        return image
    }

    private static var signingCertificates: [SecCertificate] {
        guard let code = try? staticCode() else {
            return []
        }

        var signingInformation: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
        guard status == errSecSuccess,
              let dictionary = signingInformation as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] else {
            return []
        }

        return certificates
    }

    private static func staticCode() throws -> SecStaticCode {
        var code: SecStaticCode?
        let url = Bundle.main.bundleURL as CFURL
        let status = SecStaticCodeCreateWithPath(url, SecCSFlags(), &code)

        guard status == errSecSuccess, let code else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return code
    }
}
