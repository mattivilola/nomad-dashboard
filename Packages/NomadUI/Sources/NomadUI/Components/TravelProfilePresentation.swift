import NomadCore

/// Copy and affordances for the "Travel profile" settings section, kept out of the view so it can be unit tested.
public struct TravelProfileSettingsPresentation: Equatable {
    public static let keptCustomOrderNote = "Your custom card order is kept."
    public static let useRecommendedOrderTitle = "Use recommended order"
    public static let menuBarHeadsUpTitle = "Show the top heads-up in the menu bar"
    public static let menuBarHeadsUpFooter = "Only caution or attention items replace the temperature; otherwise the menu bar looks as usual."

    public let profile: TravelProfile
    public let isUsingRecommendedOrder: Bool

    public init(profile: TravelProfile, isUsingRecommendedOrder: Bool) {
        self.profile = profile
        self.isUsingRecommendedOrder = isUsingRecommendedOrder
    }

    /// The profile summary, followed by a note that a customized card order stays untouched.
    public var footer: String {
        isUsingRecommendedOrder ? profile.summary : "\(profile.summary) \(Self.keptCustomOrderNote)"
    }

    /// Offered only when a customized order is in place, so the profile's own order can be restored in one tap.
    public var offersRecommendedOrder: Bool {
        isUsingRecommendedOrder == false
    }

    /// The card order "Use recommended order" and "Reset Dashboard Layout" restore.
    public var recommendedOrder: [DashboardCardID] {
        DashboardCardID.defaultOrder(for: profile)
    }
}
