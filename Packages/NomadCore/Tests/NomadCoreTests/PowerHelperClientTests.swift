import Foundation
@testable import NomadCore
import ServiceManagement
import Testing

@MainActor
struct PowerHelperClientTests {
    @Test(arguments: [SMAppService.Status.notFound, .notRegistered])
    func firstUseRegistersTheHelperAndRequestsApproval(initialStatus: SMAppService.Status) {
        let service = FakePowerHelperService(status: initialStatus, statusAfterRegistration: .requiresApproval)
        let client = makeClient(service: service)

        #expect(client.prepare() == .requiresApproval)
        #expect(service.registrationCount == 1)
        #expect(client.status == .requiresApproval)
    }

    @Test
    func registrationCanImmediatelyEnableAnAlreadyApprovedHelper() {
        let service = FakePowerHelperService(status: .notFound, statusAfterRegistration: .enabled)

        #expect(makeClient(service: service).prepare() == .enabled)
        #expect(service.registrationCount == 1)
    }

    @Test(arguments: [SMAppService.Status.enabled, .requiresApproval])
    func existingRegistrationIsNotRepeated(status: SMAppService.Status) {
        let service = FakePowerHelperService(status: status, statusAfterRegistration: status)
        let client = makeClient(service: service)

        #expect(client.prepare() == client.status)
        #expect(service.registrationCount == 0)
    }

    @Test
    func pendingApprovalIsPreservedEvenWhenRegisterThrows() {
        let service = FakePowerHelperService(status: .notFound, statusAfterRegistration: .requiresApproval)
        service.registrationError = LidClosedSleepError("Approval needed")

        #expect(makeClient(service: service).prepare() == .requiresApproval)
        #expect(service.registrationCount == 1)
    }

    @Test
    func missingOrInvalidBundleReportsTheActualRegistrationFailure() {
        let service = FakePowerHelperService(status: .notFound, statusAfterRegistration: .notFound)
        service.registrationError = LidClosedSleepError("Unable to read the helper's launchd plist")

        #expect(makeClient(service: service).prepare() == .unavailable("Unable to read the helper's launchd plist"))
        #expect(service.registrationCount == 1)
    }

    @Test
    func unchangedStatusAfterRegistrationDoesNotClaimSuccess() {
        let service = FakePowerHelperService(status: .notFound, statusAfterRegistration: .notFound)

        guard case let .unavailable(message) = makeClient(service: service).prepare() else {
            Issue.record("A helper macOS still cannot find must not appear ready")
            return
        }
        #expect(message.contains("after registration"))
        #expect(service.registrationCount == 1)
    }

    @Test
    func unsignedBuildNeverRegistersThePrivilegedHelper() {
        let service = FakePowerHelperService(status: .notFound, statusAfterRegistration: .enabled)
        let client = PowerHelperClient(
            appBundleIdentifier: "com.iloapps.NomadDashboard",
            teamIdentifier: nil,
            service: service
        )

        guard case .unavailable = client.prepare() else {
            Issue.record("Unsigned builds must refuse registration")
            return
        }
        #expect(service.registrationCount == 0)
    }

    private func makeClient(service: FakePowerHelperService) -> PowerHelperClient {
        PowerHelperClient(
            appBundleIdentifier: "com.iloapps.NomadDashboard",
            teamIdentifier: "MM233FKU38",
            service: service
        )
    }
}

@MainActor
private final class FakePowerHelperService: PowerHelperServiceManaging {
    var status: SMAppService.Status
    let statusAfterRegistration: SMAppService.Status
    var registrationError: LidClosedSleepError?
    private(set) var registrationCount = 0

    init(status: SMAppService.Status, statusAfterRegistration: SMAppService.Status) {
        self.status = status
        self.statusAfterRegistration = statusAfterRegistration
    }

    func register() throws {
        registrationCount += 1
        status = statusAfterRegistration
        if let registrationError {
            throw registrationError
        }
    }
}
