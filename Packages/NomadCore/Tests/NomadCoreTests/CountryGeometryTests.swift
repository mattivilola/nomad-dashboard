import Foundation
import Testing
@testable import NomadCore

struct CountryGeometryTests {
    @Test
    func moroccoHasABoxAroundItsTerritory() throws {
        let region = try #require(CountryGeometry.boundingRegion(forCountryCode: "MA"))

        #expect(region.minLatitude < 28 && region.maxLatitude > 35.5)
        #expect(region.minLongitude < -12 && region.maxLongitude > -2)
        #expect(region.crossesAntimeridian == false)
        #expect(region.minLongitude <= region.maxLongitude)
    }

    @Test
    func finlandIsTheMainlandOnly() throws {
        let region = try #require(CountryGeometry.boundingRegion(forCountryCode: "fi"))

        #expect(abs(region.minLatitude - 59.8) < 0.5)
        #expect(abs(region.maxLatitude - 70.1) < 0.5)
        #expect(abs(region.minLongitude - 20.6) < 0.5)
        #expect(abs(region.maxLongitude - 31.5) < 0.5)
        #expect(abs(region.centerLongitude - 26) < 1)
    }

    @Test
    func fijiCrossesTheAntimeridianWithoutWrappingTheWorld() throws {
        let region = try #require(CountryGeometry.boundingRegion(forCountryCode: "FJ"))

        // Viti Levu is near 178 E and Taveuni near 180 W: one box from about 177 E to 180.2 E.
        #expect(region.crossesAntimeridian)
        #expect(region.minLongitude > 176 && region.minLongitude < 178)
        #expect(region.maxLongitude > 180 && region.maxLongitude < 182)
        #expect(region.longitudeSpan < 6)
        #expect(region.centerLongitude > 178 && region.centerLongitude <= 180)
        #expect(region.minLatitude < -18 && region.maxLatitude > -16.1)
    }

    @Test
    func farFlungTerritoriesAreLeftOut() throws {
        // The contiguous states, not Alaska or Hawaii.
        let unitedStates = try #require(CountryGeometry.boundingRegion(forCountryCode: "US"))
        #expect(unitedStates.minLatitude > 24 && unitedStates.maxLatitude < 50)
        #expect(unitedStates.minLongitude > -126 && unitedStates.maxLongitude < -66)

        // Metropolitan France, not French Guiana.
        let france = try #require(CountryGeometry.boundingRegion(forCountryCode: "FR"))
        #expect(france.minLatitude > 40 && france.maxLongitude < 10 && france.minLongitude > -6)

        // Norway's mainland, not Svalbard.
        let norway = try #require(CountryGeometry.boundingRegion(forCountryCode: "NO"))
        #expect(norway.maxLatitude < 72)
    }

    @Test
    func islandGroupsStayWhole() throws {
        let indonesia = try #require(CountryGeometry.boundingRegion(forCountryCode: "ID"))
        #expect(indonesia.minLongitude < 96 && indonesia.maxLongitude > 140)
        #expect(indonesia.minLatitude < -9 && indonesia.maxLatitude > 5)
    }

    @Test
    func russiaSpansTheAntimeridianAsOneBox() throws {
        let russia = try #require(CountryGeometry.boundingRegion(forCountryCode: "RU"))
        #expect(russia.crossesAntimeridian)
        #expect(russia.longitudeSpan < 180)
        #expect(russia.centerLongitude > 100 && russia.centerLongitude < 130)
    }

    @Test
    func smallStatesTheShapesLeaveOutHaveApproximateExtents() throws {
        let singapore = try #require(CountryGeometry.boundingRegion(forCountryCode: "SG"))
        #expect(singapore.minLatitude < 1.3 && singapore.maxLatitude > 1.4)
        #expect(singapore.minLongitude < 103.7 && singapore.maxLongitude > 103.9)
    }

    @Test
    func anUnknownOrMissingCodeHasNoBox() {
        #expect(CountryGeometry.boundingRegion(forCountryCode: "ZZ") == nil)
        #expect(CountryGeometry.boundingRegion(forCountryCode: "") == nil)
        #expect(CountryGeometry.boundingRegion(forCountryCode: "Morocco") == nil)
        #expect(CountryGeometry.boundingRegion(forCountryCode: nil) == nil)
    }

    @Test
    func everyBoxIsOrderedAndInRange() throws {
        // Every country the trip planner can pick has a box that makes sense.
        for code in ["AE", "AU", "BR", "CA", "CL", "DK", "ES", "GB", "IN", "JP", "KE", "NZ", "PT", "TH", "ZA"] {
            let region = try #require(CountryGeometry.boundingRegion(forCountryCode: code), "\(code)")
            #expect(region.minLatitude < region.maxLatitude)
            #expect(region.minLongitude < region.maxLongitude)
            #expect(region.minLatitude >= -90 && region.maxLatitude <= 90)
            #expect(region.minLongitude >= -180 && region.maxLongitude <= 360)
            #expect(region.latitudeSpan < 90)
        }
    }

    @Test
    func theMissionMarkersOfATripAreAlreadyOnThePreview() {
        // A planned trip's own and fallback missions, with coordinates and `isApproximateLocation`, are
        // `TripPreview.Embassy` values, so the trip map needs no extra model.
        let now = Date(timeIntervalSince1970: 1_791_806_400)
        let trip = PlannedTrip(countryCode: "MA", startDate: now, endDate: now.addingTimeInterval(86_400 * 3))
        let preview = TripPreview.make(
            trip: trip,
            settings: AppSettings(citizenshipCountryCodes: ["FI"], plannedTrips: [trip]),
            countryDays: [],
            homeTimeZoneIdentifier: nil,
            now: now
        )

        let missions = (preview.embassy?.ownMissions ?? []) + (preview.embassy?.fallbackMissions ?? [])
        #expect(missions.isEmpty == false)
        #expect(missions.allSatisfy { $0.mission.hostCountry == "MA" })
    }
}
