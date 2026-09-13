@testable import NomadUI
import Testing

struct NomadsCityFormattingTests {
    @Test func unavailableMetricsNeverLookLikeFreeLivingOrZeroConnectivity() {
        #expect(NomadsCityFormatting.monthlyUSD(nil) == "Not available")
        #expect(NomadsCityFormatting.monthlyUSD(0) == "Not available")
        #expect(NomadsCityFormatting.monthlyUSD(-1) == "Not available")
        #expect(NomadsCityFormatting.internet(0) == "Not available")
        #expect(NomadsCityFormatting.internet(.infinity) == "Not available")
    }

    @Test func validZeroRatingIsPreservedButInvalidRatingsAreHidden() {
        #expect(NomadsCityFormatting.score(0) != "Not available")
        #expect(NomadsCityFormatting.score(5) != "Not available")
        #expect(NomadsCityFormatting.score(5.1) == "Not available")
        #expect(NomadsCityFormatting.score(-1) == "Not available")
        #expect(NomadsCityFormatting.score(.nan) == "Not available")
    }
}
