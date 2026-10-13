import Foundation
import NomadCore
@testable import NomadUI
import Testing

struct KeepAwakePresentationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func timedSessionShowsTimeLeft() {
        let session = KeepAwakeSession(
            startedAt: start,
            endsAt: start.addingTimeInterval(2 * 3_600),
            keepsDisplayOn: true,
            duration: .twoHours
        )
        let presentation = KeepAwakePresentation(session: session)

        #expect(presentation.statusText(at: start.addingTimeInterval(17 * 60 + 50)) == "Awake · 1:42:10 left")
        #expect(presentation.statusText(at: start.addingTimeInterval(2 * 3_600 - 249)) == "Awake · 4:09 left")
    }

    @Test
    func timedSessionNeverShowsNegativeTime() {
        let session = KeepAwakeSession(
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            keepsDisplayOn: true,
            duration: .fifteenMinutes
        )

        #expect(KeepAwakePresentation(session: session).statusText(at: start.addingTimeInterval(1_000)) == "Awake · 0:00 left")
    }

    @Test
    func indefiniteSessionShowsTimeElapsed() {
        let session = KeepAwakeSession(startedAt: start, endsAt: nil, keepsDisplayOn: false, duration: .indefinite)
        let presentation = KeepAwakePresentation(session: session)

        #expect(presentation.statusText(at: start.addingTimeInterval(12 * 60 + 4)) == "Awake until stopped · 12:04")
        #expect(presentation.statusText(at: start.addingTimeInterval(3_600 + 5 * 60 + 9)) == "Awake until stopped · 1:05:09")
    }
}

struct KeepAwakeLidClosedPresentationTests {
    @Test
    func offShowsNothing() {
        #expect(KeepAwakeLidClosedPresentation(state: .off).indicator == nil)
    }

    @Test
    func activeShowsAHighlightedLaptop() {
        #expect(
            KeepAwakeLidClosedPresentation(state: .active).indicator
                == .icon(systemImage: "laptopcomputer", isHighlighted: true, help: "Stays awake with the lid closed")
        )
    }

    @Test
    func startingShowsADimmedLaptop() {
        #expect(
            KeepAwakeLidClosedPresentation(state: .starting).indicator
                == .icon(systemImage: "laptopcomputer", isHighlighted: false, help: "Starting lid-closed mode")
        )
    }

    @Test
    func needingApprovalShowsTheAllowButton() {
        #expect(KeepAwakeLidClosedPresentation(state: .needsApproval).indicator == .allowButton)
        #expect(KeepAwakeLidClosedPresentation.allowButtonTitle == "Allow Lid Closed")
    }

    @Test
    func unavailableShowsADimmedSlashedLaptopWithTheReason() {
        #expect(
            KeepAwakeLidClosedPresentation(state: .unavailable("Not signed")).indicator
                == .icon(systemImage: "laptopcomputer.slash", isHighlighted: false, help: "Not signed")
        )
    }

    @Test
    func menuNoticePrefersTheEndReasonOverTheError() {
        #expect(KeepAwakeLidClosedPresentation.menuNotice(endReason: "Keep Awake ended: battery low", errorMessage: "Oops") == "Keep Awake ended: battery low")
        #expect(KeepAwakeLidClosedPresentation.menuNotice(endReason: nil, errorMessage: "Oops") == "Oops")
        #expect(KeepAwakeLidClosedPresentation.menuNotice(endReason: nil, errorMessage: nil) == nil)
    }
}
