import Foundation
@testable import NomadCore
@testable import NomadUI
import Testing

struct TravelProfilePresentationTests {
    @Test
    func footerIsTheProfileSummaryWhenTheRecommendedOrderIsInUse() {
        for profile in TravelProfile.allCases {
            let presentation = TravelProfileSettingsPresentation(profile: profile, isUsingRecommendedOrder: true)

            #expect(presentation.footer == profile.summary)
            #expect(presentation.offersRecommendedOrder == false)
        }
    }

    @Test
    func footerMentionsTheKeptCustomOrderAndOffersTheRecommendedOneWhenCustomized() {
        for profile in TravelProfile.allCases {
            let presentation = TravelProfileSettingsPresentation(profile: profile, isUsingRecommendedOrder: false)

            #expect(presentation.footer == "\(profile.summary) Your custom card order is kept.")
            #expect(presentation.offersRecommendedOrder)
        }
    }

    @Test
    func recommendedOrderIsTheProfilesDefaultCardOrder() {
        for profile in TravelProfile.allCases {
            let presentation = TravelProfileSettingsPresentation(profile: profile, isUsingRecommendedOrder: false)

            #expect(presentation.recommendedOrder == DashboardCardID.defaultOrder(for: profile))
        }
    }

    @Test
    func menuBarHeadsUpFooterExplainsThatOnlyUrgentItemsReplaceTheTemperature() {
        #expect(TravelProfileSettingsPresentation.menuBarHeadsUpFooter.contains("caution or attention"))
        #expect(TravelProfileSettingsPresentation.menuBarHeadsUpFooter.contains("temperature"))
    }
}

struct OfflineEssentialsPresentationTests {
    @Test
    func weatherSummaryUsesTheSharedTemperatureFormat() {
        let summary = OfflineEssentialsPresentation.weatherSummary(makeWeather(temperature: 18.6, condition: "Sunny"))

        #expect(summary == "\(TravelUnitFormatting.temperature(18.6)) · Sunny")
        #expect(summary == "19° · Sunny")
    }

    @Test
    func weatherSummaryFallsBackToTheConditionWithoutATemperature() {
        let summary = OfflineEssentialsPresentation.weatherSummary(makeWeather(temperature: nil, condition: "Fog"))

        #expect(summary == "Fog")
    }

    @Test
    func fuelLineUsesThePumpPriceFormatWithPerLiterSuffix() {
        let station = FuelStationPrice(
            fuelType: .diesel,
            stationName: "Repsol",
            address: nil,
            locality: nil,
            pricePerLiter: 1.4294,
            currencyCode: "EUR",
            distanceKilometers: 2,
            latitude: 40,
            longitude: -3,
            updatedAt: nil
        )
        let locale = Locale(identifier: "en_US")

        #expect(
            OfflineEssentialsPresentation.fuelLine(station, locale: locale)
                == "Repsol · \(FuelPriceFormatting.price(1.4294, currencyCode: "EUR", locale: locale))/L"
        )
        #expect(OfflineEssentialsPresentation.fuelLine(station, locale: locale).contains("1.429"))
    }

    @Test
    func emergencyNumbersFollowTheCurrentCountry() {
        let france = makeSnapshot(countryCode: "FR")

        #expect(OfflineEssentialsPresentation.emergencyNumbers(for: france)?.general == "112")
        #expect(OfflineEssentialsPresentation.emergencyNumbers(for: france) == EmergencyNumberDirectory.numbers(forCountryCode: "FR"))
    }

    @Test
    func emergencyNumbersAreNilWithoutACountry() {
        #expect(OfflineEssentialsPresentation.emergencyNumbers(for: makeSnapshot(countryCode: nil)) == nil)
    }
}

private func makeSnapshot(countryCode: String?) -> DashboardSnapshot {
    DashboardSnapshot(
        network: NetworkSectionSnapshot(
            throughput: NetworkThroughputSample(
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0,
                activeInterface: nil,
                collectedAt: .now
            ),
            connectivity: .checking,
            latency: nil,
            downloadHistory: [],
            uploadHistory: [],
            latencyHistory: []
        ),
        power: PowerSectionSnapshot(snapshot: nil, chargeHistory: [], dischargeHistory: []),
        travelContext: TravelContextSnapshot(
            wifi: nil,
            vpn: VPNStatusSnapshot(isActive: false, interfaceNames: []),
            timeZoneIdentifier: "Europe/Paris",
            deviceLocation: nil,
            publicIP: nil,
            location: IPLocationSnapshot(
                city: nil,
                region: nil,
                country: nil,
                countryCode: countryCode,
                latitude: nil,
                longitude: nil,
                timeZone: nil,
                provider: "test",
                fetchedAt: .now
            )
        ),
        weather: nil,
        appState: AppStatusSnapshot(lastRefresh: .now, updateState: .idle, issues: []),
        meteredData: .disabled
    )
}

private func makeWeather(temperature: Double?, condition: String) -> WeatherSnapshot {
    WeatherSnapshot(
        currentTemperatureCelsius: temperature,
        apparentTemperatureCelsius: temperature,
        conditionDescription: condition,
        symbolName: "sun.max.fill",
        precipitationChance: 0,
        windSpeedKph: nil,
        windDirectionDegrees: nil,
        hourlyForecastSlots: [],
        dailyForecast: [],
        tomorrow: nil,
        fetchedAt: .now
    )
}
