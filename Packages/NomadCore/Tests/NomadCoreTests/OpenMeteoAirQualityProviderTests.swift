import CoreLocation
import Foundation
import NomadCore
import Testing

@Suite(.serialized)
struct OpenMeteoAirQualityProviderTests {
    @Test
    func providerDecodesCurrentAndHourlyAirQualityIntoSnapshot() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        // The hourly series starts at the current hour, which is not part of the 12 hour outlook.
        let times = (0...12).map { hour.addingTimeInterval(Double($0) * 3_600) }
        let aqi: [Any] = [41.2, 44, 48, 52, 58, 61, 66, 70, 72, NSNull(), 64, 59, 55]
        MockURLProtocol.install(try airQualityPayload(times: times, hourlyAQI: aqi, current: [
            "european_aqi": 43.6, "pm2_5": 14.2, "pm10": 31.5, "ozone": 88.0, "nitrogen_dioxide": 12.4,
            "european_aqi_pm2_5": 43.6, "european_aqi_pm10": 33.0, "european_aqi_ozone": 20.0,
            "european_aqi_nitrogen_dioxide": 5.0, "european_aqi_sulphur_dioxide": 1.0
        ]))

        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        let snapshot = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384))

        #expect(snapshot.sourceName == "Open-Meteo")
        #expect(snapshot.latitude == 60.2)
        #expect(snapshot.longitude == 24.9)
        #expect(snapshot.europeanAQI == 44)
        #expect(snapshot.band == .moderate)
        #expect(snapshot.mainPollutant == .pm2_5)
        #expect(snapshot.pm2_5 == 14.2)
        #expect(snapshot.pm10 == 31.5)
        #expect(snapshot.ozone == 88)
        #expect(snapshot.nitrogenDioxide == 12.4)
        #expect(snapshot.forecastSlots.count == 12)
        #expect(snapshot.forecastSlots.allSatisfy { $0.date > snapshot.fetchedAt.addingTimeInterval(-1) })
        #expect(snapshot.forecastSlots.map(\.date) == snapshot.forecastSlots.map(\.date).sorted())
        #expect(snapshot.forecastSlots.contains { $0.europeanAQI == nil })
    }

    @Test
    func requestRoundsTheCoordinateAndAsksForTheDocumentedVariables() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        MockURLProtocol.install(try airQualityPayload(times: [hour], hourlyAQI: [30], current: ["european_aqi": 30]))


        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.169857, longitude: 24.938379))

        let url = try #require(MockURLProtocol.requestedURLs().first)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host == "air-quality-api.open-meteo.com")
        #expect(url.path == "/v1/air-quality")
        #expect(items["latitude"] == "60.2")
        #expect(items["longitude"] == "24.9")
        #expect(items["hourly"] == "european_aqi")
        #expect(items["forecast_hours"] == "13")
        let current = Set((items["current"] ?? "").split(separator: ",").map(String.init))
        #expect(current.isSuperset(of: ["european_aqi", "pm2_5", "pm10", "ozone", "nitrogen_dioxide"]))
        #expect(current.contains("european_aqi_pm2_5") && current.contains("european_aqi_nitrogen_dioxide"))
        // The exact coordinate must not appear anywhere in the request.
        #expect(url.absoluteString.contains("60.169") == false)
        #expect(url.absoluteString.contains("24.938") == false)
        #expect(MockURLProtocol.requestedURLs().count == 1)
    }

    @Test
    func negativeZeroAndSouthernWesternCoordinatesRoundCleanly() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        MockURLProtocol.install(try airQualityPayload(times: [hour], hourlyAQI: [30], current: ["european_aqi": 30]))


        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: -0.04, longitude: -33.86))

        let url = try #require(MockURLProtocol.requestedURLs().first)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "latitude" }?.value == "0.0")
        #expect(items.first { $0.name == "longitude" }?.value == "-33.9")
    }

    @Test
    func nearbyCoordinatesInTheSameGridCellShareTheCachedSnapshot() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        MockURLProtocol.install(try airQualityPayload(times: [hour], hourlyAQI: [30], current: ["european_aqi": 30]))


        let provider = LiveOpenMeteoAirQualityProvider(session: session, ttl: 1_800)
        let first = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.161, longitude: 24.941))
        let second = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.174, longitude: 24.935))
        _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.4, longitude: 24.9))

        #expect(first == second)
        #expect(MockURLProtocol.requestedURLs().count == 2)
    }

    @Test
    func expiredCacheRefetches() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        MockURLProtocol.install(try airQualityPayload(times: [hour], hourlyAQI: [30], current: ["european_aqi": 30]))


        let provider = LiveOpenMeteoAirQualityProvider(session: session, ttl: 0)
        _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.2, longitude: 24.9))
        _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.2, longitude: 24.9))

        #expect(MockURLProtocol.requestedURLs().count == 2)
    }

    @Test
    func missingCurrentIndexIsAnInvalidResponse() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        MockURLProtocol.install(try airQualityPayload(times: [hour], hourlyAQI: [NSNull()], current: ["european_aqi": NSNull(), "pm2_5": NSNull()]))


        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        await #expect(throws: ProviderError.self) {
            _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 0.1, longitude: 0.1))
        }
    }

    @Test
    func httpErrorIsAnInvalidResponse() async throws {
        let session = makeSession()
        MockURLProtocol.install(Data(), statusCode: 500)

        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        await #expect(throws: ProviderError.self) {
            _ = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 60.2, longitude: 24.9))
        }
    }

    @Test
    func invalidCoordinatesNeverReachTheNetwork() async throws {
        let session = makeSession()
        MockURLProtocol.install(Data())

        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        for coordinate in [
            CLLocationCoordinate2D(latitude: 91, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 181),
            CLLocationCoordinate2D(latitude: .nan, longitude: 0)
        ] {
            await #expect(throws: ProviderError.self) {
                _ = try await provider.airQuality(for: coordinate)
            }
        }
        #expect(MockURLProtocol.requestedURLs().isEmpty)
    }

    @Test
    func timestampsAreInterpretedInTheLocationsTimeZone() async throws {
        let session = makeSession()
        let hour = Date().roundedDownToHour()
        let zone = TimeZone(identifier: "Asia/Kolkata")!
        MockURLProtocol.install(try airQualityPayload(
            times: (0...2).map { hour.addingTimeInterval(Double($0) * 3_600) },
            hourlyAQI: [90, 95, 99],
            current: ["european_aqi": 90],
            timezone: zone.identifier,
            utcOffsetSeconds: zone.secondsFromGMT()
        ))

        let provider = LiveOpenMeteoAirQualityProvider(session: session)
        let snapshot = try await provider.airQuality(for: CLLocationCoordinate2D(latitude: 28.6, longitude: 77.2))

        #expect(snapshot.forecastSlots.count == 2)
        let first = try #require(snapshot.forecastSlots.first)
        #expect(abs(first.date.timeIntervalSince(hour.addingTimeInterval(3_600))) < 1)
        #expect(first.europeanAQI == 95)
    }
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func airQualityPayload(
    times: [Date],
    hourlyAQI: [Any],
    current: [String: Any],
    timezone: String = "UTC",
    utcOffsetSeconds: Int = 0
) throws -> Data {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timezone)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return try JSONSerialization.data(
        withJSONObject: [
            "timezone": timezone,
            "utc_offset_seconds": utcOffsetSeconds,
            "current": current,
            "hourly": [
                "time": times.map { formatter.string(from: $0) },
                "european_aqi": hourlyAQI
            ]
        ]
    )
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var urls: [URL] = []
    private static let lock = NSLock()

    static func install(_ payload: Data, statusCode: Int = 200) {
        lock.lock()
        defer { lock.unlock() }
        self.payload = payload
        self.statusCode = statusCode
        urls = []
    }

    static func requestedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: ProviderError.invalidResponse)
            return
        }
        Self.lock.lock()
        Self.urls.append(url)
        let payload = Self.payload
        let statusCode = Self.statusCode
        Self.lock.unlock()

        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: ProviderError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Date {
    func roundedDownToHour() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: self)
        var rounded = DateComponents()
        rounded.timeZone = TimeZone(identifier: "UTC")
        rounded.year = components.year
        rounded.month = components.month
        rounded.day = components.day
        rounded.hour = components.hour
        return calendar.date(from: rounded) ?? self
    }
}
