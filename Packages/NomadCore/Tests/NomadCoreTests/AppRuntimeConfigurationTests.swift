import NomadCore
import Testing

struct AppRuntimeConfigurationTests {
    @Test
    func tankerkonigAPIKeyUsesUserSettingWhenEnvironmentIsEmpty() {
        let resolved = AppRuntimeConfiguration.resolveTankerkonigAPIKey(
            userSetting: "stored-user-key",
            environment: [:]
        )

        #expect(resolved == "stored-user-key")
    }

    @Test
    func tankerkonigAPIKeyReturnsNilWhenSettingAndEnvironmentAreEmpty() {
        let resolved = AppRuntimeConfiguration.resolveTankerkonigAPIKey(
            userSetting: "   ",
            environment: [:]
        )

        #expect(resolved == nil)
    }

    @Test
    func tankerkonigAPIKeyEnvironmentOverrideWins() {
        let resolved = AppRuntimeConfiguration.resolveTankerkonigAPIKey(
            userSetting: "stored-user-key",
            environment: ["TANKERKOENIG_APIKEY": "env-key-override"]
        )

        #expect(resolved == "env-key-override")
    }
}
