import Foundation

/// An optional capability for country-day stores that keep user corrections separate from observations.
public protocol EditableVisitedCountryDaysStore: VisitedCountryDaysStore {
    func setOverride(_ override: VisitedCountryDayOverride) async throws
    func restoreObservation(for day: VisitedCountryDayStamp) async throws
}
