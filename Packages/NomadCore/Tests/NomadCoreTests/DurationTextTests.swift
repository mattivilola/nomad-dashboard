import Testing
@testable import NomadCore

struct DurationTextTests {
    @Test
    func writesMinutesAndHoursShort() {
        #expect(DurationText.hoursAndMinutes(45 * 60) == "45 min")
        #expect(DurationText.hoursAndMinutes(3_600) == "1 h")
        #expect(DurationText.hoursAndMinutes(3 * 3_600 + 11 * 60) == "3 h 11 min")
    }

    @Test
    func roundsToTheNearestMinuteWithAtLeastOne() {
        #expect(DurationText.hoursAndMinutes(0) == "1 min")
        #expect(DurationText.hoursAndMinutes(89) == "1 min")
        #expect(DurationText.hoursAndMinutes(91) == "2 min")
        #expect(DurationText.hoursAndMinutes(3_599) == "1 h")
    }
}
