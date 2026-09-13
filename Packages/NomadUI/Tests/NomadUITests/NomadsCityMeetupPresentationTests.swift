import Foundation
@testable import NomadUI
import Testing

struct NomadsCityMeetupPresentationTests {
    @Test func acceptsTodayAndFutureDatesButHidesPastOrMalformedDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2_026, month: 9, day: 11, hour: 15)))

        #expect(NomadsCityMeetupPresentation.isUpcoming(dateString: "2026-09-11", now: now, calendar: calendar))
        #expect(NomadsCityMeetupPresentation.isUpcoming(dateString: "2026-09-12", now: now, calendar: calendar))
        #expect(!NomadsCityMeetupPresentation.isUpcoming(dateString: "2026-09-10", now: now, calendar: calendar))
        #expect(!NomadsCityMeetupPresentation.isUpcoming(dateString: "2026-02-30", now: now, calendar: calendar))
        #expect(!NomadsCityMeetupPresentation.isUpcoming(dateString: "next Tuesday", now: now, calendar: calendar))
    }
}
