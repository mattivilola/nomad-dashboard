@testable import NomadCore
import Testing

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

    @Test
    func countdownShowsMinutesAndSecondsUnderOneHour() {
        #expect(DurationText.countdown(249) == "4:09")
        #expect(DurationText.countdown(0) == "0:00")
        #expect(DurationText.countdown(59) == "0:59")
        #expect(DurationText.countdown(3_599) == "59:59")
    }

    @Test
    func countdownShowsHoursFromOneHour() {
        #expect(DurationText.countdown(3_600) == "1:00:00")
        #expect(DurationText.countdown(3_909) == "1:05:09")
        #expect(DurationText.countdown(8 * 3_600) == "8:00:00")
    }

    @Test
    func countdownFloorsToWholeSecondsAndNeverGoesNegative() {
        #expect(DurationText.countdown(249.9) == "4:09")
        #expect(DurationText.countdown(0.4) == "0:00")
        #expect(DurationText.countdown(-12) == "0:00")
    }
}
