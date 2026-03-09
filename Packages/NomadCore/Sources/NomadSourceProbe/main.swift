import CoreLocation
import Foundation
import NomadCore

@main
struct NomadSourceProbeCLI {
    static func main() async {
        do {
            let options = try Options.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(Options.helpText)
                return
            }

            let runner = ProbeRunner(options: options)
            let exitCode = await runner.run()
            Foundation.exit(exitCode)
        } catch {
            fputs("error: \(error)\n\n\(Options.helpText)\n", stderr)
            Foundation.exit(2)
        }
    }
}

private struct ProbeRunner {
    let options: Options

    func run() async -> Int32 {
        let context = ProbeContext(options: options)
        let probeStart = Date()

        print("Nomad source probe")
        print("Started: \(context.formatter.string(from: probeStart))")
        print("ReliefWeb app name: \(context.reliefWebAppName)")
        print("")

        var results = [ProbeResult]()

        let publicIPProvider = CachedPublicIPProvider()
        let publicIPResult = await probe("FreeIPAPI current IP") {
            let snapshot = try await publicIPProvider.currentIP(forceRefresh: true)
            return ProbeResult.success(
                name: "FreeIPAPI current IP",
                lines: [
                    "address: \(snapshot.address)",
                    "provider: \(snapshot.provider)"
                ]
            )
        }
        results.append(publicIPResult)

        let ipForLocation = options.ipAddress ?? publicIPResult.firstValue(after: "address: ")

        let ipLocationProvider = CachedIPLocationProvider()
        let locationResult: ProbeResult
        var resolvedLocation: IPLocationSnapshot?
        if let ipForLocation {
            locationResult = await probe("FreeIPAPI geolocation") {
                let snapshot = try await ipLocationProvider.currentLocation(for: ipForLocation, forceRefresh: true)
                resolvedLocation = snapshot
                return ProbeResult.success(
                    name: "FreeIPAPI geolocation",
                    lines: [
                        "country: \(display(snapshot.country)) (\(display(snapshot.countryCode)))",
                        "region: \(display(snapshot.region))",
                        "city: \(display(snapshot.city))",
                        "coordinate: \(displayCoordinate(snapshot.coordinate))",
                        "timezone: \(display(snapshot.timeZone))"
                    ]
                )
            }
        } else {
            locationResult = .skipped(name: "FreeIPAPI geolocation", reason: "No IP address available.")
        }
        results.append(locationResult)

        let coordinate = options.coordinate ?? resolvedLocation?.coordinate
        let primaryCountryCode = options.countryCode ?? resolvedLocation?.countryCode?.uppercased()
        let neighborResolver = BundledNeighborCountryResolver()
        let coverageCountryCodes = primaryCountryCode.map {
            [$0] + neighborResolver.neighboringCountryCodes(for: $0)
        } ?? []

        print("Resolved inputs")
        print("  coordinate: \(displayCoordinate(coordinate))")
        print("  primary country: \(display(primaryCountryCode))")
        print("  coverage countries: \(coverageCountryCodes.isEmpty ? "n/a" : coverageCountryCodes.joined(separator: ", "))")
        print("  marine spot: \(context.spotName)")
        print("")

        let reverseGeocoder = CachedReverseGeocodingProvider()
        if let coordinate {
            await results.append(
                probe("Apple reverse geocoder") {
                    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let details = try await reverseGeocoder.details(for: location)
                    return ProbeResult.success(
                        name: "Apple reverse geocoder",
                        lines: [
                            "country: \(display(details.country)) (\(display(details.countryCode)))",
                            "region: \(display(details.region))",
                            "city: \(display(details.city))",
                            "timezone: \(display(details.timeZoneIdentifier))"
                        ]
                    )
                }
            )
        } else {
            results.append(.skipped(name: "Apple reverse geocoder", reason: "Coordinate unavailable. Pass --latitude and --longitude to force it."))
        }

        let weatherProvider = LiveWeatherProvider()
        if let coordinate {
            await results.append(
                probe("WeatherKit weather") {
                    let snapshot = try await weatherProvider.weather(for: coordinate)
                    var lines = [
                        "condition: \(snapshot.conditionDescription)",
                        "temperature C: \(displayNumber(snapshot.currentTemperatureCelsius))",
                        "apparent C: \(displayNumber(snapshot.apparentTemperatureCelsius))",
                        "wind kph: \(displayNumber(snapshot.windSpeedKph))"
                    ]

                    if let precipitationChance = snapshot.precipitationChance {
                        lines.append("precip chance: \(String(format: "%.0f%%", precipitationChance * 100))")
                    }

                    if let tomorrow = snapshot.tomorrow {
                        lines.append("tomorrow: \(tomorrow.summary) (\(displayNumber(tomorrow.temperatureMinCelsius)) to \(displayNumber(tomorrow.temperatureMaxCelsius)) C)")
                    }

                    return ProbeResult.success(name: "WeatherKit weather", lines: lines)
                }
            )
        } else {
            results.append(.skipped(name: "WeatherKit weather", reason: "Coordinate unavailable."))
        }

        let weatherAlertsProvider = WeatherKitAlertProvider()
        if let coordinate {
            await results.append(
                probe("WeatherKit alerts") {
                    let signal = try await weatherAlertsProvider.alerts(for: coordinate, forceRefresh: true)
                    return ProbeResult.success(
                        name: "WeatherKit alerts",
                        lines: travelAlertLines(signal)
                    )
                }
            )
        } else {
            results.append(.skipped(name: "WeatherKit alerts", reason: "Coordinate unavailable."))
        }

        let advisoryProvider = SmartravellerAdvisoryProvider()
        if let primaryCountryCode, coverageCountryCodes.isEmpty == false {
            await results.append(
                probe("Smartraveller advisory") {
                    let signal = try await advisoryProvider.advisory(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: true
                    )
                    return ProbeResult.success(
                        name: "Smartraveller advisory",
                        lines: travelAlertLines(signal)
                    )
                }
            )
        } else {
            results.append(.skipped(name: "Smartraveller advisory", reason: "Country code unavailable. Pass --country-code to force it."))
        }

        let reliefWebProvider = ReliefWebSecurityProvider(appName: context.reliefWebAppName)
        if let primaryCountryCode, coverageCountryCodes.isEmpty == false {
            await results.append(
                probe("ReliefWeb regional security") {
                    let signal = try await reliefWebProvider.security(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: true
                    )
                    return ProbeResult.success(
                        name: "ReliefWeb regional security",
                        lines: travelAlertLines(signal)
                    )
                }
            )
        } else {
            results.append(.skipped(name: "ReliefWeb regional security", reason: "Country code unavailable. Pass --country-code to force it."))
        }

        let marineProvider = LiveOpenMeteoMarineProvider()
        if let coordinate {
            await results.append(
                probe("Open-Meteo marine") {
                    let snapshot = try await marineProvider.marine(
                        for: MarineSpot(name: context.spotName, coordinate: coordinate)
                    )
                    return ProbeResult.success(
                        name: "Open-Meteo marine",
                        lines: [
                            "spot: \(snapshot.spotName)",
                            "wave m: \(displayNumber(snapshot.waveHeightMeters))",
                            "swell m: \(displayNumber(snapshot.swellHeightMeters))",
                            "wind kph: \(displayNumber(snapshot.windSpeedKph))",
                            "sea temp C: \(displayNumber(snapshot.seaSurfaceTemperatureCelsius))"
                        ]
                    )
                }
            )
        } else {
            results.append(.skipped(name: "Open-Meteo marine", reason: "Coordinate unavailable."))
        }

        print("Summary")
        for result in results {
            print(result.summaryLine)
        }

        let failures = results.filter { $0.status == .failed }
        let skipped = results.filter { $0.status == .skipped }
        print("")
        print("Completed in \(String(format: "%.2f", Date().timeIntervalSince(probeStart)))s")
        print("Failures: \(failures.count), skipped: \(skipped.count)")

        return failures.isEmpty ? 0 : 1
    }

    private func probe(_ name: String, operation: () async throws -> ProbeResult) async -> ProbeResult {
        let start = Date()
        do {
            var result = try await operation()
            result.duration = Date().timeIntervalSince(start)
            print(result.renderedBlock)
            return result
        } catch {
            var result = ProbeResult.failed(
                name: name,
                lines: errorLines(for: error)
            )
            result.duration = Date().timeIntervalSince(start)
            print(result.renderedBlock)
            return result
        }
    }
}

private struct ProbeContext {
    let reliefWebAppName: String
    let spotName: String
    let formatter: ISO8601DateFormatter

    init(options: Options) {
        reliefWebAppName = options.reliefWebAppName
            ?? ProcessInfo.processInfo.environment["RELIEFWEB_APPNAME"]?.trimmedNonEmpty
            ?? "NomadDashboardSourceProbe"
        spotName = options.spotName ?? "Source probe spot"
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
}

private struct Options {
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let ipAddress: String?
    let reliefWebAppName: String?
    let spotName: String?
    let showHelp: Bool

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func parse(arguments: [String]) throws -> Options {
        var countryCode: String?
        var latitude: Double?
        var longitude: Double?
        var ipAddress: String?
        var reliefWebAppName: String?
        var spotName: String?
        var showHelp = false

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h":
                showHelp = true
            case "--country-code":
                countryCode = try nextValue(after: argument, iterator: &iterator).uppercased()
            case "--latitude":
                latitude = try parseDouble(nextValue(after: argument, iterator: &iterator), argument: argument)
            case "--longitude":
                longitude = try parseDouble(nextValue(after: argument, iterator: &iterator), argument: argument)
            case "--ip":
                ipAddress = try nextValue(after: argument, iterator: &iterator)
            case "--reliefweb-app-name":
                reliefWebAppName = try nextValue(after: argument, iterator: &iterator)
            case "--spot-name":
                spotName = try nextValue(after: argument, iterator: &iterator)
            default:
                throw UsageError("Unknown argument: \(argument)")
            }
        }

        if (latitude == nil) != (longitude == nil) {
            throw UsageError("Pass both --latitude and --longitude together.")
        }

        return Options(
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            ipAddress: ipAddress,
            reliefWebAppName: reliefWebAppName,
            spotName: spotName,
            showHelp: showHelp
        )
    }

    static let helpText = """
    Usage: NomadSourceProbe [options]

    Probes the app's external data sources through the same live providers used by Nomad Dashboard.

    Options:
      --country-code <code>         Override the primary ISO country code for Smartraveller and ReliefWeb.
      --latitude <value>            Override the latitude used for reverse geocoding, WeatherKit, and marine.
      --longitude <value>           Override the longitude used for reverse geocoding, WeatherKit, and marine.
      --ip <address>                Override the IP address used for geolocation.
      --reliefweb-app-name <name>   Override RELIEFWEB_APPNAME. Defaults to env RELIEFWEB_APPNAME or NomadDashboardSourceProbe.
      --spot-name <name>            Label used for the marine probe. Default: Source probe spot.
      --help                        Show this help.
    """

    private static func nextValue(after argument: String, iterator: inout IndexingIterator<[String]>) throws -> String {
        guard let value = iterator.next() else {
            throw UsageError("Missing value for \(argument)")
        }

        return value
    }

    private static func parseDouble(_ value: String, argument: String) throws -> Double {
        guard let parsed = Double(value) else {
            throw UsageError("Invalid number for \(argument): \(value)")
        }

        return parsed
    }
}

private struct ProbeResult {
    enum Status {
        case passed
        case failed
        case skipped
    }

    let name: String
    let status: Status
    let lines: [String]
    var duration: TimeInterval?

    static func success(name: String, lines: [String]) -> ProbeResult {
        ProbeResult(name: name, status: .passed, lines: lines, duration: nil)
    }

    static func failed(name: String, lines: [String]) -> ProbeResult {
        ProbeResult(name: name, status: .failed, lines: lines, duration: nil)
    }

    static func skipped(name: String, reason: String) -> ProbeResult {
        ProbeResult(name: name, status: .skipped, lines: ["reason: \(reason)"], duration: nil)
    }

    var renderedBlock: String {
        var buffer = ["[\(statusLabel)] \(name)\(durationSuffix)"]
        buffer.append(contentsOf: lines.map { "  \($0)" })
        buffer.append("")
        return buffer.joined(separator: "\n")
    }

    var summaryLine: String {
        "[\(statusLabel)] \(name)"
    }

    private var statusLabel: String {
        switch status {
        case .passed:
            "OK"
        case .failed:
            "FAIL"
        case .skipped:
            "SKIP"
        }
    }

    private var durationSuffix: String {
        guard let duration else {
            return ""
        }

        return " (\(String(format: "%.2fs", duration)))"
    }

    func firstValue(after prefix: String) -> String? {
        lines.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}

private struct UsageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private func errorLines(for error: Error) -> [String] {
    var lines = ["error: \(String(describing: error))"]

    if let urlError = error as? URLError {
        lines.append("url error: \(urlError.code.rawValue) \(urlError.code)")
    }

    let hint = errorHint(for: error)
    if let hint {
        lines.append("hint: \(hint)")
    }

    return lines
}

private func errorHint(for error: Error) -> String? {
    let description = String(describing: error).lowercased()

    if description.contains("weatherkit") {
        return "WeatherKit calls from the CLI may fail without the same entitlement context as the app build."
    }

    if description.contains("429") {
        return "The upstream likely rate-limited the request. Retry later or reduce probe frequency."
    }

    if description.contains("approved appname") {
        return "ReliefWeb now requires an approved app name. Set RELIEFWEB_APPNAME to the approved value you received from ReliefWeb."
    }

    if description.contains("missingconfiguration") {
        return "Set RELIEFWEB_APPNAME if ReliefWeb rejects the default app name."
    }

    return nil
}

private func travelAlertLines(_ signal: TravelAlertSignalSnapshot) -> [String] {
    [
        "severity: \(signal.severity.rawValue)",
        "summary: \(signal.summary)",
        "source: \(signal.sourceName)",
        "items: \(signal.itemCount.map(String.init) ?? "n/a")",
        "affected: \(signal.affectedCountryCodes.isEmpty ? "none" : signal.affectedCountryCodes.joined(separator: ", "))",
        "source URL: \(signal.sourceURL?.absoluteString ?? "n/a")"
    ]
}

private func display(_ value: String?) -> String {
    value?.trimmedNonEmpty ?? "n/a"
}

private func displayCoordinate(_ coordinate: CLLocationCoordinate2D?) -> String {
    guard let coordinate else {
        return "n/a"
    }

    return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
}

private func displayNumber(_ value: Double?) -> String {
    guard let value else {
        return "n/a"
    }

    return String(format: "%.1f", value)
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
