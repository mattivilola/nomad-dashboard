import Foundation
@testable import NomadCore
import Testing

struct PriceLevelComparisonTests {
    @Test
    func percentDifferenceIsDestinationOverHomeRoundedToWholePercent() {
        let differences = PriceLevelComparison.compare(
            destination: [.groceries: 70, .mealOut: 115.4, .overall: 99],
            home: [.groceries: 100, .mealOut: 100, .overall: 100]
        )

        #expect(differences == [
            PriceLevelDifference(kind: .mealOut, percentDifference: 15),
            PriceLevelDifference(kind: .groceries, percentDifference: -30),
            PriceLevelDifference(kind: .overall, percentDifference: -1)
        ])
    }

    @Test
    func differenceIsRelativeToHomeNotToTheBaseline() {
        // 90 against a home of 120 is 25% cheaper, whatever the EU27 = 100 baseline says.
        let differences = PriceLevelComparison.compare(destination: [.overall: 90], home: [.overall: 120])

        #expect(differences.first?.percentDifference == -25)
    }

    @Test
    func roundsHalfAwayFromZero() {
        let up = PriceLevelComparison.compare(destination: [.overall: 112.5], home: [.overall: 100])
        let down = PriceLevelComparison.compare(destination: [.overall: 87.5], home: [.overall: 100])

        #expect(up.first?.percentDifference == 13)
        #expect(down.first?.percentDifference == -13)
    }

    @Test
    func aboutTheSameBandIsPlusOrMinusThreePercent() {
        let verdicts = [-4, -3, 0, 3, 4].map { PriceLevelDifference(kind: .overall, percentDifference: $0).verdict }

        #expect(verdicts == [.cheaper, .aboutTheSame, .aboutTheSame, .aboutTheSame, .pricier])
    }

    @Test
    func bandAppliesToTheRoundedPercent() {
        let inside = PriceLevelComparison.compare(destination: [.overall: 103.4], home: [.overall: 100])
        let outside = PriceLevelComparison.compare(destination: [.overall: 103.5], home: [.overall: 100])

        #expect(inside.first?.verdict == .aboutTheSame)
        #expect(outside.first?.verdict == .pricier)
    }

    @Test
    func categoriesMissingOnEitherSideOrInvalidAreSkipped() {
        let differences = PriceLevelComparison.compare(
            destination: [.groceries: 80, .overall: 90, .mealOut: 0],
            home: [.groceries: 100, .mealOut: 100, .rentOneBedroom: 100]
        )

        #expect(differences.map(\.kind) == [.groceries])
        #expect(PriceLevelComparison.compare(destination: [:], home: [.overall: 100]).isEmpty)
        #expect(PriceLevelComparison.compare(destination: [.overall: 100], home: [.overall: 0]).isEmpty)
    }

    @Test
    func textReadsCheaperPricierAndAboutTheSame() {
        let locale = Locale(identifier: "en_US")

        #expect(
            PriceLevelComparison.text(
                for: PriceLevelDifference(kind: .groceries, percentDifference: -30),
                homeCountryCode: "FI",
                locale: locale
            ) == "Groceries ~30% cheaper than Finland"
        )
        #expect(
            PriceLevelComparison.text(
                for: PriceLevelDifference(kind: .mealOut, percentDifference: 15),
                homeCountryCode: "fi",
                locale: locale
            ) == "Meals out ~15% pricier than Finland"
        )
        #expect(
            PriceLevelComparison.text(
                for: PriceLevelDifference(kind: .overall, percentDifference: 2),
                homeCountryCode: "FI",
                locale: locale
            ) == "Overall about the same as Finland"
        )
    }

    @Test
    func textFallsBackToTheCodeWhenTheSystemHasNoName() {
        let text = PriceLevelComparison.text(
            for: PriceLevelDifference(kind: .overall, percentDifference: 10),
            homeCountryCode: "zz",
            locale: Locale(identifier: "en_US")
        )

        #expect(text == "Overall ~10% pricier than ZZ")
    }
}
