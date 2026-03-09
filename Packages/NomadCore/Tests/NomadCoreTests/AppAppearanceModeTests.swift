import NomadCore
import Testing

struct AppAppearanceModeTests {
    @Test
    func systemTogglesToLightWhenResolvedAppearanceIsDark() {
        #expect(AppAppearanceMode.system.toggled(resolvedSystemAppearanceIsDark: true) == .light)
    }

    @Test
    func systemTogglesToDarkWhenResolvedAppearanceIsLight() {
        #expect(AppAppearanceMode.system.toggled(resolvedSystemAppearanceIsDark: false) == .dark)
    }

    @Test
    func darkTogglesToLight() {
        #expect(AppAppearanceMode.dark.toggled(resolvedSystemAppearanceIsDark: true) == .light)
    }

    @Test
    func lightTogglesToDark() {
        #expect(AppAppearanceMode.light.toggled(resolvedSystemAppearanceIsDark: false) == .dark)
    }
}
