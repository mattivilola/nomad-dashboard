import CoreLocation
import Foundation
import NomadCore
import Testing

struct OpenMeteoMarineProviderTests {
    @Test
    func providerDecodesMarineAndWindResponsesIntoSnapshot() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let now = Date()
        let timeline = [
            now.roundedDownToHour(),
            now.roundedDownToHour().addingTimeInterval(3 * 3_600),
            now.roundedDownToHour().addingTimeInterval(6 * 3_600),
            now.roundedDownToHour().addingTimeInterval(12 * 3_600),
            now.roundedDownToHour().addingTimeInterval(24 * 3_600)
        ]

        MockURLProtocol.handler = { request in
            guard let url = request.url else {
                throw ProviderError.invalidResponse
            }
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw ProviderError.invalidResponse
            }

            if url.host == "marine-api.open-meteo.com" {
                return try (marinePayload(times: timeline), response)
            }

            if url.host == "api.open-meteo.com" {
                return try (forecastPayload(times: timeline), response)
            }

            Issue.record("Unexpected URL: \(url.absoluteString)")
            throw ProviderError.invalidResponse
        }

        let provider = LiveOpenMeteoMarineProvider(session: session, ttl: 1_800)
        let snapshot = try await provider.marine(
            for: MarineSpot(
                name: "El Saler",
                coordinate: CLLocationCoordinate2D(latitude: 39.355, longitude: -0.314)
            )
        )

        #expect(snapshot.spotName == "El Saler")
        #expect(snapshot.sourceName == "Open-Meteo")
        #expect(snapshot.waveHeightMeters == 1.6)
        #expect(snapshot.wavePeriodSeconds == 11)
        #expect(snapshot.swellHeightMeters == 1.2)
        #expect(snapshot.swellDirectionDegrees == 90)
        #expect(snapshot.windSpeedKph == 18)
        #expect(snapshot.windGustKph == 24)
        #expect(snapshot.windDirectionDegrees == 315)
        #expect(snapshot.seaSurfaceTemperatureCelsius == 17)
        #expect(snapshot.forecastSlots.count == 4)
        #expect(abs(snapshot.forecastSlots[0].date.timeIntervalSince(snapshot.fetchedAt) - (3 * 3_600)) < 1)
        #expect(abs(snapshot.forecastSlots[3].date.timeIntervalSince(snapshot.fetchedAt) - (24 * 3_600)) < 1)
        #expect(snapshot.forecastSlots.first?.waveHeightMeters == 1.4)
        #expect(snapshot.forecastSlots[3].windSpeedKph == 8)
    }
}

private func marinePayload(times: [Date]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "timezone": "UTC",
            "utc_offset_seconds": 0,
            "hourly": [
                "time": times.map(\.openMeteoHourString),
                "wave_height": [1.6, 1.4, 1.3, 1.1, 0.9],
                "wave_period": [11, 10, 9, 8, 7],
                "swell_wave_height": [1.2, 1.0, 0.9, 0.8, 0.7],
                "swell_wave_period": [10, 9, 8, 7, 6],
                "swell_wave_direction": [90, 80, 70, 60, 50],
                "sea_surface_temperature": [17, 17, 16, 16, 15]
            ]
        ]
    )
}

private func forecastPayload(times: [Date]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "timezone": "UTC",
            "utc_offset_seconds": 0,
            "hourly": [
                "time": times.map(\.openMeteoHourString),
                "wind_speed_10m": [18, 16, 13, 10, 8],
                "wind_gusts_10m": [24, 22, 18, 14, 11],
                "wind_direction_10m": [315, 300, 285, 270, 255]
            ]
        ]
    )
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Data, URLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ProviderError.invalidResponse)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Date {
    func roundedDownToHour() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: self)
        return calendar.date(from: components) ?? self
    }

    var openMeteoHourString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: self)
    }
}
