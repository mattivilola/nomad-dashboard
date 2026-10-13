import Foundation
@testable import NomadPowerHelperKit
import Testing

struct NomadPowerHelperSupportTests {
    @Test
    func labelsDifferBetweenDevAndReleaseBuilds() {
        #expect(NomadPowerHelperIdentity.label(appBundleIdentifier: "com.iloapps.NomadDashboard") == "com.iloapps.NomadDashboard.PowerHelper")
        #expect(NomadPowerHelperIdentity.label(appBundleIdentifier: "com.iloapps.NomadDashboard.dev") == "com.iloapps.NomadDashboard.dev.PowerHelper")
        #expect(NomadPowerHelperIdentity.launchdPlistName(label: "a.b.PowerHelper") == "a.b.PowerHelper.plist")
    }

    @Test
    func requirementsNameTheIdentifierAndTheTeam() {
        let client = NomadPowerHelperIdentity.clientCodeSigningRequirement(
            appBundleIdentifier: "com.iloapps.NomadDashboard",
            teamIdentifier: "MM233FKU38"
        )
        #expect(client == "anchor apple generic and identifier \"com.iloapps.NomadDashboard\" and certificate leaf[subject.OU] = \"MM233FKU38\"")

        let helper = NomadPowerHelperIdentity.helperCodeSigningRequirement(
            helperLabel: "com.iloapps.NomadDashboard.PowerHelper",
            teamIdentifier: "MM233FKU38"
        )
        #expect(helper?.contains("identifier \"com.iloapps.NomadDashboard.PowerHelper\"") == true)
    }

    @Test
    func requirementsAreRefusedWithoutAValidTeamOrIdentifier() {
        #expect(NomadPowerHelperIdentity.clientCodeSigningRequirement(appBundleIdentifier: "com.iloapps.NomadDashboard", teamIdentifier: "") == nil)
        #expect(NomadPowerHelperIdentity.clientCodeSigningRequirement(appBundleIdentifier: "com.iloapps.NomadDashboard", teamIdentifier: "short") == nil)
        #expect(NomadPowerHelperIdentity.clientCodeSigningRequirement(appBundleIdentifier: "", teamIdentifier: "MM233FKU38") == nil)
        #expect(NomadPowerHelperIdentity.clientCodeSigningRequirement(appBundleIdentifier: "a\" or anchor apple or \"b", teamIdentifier: "MM233FKU38") == nil)
        #expect(NomadPowerHelperIdentity.helperCodeSigningRequirement(helperLabel: "x y", teamIdentifier: "MM233FKU38") == nil)
    }

    @Test
    func pmsetOutputIsParsedForTheSleepDisabledLine() {
        let enabled = " System-wide power settings:\n SleepDisabled\t\t1\n Currently in use:\n sleep 1\n"
        let disabled = " System-wide power settings:\n SleepDisabled\t\t0\n"
        #expect(PmsetSleepDisabledSetting.parseSleepDisabled(enabled))
        #expect(PmsetSleepDisabledSetting.parseSleepDisabled(disabled) == false)
        #expect(PmsetSleepDisabledSetting.parseSleepDisabled(" sleep 1\n displaysleep 10\n") == false)
        #expect(PmsetSleepDisabledSetting.parseSleepDisabled("") == false)
    }

    @Test
    func fileJournalRoundTripsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("helper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let journal = FileLidClosedJournal(directoryURL: directory)
        let record = LidClosedJournalRecord(priorSleepDisabled: false, endsAt: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(try journal.load() == nil)
        try journal.save(record)
        #expect(try journal.load() == record)

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(FileLidClosedJournal.fileName).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)

        try journal.delete()
        #expect(try journal.load() == nil)
        try journal.delete()
    }

    @Test
    func defaultJournalDirectoryIsUnderLibraryApplicationSupport() {
        #expect(FileLidClosedJournal.defaultDirectoryURL(label: "a.b.PowerHelper").path == "/Library/Application Support/a.b.PowerHelper")
    }
}
