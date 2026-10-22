# Release Flow

Nomad Dashboard is distributed directly outside the Mac App Store.

Read [docs/security.md](security.md) before adding any new integration that
needs credentials. Release-time convenience is not a valid reason to embed
private keys into tracked config or the shipped app bundle.

## Branch Policy

- `staging` is the integration branch.
- `main` is the official release branch.
- Finalize release candidates on `staging`, then merge or fast-forward them into `main` before cutting a public release.
- Public release tags use the exact format `vX.Y.Z` and must point at the same commit as `Config/Version.xcconfig`.

## One-Time Local Setup

1. Install and trust your Developer ID Application certificate in the login keychain.
2. Re-authenticate GitHub CLI:
   `gh auth login -h github.com`
3. Store notarization credentials in the keychain:
   `xcrun notarytool store-credentials NomadDashboardNotary --apple-id <apple-id> --team-id <team-id>`
   or use the repo helper:
   `make release-setup-notary APPLE_ID=<apple-id>`
4. Generate or import Sparkle signing keys:
   `generate_keys --account nomad-dashboard`
   or export an existing private key to the path referenced by `NOMAD_SPARKLE_PRIVATE_KEY_PATH`.
5. Create `Config/Signing.env` from `Config/Signing.example.env` and fill in:
   - `NOMAD_TEAM_ID`
   - `NOMAD_SIGNING_IDENTITY`
   - `NOMAD_NOTARY_PROFILE`
   - `NOMAD_GITHUB_REPOSITORY`
   - `NOMAD_SPARKLE_PRIVATE_KEY_PATH`
   - `NOMAD_SPARKLE_PUBLIC_ED_KEY`
   - optional `NOMAD_SPARKLE_BIN_DIR` if Sparkle CLI tools are not auto-discovered from repo-local `DerivedData` or Xcode's default DerivedData
6. Create `Config/AppConfig.local.xcconfig` from `Config/AppConfig.local.example.xcconfig` and set the approved `RELIEFWEB_APPNAME` there on the release machine. Keep this file local and out of git.
7. In the Apple Developer portal, open the App ID for `com.iloapps.NomadDashboard` and enable the WeatherKit capability before shipping a release build.
8. Local Debug builds default to unsigned mode so `make build`, `make run`, and `make rerun` work without Apple provisioning setup. If you want local WeatherKit access in the separate debug app, create a second App ID for `com.iloapps.NomadDashboard.dev`, enable WeatherKit there too, and add local values plus `DEBUG_CODE_SIGN_ENTITLEMENTS = App/NomadDashboard.entitlements` in `Config/Signing.debug.local.xcconfig`.
9. Optional for signed local Debug builds: set `NOMAD_DEBUG_ALLOW_PROVISIONING_UPDATES = true` in `Config/Signing.debug.local.xcconfig` to let `xcodebuild` request or refresh the `com.iloapps.NomadDashboard.dev` provisioning profile automatically.

10. Widgets and Siri/Shortcuts: the app embeds a WidgetKit extension (`com.iloapps.NomadDashboard.widgets`, debug `com.iloapps.NomadDashboard.dev.widgets`) and shares data with it through a team-prefixed App Group (`<TeamID>.com.iloapps.NomadDashboard`, debug `<TeamID>.com.iloapps.NomadDashboard.dev`). The group is set once as `APP_GROUP_IDENTIFIER` in `Config/*.xcconfig` and is in both entitlements files (`App/NomadDashboard.entitlements`, `App/Widgets/NomadDashboardWidgets.entitlements`). Team-prefixed groups are the macOS form that needs no App Group registration in the Developer portal. The extension is signed with the same Developer ID identity and needs no provisioning profile of its own, so `Config/Signing.local.xcconfig` (the app's profile) is deliberately not included by `Config/Widgets.Release.xcconfig`. Signed debug builds register the `.dev.widgets` App ID automatically when `NOMAD_DEBUG_ALLOW_PROVISIONING_UPDATES = true`; unsigned debug and CI builds have no App Group, so the widgets stay empty there and the app skips writing the widget snapshot.

11. Keep Awake with the lid closed: the app embeds a privileged launchd helper, `NomadDashboardPowerHelper`, that toggles the global `SleepDisabled` power setting. It is registered by the app with `SMAppService.daemon` (the user approves it once in System Settings > General > Login Items); there is no `sudoers` entry, `SMJobBless` or installer step. The bundle identifier of the app is set once as `NOMAD_APP_BUNDLE_IDENTIFIER` in `Config/Identity.Debug.xcconfig` and `Config/Identity.Release.xcconfig`; the helper's launchd label and Mach service name are that identifier plus `.PowerHelper` (`com.iloapps.NomadDashboard.PowerHelper`, debug `com.iloapps.NomadDashboard.dev.PowerHelper`, so both can be installed together). The helper binary is embedded in `Contents/Library/HelperTools/`, and its launchd property list is generated into `Contents/Library/LaunchDaemons/<label>.plist` by the app target's "Generate Power Helper launchd plist" build phase (`App/PowerHelper/generate-launchd-plist.sh`) so the per-configuration label is never written down twice. The helper embeds the app's bundle identifier and `DEVELOPMENT_TEAM` in its Info.plist and accepts XPC clients only from the app signed by that team; the app carries the team as `NomadTeamIdentifier`, so a build without a team has no working lid-closed mode. The helper takes its own `Config/PowerHelper.*.xcconfig` and, like the widget extension, needs no provisioning profile, so `Config/Signing.local.xcconfig` is not included by `Config/PowerHelper.Release.xcconfig`.

    Registration must be attempted for both `notRegistered` and `notFound` service states: a failed service lookup alone does not establish that the bundled helper is missing. Registration validates the bundle and surfaces the real macOS error. Verify a signed installed build on first use: approve the background helper if requested, confirm the laptop indicator becomes active and `pmset -g` reports `SleepDisabled 1`, stop the session and confirm it returns to its previous value. Also verify quitting during an active session restores the previous setting. Package tests use a fake registration service and never install a daemon.

    XPC error callbacks must be explicitly `@Sendable`: macOS invokes them on a background queue, and inheriting main-actor isolation crashes the app before it can display the connection error. The package regression test calls a unique nonexistent Mach service to exercise the real failure callback without installing a helper or changing power settings.

`Config/Signing.env` is ignored by git and should stay local to the release machine.
`Config/AppConfig.local.xcconfig` is also ignored by git and should stay local to developer or release machines.

## Release Artifacts

- Sparkle updates are published as `NomadDashboard-<version>.zip`.
- Manual installs are published as `NomadDashboard-<version>.dmg`.
- `appcast.xml` is published to the GitHub release and served from:
  `https://github.com/mattivilola/nomad-dashboard/releases/latest/download/appcast.xml`
- Release notes for both the GitHub release and Sparkle appcast are sourced from the matching version section in `CHANGELOG.md`.

## Release Checklist

1. Make sure `staging` contains the final release-ready changes. Run `make test`, `make build`, and `make lint` locally. After promotion to `main`, wait for its full GitHub CI run (including the app build) before cutting a release tag; CI also verifies compatibility with its older macOS SDK.
2. Merge or fast-forward `staging` into `main`.
3. Confirm `git status --short` is empty on `main`.
4. Update `CHANGELOG.md` under `## [Unreleased]`.
5. Cut the release version and tag on `main`, then push both automatically to `origin`:
   - `make release-patch`
   - `make release-minor`
   - `make release-major`
6. Run a local pipeline preview:
   `make release-dry-run`
7. Build, sign, notarize, staple, and package the release:
   `make release`
   - `make release` now does an upfront GitHub preflight and aborts immediately if the release tag has not been pushed yet.
   - Before publishing, verify any new integration follows the credential rules in `docs/security.md`: public values may be injected locally, but private credentials must not be bundled into the app.
8. Verify the GitHub release includes:
   - `NomadDashboard-<version>.zip`
   - `NomadDashboard-<version>.dmg`
   - `appcast.xml`
9. Install from the DMG, launch the app, and verify `Check for Updates` reaches the published GitHub appcast.
10. Verify the installed release can load current weather and WeatherKit-backed travel weather alerts.
11. Verify the widgets: right-click the desktop, choose Edit Widgets, add Glance, Safety and Daylight from Nomad Dashboard, and confirm they show data and "Updated" times after the app has run for a minute. `pluginkit -mAvv -p com.apple.widgetkit-extension | grep -i nomad` lists the registered extension. Also run the Emergency Number action from Shortcuts. The first release that ships the widgets is the first to carry the App Group under Developer ID signing, so treat a widget that stays empty as a signing problem: check `codesign -d --entitlements - "/Applications/Nomad Dashboard.app"` and the extension for `com.apple.security.application-groups`, and if macOS rejects the group, enable the App Groups capability on both App IDs and add the group to their Developer ID profiles.

## Commands

- `make archive`
  Creates the release archive. When local config files are present, release signing metadata and the ReliefWeb app name are injected at build time.
- `make dmg`
  Creates a DMG from the archived app without regenerating tracked branding exports.
- `make release-dry-run`
  Prints the exact version, tag, repository, feed URL, and artifact paths the release pipeline will use.
- `make release-check-setup`
  Verifies the local release prerequisites before you start: the widget extension's project files (team-prefixed App Group in both entitlements files, sandbox on the extension, release bundle identifier), command availability, `Config/Signing.env`, Developer ID signing identity, GitHub CLI auth, Sparkle CLI tools, and the stored notary profile. If Apple has blocked notarization because a required agreement is unsigned or expired, this usually surfaces in the notary-profile check once the profile exists.
- `make release-setup-notary APPLE_ID=<apple-id>`
  Stores or refreshes the `notarytool` keychain profile from `Config/Signing.env`. `notarytool` will still prompt interactively for the app-specific password, but the profile name and Team ID no longer need to be typed manually.
- `make release`
  Verifies the pushed release tag first, then runs signing/notarization and publishes the versioned Sparkle zip, DMG, and `appcast.xml` to GitHub Releases.
  If you recently cleaned `DerivedData`, run `make build` once before publishing so Sparkle's CLI tools are downloaded again, or point `NOMAD_SPARKLE_BIN_DIR` at the Sparkle `bin` directory directly.
- `make release-patch`, `make release-minor`, `make release-major`
  Prepare the release locally, then push the current branch and the new tag to `origin`.

## Notes

- Version metadata lives in `Config/Version.xcconfig`. The widget extension takes its version and build number from the same file.
- The archive embeds `Contents/PlugIns/NomadDashboardWidgets.appex`. `make release` re-signs nested code inside out: the Sparkle helpers and framework, then the widget extension, then the app that seals them, all with the Developer ID identity, `--timestamp`, the hardened runtime and the preserved entitlements. It then checks that the app carries a team-prefixed App Group and that the extension has the release bundle identifier, the App Sandbox (WidgetKit requires it) and the same App Group, is not ad-hoc signed and has the hardened runtime. `codesign --verify --deep --strict` and notarization cover the extension because it is nested in the app.
- `make release` also signs the power helper (`Contents/Library/HelperTools/NomadDashboardPowerHelper`) in that inside-out order, after the Sparkle components and before the widget extension and the app, with the Developer ID identity, `--timestamp`, the hardened runtime and the preserved identifier (the launchd label). `assert_archive_power_helper` then checks that the launchd plist has the expected `Label`, `BundleProgram`, Mach service and associated app, and that the helper is not ad-hoc signed, has the hardened runtime and a secure timestamp, is signed by `NOMAD_TEAM_ID` under the identifier `com.iloapps.NomadDashboard.PowerHelper`, and trusts the same team the app names in `NomadTeamIdentifier`. `make release-check-setup` (`check-release-setup.sh`) checks the helper's project files. Notarization covers the helper because it is nested in the app.
- Sparkle updates replace the whole app bundle, so the extension and the helper update with it.
- App Group validation treats a failed entitlement-plist extraction as a missing entitlement. Diagnostics from `plutil` are never accepted as an App Group value, including on older macOS release machines.
- Sparkle remains unavailable in local/dev builds until both `SUFeedURL` and `SUPublicEDKey` are injected into the app bundle.
- Release builds must not ship a shared `TankerkonigAPIKey`; Germany fuel support now depends on a user-supplied key stored in app settings.
- Treat any new provider the same way: if it needs a private credential, redesign the feature so the client does not ship that shared secret.
- Debug builds use a separate app identity (`Nomad Dashboard Dev`, bundle ID `com.iloapps.NomadDashboard.dev`) so they can run alongside production with separate macOS privacy permissions.
- Local Debug builds are unsigned unless `Config/Signing.debug.local.xcconfig` enables local automatic signing.
- Signed local Debug builds use your normal macOS home directory so Xcode can access the local developer account state; unsigned and CI builds still use an isolated temporary home for reproducible caches.
- When signed local Debug provisioning fails, `make build`, `make run`, and `make rerun` automatically retry once as unsigned builds so the app still launches, but WeatherKit remains unavailable in that fallback build.
- `make brand-assets` is still available for design-time regeneration of tracked branding assets, but it is no longer part of normal DMG packaging.
- The release-preparation script still drafts notes from commits since the latest `v*` tag and merges any curated `Unreleased` notes.
