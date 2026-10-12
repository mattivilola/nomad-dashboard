import Foundation

/// How a destination's price level reads next to the user's home country for one category.
public enum PriceLevelVerdict: String, Codable, Equatable, Sendable {
    case cheaper
    case aboutTheSame
    case pricier
}

/// One category of the destination-versus-home price comparison.
public struct PriceLevelDifference: Codable, Equatable, Sendable, Identifiable {
    public let kind: LocalPriceIndicatorKind
    /// Signed whole-percent difference of the destination from home (`destination / home - 1`), so -30
    /// means the destination is 30% cheaper than home and 15 means it is 15% pricier.
    public let percentDifference: Int

    public init(kind: LocalPriceIndicatorKind, percentDifference: Int) {
        self.kind = kind
        self.percentDifference = percentDifference
    }

    public var id: LocalPriceIndicatorKind {
        kind
    }

    public var verdict: PriceLevelVerdict {
        if abs(percentDifference) <= PriceLevelComparison.aboutTheSameBandPercent {
            return .aboutTheSame
        }

        return percentDifference < 0 ? .cheaper : .pricier
    }
}

/// Compares two countries' price-level indices category by category. Both sides must use the same
/// baseline (e.g. Eurostat's EU27 = 100) for the ratio to mean anything.
public enum PriceLevelComparison {
    /// Differences up to and including this many whole percent read as "about the same".
    public static let aboutTheSameBandPercent = 3

    /// One difference per category present with a positive index on both sides, in
    /// `LocalPriceIndicatorKind.allCases` order. Categories missing on either side are left out.
    public static func compare(
        destination: [LocalPriceIndicatorKind: Double],
        home: [LocalPriceIndicatorKind: Double]
    ) -> [PriceLevelDifference] {
        LocalPriceIndicatorKind.allCases.compactMap { kind in
            guard let destinationIndex = destination[kind], destinationIndex > 0,
                  let homeIndex = home[kind], homeIndex > 0
            else {
                return nil
            }

            let percent = ((destinationIndex - homeIndex) * 100 / homeIndex).rounded(.toNearestOrAwayFromZero)
            return PriceLevelDifference(kind: kind, percentDifference: Int(percent))
        }
    }

    /// Plain-English line such as "Groceries ~30% cheaper than Finland", "Meals out ~15% pricier than
    /// Finland" or "Overall about the same as Finland".
    public static func text(
        for difference: PriceLevelDifference,
        homeCountryCode: String,
        locale: Locale = .current
    ) -> String {
        text(for: difference, homeCountryName: CountryNames.displayName(forCode: homeCountryCode, locale: locale))
    }

    public static func text(for difference: PriceLevelDifference, homeCountryName: String) -> String {
        let label = label(for: difference.kind)
        let magnitude = abs(difference.percentDifference)

        switch difference.verdict {
        case .aboutTheSame:
            return "\(label) about the same as \(homeCountryName)"
        case .cheaper:
            return "\(label) ~\(magnitude)% cheaper than \(homeCountryName)"
        case .pricier:
            return "\(label) ~\(magnitude)% pricier than \(homeCountryName)"
        }
    }

    private static func label(for kind: LocalPriceIndicatorKind) -> String {
        switch kind {
        case .mealOut:
            "Meals out"
        case .groceries:
            "Groceries"
        case .rentOneBedroom:
            "1BR rent"
        case .overall:
            "Overall"
        }
    }
}
