import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct TripMapPresentationTests {
    private typealias Support = StaysTestSupport

    private func mission(
        _ id: String,
        host: String = "MA",
        latitude: Double,
        longitude: Double,
        approximate: Bool = false,
        city: String? = "Rabat"
    ) -> DiplomaticMissionMatch {
        DiplomaticMissionMatch(
            mission: DiplomaticMission(
                id: id,
                sendingCountry: "FI",
                hostCountry: host,
                kind: .embassy,
                name: "Embassy of Finland in \(city ?? "Nowhere")",
                city: city,
                latitude: latitude,
                longitude: longitude,
                isApproximateLocation: approximate
            ),
            distanceKilometers: nil
        )
    }

    private func preview(
        country: String = "MA",
        own: [DiplomaticMissionMatch] = [],
        fallback: [DiplomaticMissionMatch] = []
    ) -> TripPreview {
        let trip = Support.trip(country, from: (2_027, 1, 12), to: (2_027, 1, 25))
        return TripPreview(
            trip: trip,
            countryCode: country,
            countryName: CountryNames.displayName(forCode: country, locale: Support.locale),
            schedule: TripPreview.Schedule(dayCount: 14, nightCount: 13, daysUntilStart: 92, daysSinceEnd: -105),
            embassy: TripPreview.Embassy(
                citizenshipCode: "FI",
                ownMissions: own,
                fallbackMissions: fallback,
                fallbackReason: fallback.isEmpty ? nil : .nordicCooperation,
                consularContacts: nil
            )
        )
    }

    private func map(
        _ preview: TripPreview,
        policy: DashboardResourcePolicy = .normal
    ) -> TripMapPresentation? {
        TripMapPresentation(preview: preview, policy: policy)
    }

    // MARK: Framing

    @Test
    func theCountryIsFramedFromItsBoundsWithSomePadding() throws {
        let region = try #require(CountryGeometry.boundingRegion(forCountryCode: "MA"))
        let result = try #require(map(preview()))

        #expect(result.camera.centerLatitude == region.centerLatitude)
        #expect(result.camera.centerLongitude == region.centerLongitude)
        #expect(abs(result.camera.latitudeSpan - region.latitudeSpan * TripMapPresentation.regionPadding) < 1e-9)
        #expect(abs(result.camera.longitudeSpan - region.longitudeSpan * TripMapPresentation.regionPadding) < 1e-9)
        #expect(result.camera.latitudeSpan > region.latitudeSpan)
    }

    @Test
    func aCountryAcrossTheAntimeridianIsFramedOnItsOwnSideOfTheWorld() throws {
        let region = try #require(CountryGeometry.boundingRegion(forCountryCode: "FJ"))
        #expect(region.crossesAntimeridian)

        let result = try #require(map(preview(country: "FJ")))

        // The centre is the box's own centre (about 178.7 E), and the span is the few degrees of Fiji, not
        // the 360 degrees around the world.
        #expect(abs(result.camera.centerLongitude - region.centerLongitude) < 1e-9)
        #expect(result.camera.centerLongitude > 178 && result.camera.centerLongitude <= 180)
        #expect(result.camera.longitudeSpan < 10)
    }

    @Test
    func theSpansStayWithinWhatAMapCanShow() throws {
        let russia = try #require(map(preview(country: "RU")))

        #expect(russia.camera.latitudeSpan <= TripMapPresentation.maximumLatitudeSpan)
        #expect(russia.camera.longitudeSpan <= TripMapPresentation.maximumLongitudeSpan)
        #expect(russia.camera.centerLongitude >= -180 && russia.camera.centerLongitude <= 180)
    }

    @Test
    func withoutBoundsTheMissionsAreFramed() throws {
        let result = try #require(map(preview(
            country: "ZZ",
            own: [mission("A", latitude: 10, longitude: 20), mission("B", latitude: 12, longitude: 24)]
        )))

        #expect(result.camera.centerLatitude == 11)
        #expect(result.camera.centerLongitude == 22)
        #expect(abs(result.camera.latitudeSpan - 2 * TripMapPresentation.missionPadding) < 1e-9)
        #expect(abs(result.camera.longitudeSpan - 4 * TripMapPresentation.missionPadding) < 1e-9)
    }

    @Test
    func aSingleMissionStillGetsRoomAroundIt() throws {
        let result = try #require(map(preview(country: "ZZ", own: [mission("A", latitude: 10, longitude: 20)])))

        #expect(result.camera.latitudeSpan == TripMapPresentation.minimumSpan)
        #expect(result.camera.longitudeSpan == TripMapPresentation.minimumSpan)
    }

    @Test
    func missionsOnBothSidesOfTheAntimeridianAreFramedTogether() throws {
        let result = try #require(map(preview(
            country: "ZZ",
            own: [mission("A", latitude: -17, longitude: 179.9), mission("B", latitude: -17.2, longitude: -179.9)]
        )))

        #expect(abs(abs(result.camera.centerLongitude) - 180) < 1e-9)
        #expect(result.camera.longitudeSpan < 1)
    }

    @Test
    func nothingToFrameMeansNoMap() {
        #expect(map(preview(country: "ZZ")) == nil)
    }

    @Test
    func aCountryWithBoundsIsMappedEvenWithoutMissions() throws {
        let result = try #require(map(preview()))

        #expect(result.pins.isEmpty)
        #expect(result.caption == "Map © Apple")
    }

    // MARK: Pins

    @Test
    func theOwnMissionsArePinnedAndPreciseOnesAreNotMarkedApproximate() throws {
        let result = try #require(map(preview(
            own: [
                mission("A", latitude: 34.05, longitude: -6.84, approximate: false),
                mission("B", latitude: 33.57, longitude: -7.59, approximate: true, city: "Casablanca")
            ],
            fallback: [mission("C", latitude: 35.77, longitude: -5.80)]
        )))

        #expect(result.pins.map(\.id) == ["A", "B"])
        #expect(result.pins.map(\.isApproximate) == [false, true])
        #expect(result.pins[0].latitude == 34.05)
    }

    @Test
    func theFallbackMissionsAreUsedWhenThereIsNoOwnOne() throws {
        let result = try #require(map(preview(fallback: [mission("C", latitude: 35.77, longitude: -5.80)])))

        #expect(result.pins.map(\.id) == ["C"])
    }

    @Test
    func aMissionOpensTheSameAppleMapsSearchAsTheEmbassyCard() throws {
        let precise = mission("A", latitude: 34.05, longitude: -6.84, approximate: false)
        let approximate = mission("B", latitude: 33.57, longitude: -7.59, approximate: true, city: "Casablanca")
        let result = try #require(map(preview(own: [precise, approximate])))

        #expect(result.pins[0].mapsURL == EmbassyMapsLink.url(for: precise.mission))
        #expect(result.pins[1].mapsURL == EmbassyMapsLink.url(for: approximate.mission))
        #expect(result.pins[0].mapsURL?.host == "maps.apple.com")
        // A city-centre location is searched by name and city, not pinned.
        #expect(result.pins[1].mapsURL?.absoluteString.contains("q=Embassy%20of%20Finland%20in%20Casablanca,%20Casablanca") == true)
        #expect(result.pins[1].mapsURL?.absoluteString.contains("sll=") == true)
    }

    @Test
    func aMissionListedTwiceIsPinnedOnce() throws {
        let one = mission("A", latitude: 34.05, longitude: -6.84)

        #expect(try #require(map(preview(own: [one, one]))).pins.count == 1)
    }

    // MARK: Text

    @Test
    func theCaptionCreditsAppleAndWikidata() throws {
        let result = try #require(map(preview(own: [mission("A", latitude: 34.05, longitude: -6.84)])))

        #expect(result.caption == "Map © Apple · embassy locations from Wikidata, approximate where marked")
        #expect(result.offlineNote == nil)
        #expect(result.accessibilityLabel == "Map of Morocco with 1 embassy location")
    }

    @Test
    func offlineAddsTheConnectionNoteAndKeepsTheCaption() throws {
        let offline = DashboardResourcePolicy(mode: .automatic, conditions: ResourceConditions(pathAvailable: false))
        let result = try #require(map(preview(own: [mission("A", latitude: 34.05, longitude: -6.84)]), policy: offline))

        #expect(result.offlineNote == "Map needs a connection")
        #expect(result.caption.hasPrefix("Map © Apple"))
    }

    @Test
    func openInMapsSearchesForTheCountryByName() throws {
        let result = try #require(map(preview()))

        #expect(result.openInMapsURL?.absoluteString == "https://maps.apple.com/?q=Morocco")
        #expect(TripMapPresentation.openInMapsTitle == "Open in Maps")
    }

    @Test
    func theCountrySearchKeepsAnAmpersandInsideTheQuery() throws {
        let url = try #require(EmbassyMapsLink.url(forPlaceNamed: "Bosnia & Herzegovina"))

        #expect(url.absoluteString == "https://maps.apple.com/?q=Bosnia%20%26%20Herzegovina")
    }

    @Test
    func theIdentityChangesWithTheCountryAndTheMissions() throws {
        let morocco = try #require(map(preview()))
        let portugal = try #require(map(preview(country: "PT")))
        let withMission = try #require(map(preview(own: [mission("A", latitude: 34.05, longitude: -6.84)])))

        #expect(Set([morocco.identity, portugal.identity, withMission.identity]).count == 3)
        #expect(try morocco.identity == #require(map(preview())).identity)
    }
}
