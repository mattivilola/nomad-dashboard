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

`Config/Signing.env` is ignored by git and should stay local to the release machine.
`Config/AppConfig.local.xcconfig` is also ignored by git and should stay local to developer or release machines.

## Release Artifacts

- Sparkle updates are published as `NomadDashboard-<version>.zip`.
- Manual installs are published as `NomadDashboard-<version>.dmg`.
- `appcast.xml` is published to the GitHub release and served from:
  `https://github.com/mattivilola/nomad-dashboard/releases/latest/download/appcast.xml`
- Release notes for both the GitHub release and Sparkle appcast are sourced from the matching version section in `CHANGELOG.md`.

## Release Checklist

1. Make sure `staging` contains the final release-ready changes.
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

## Commands

- `make archive`
  Creates the release archive. When local config files are present, release signing metadata and the ReliefWeb app name are injected at build time.
- `make dmg`
  Creates a DMG from the archived app without regenerating tracked branding exports.
- `make release-dry-run`
  Prints the exact version, tag, repository, feed URL, and artifact paths the release pipeline will use.
- `make release-check-setup`
  Verifies the local release prerequisites before you start: command availability, `Config/Signing.env`, Developer ID signing identity, GitHub CLI auth, Sparkle CLI tools, and the stored notary profile. If Apple has blocked notarization because a required agreement is unsigned or expired, this usually surfaces in the notary-profile check once the profile exists.
- `make release-setup-notary APPLE_ID=<apple-id>`
  Stores or refreshes the `notarytool` keychain profile from `Config/Signing.env`. `notarytool` will still prompt interactively for the app-specific password, but the profile name and Team ID no longer need to be typed manually.
- `make release`
  Verifies the pushed release tag first, then runs signing/notarization and publishes the versioned Sparkle zip, DMG, and `appcast.xml` to GitHub Releases.
  If you recently cleaned `DerivedData`, run `make build` once before publishing so Sparkle's CLI tools are downloaded again, or point `NOMAD_SPARKLE_BIN_DIR` at the Sparkle `bin` directory directly.
- `make release-patch`, `make release-minor`, `make release-major`
  Prepare the release locally, then push the current branch and the new tag to `origin`.

## Notes

- Version metadata lives in `Config/Version.xcconfig`.
- Sparkle remains unavailable in local/dev builds until both `SUFeedURL` and `SUPublicEDKey` are injected into the app bundle.
- Release builds must not ship a shared `TankerkonigAPIKey`; Germany fuel support now depends on a user-supplied key stored in app settings.
- Treat any new provider the same way: if it needs a private credential, redesign the feature so the client does not ship that shared secret.
- Debug builds use a separate app identity (`Nomad Dashboard Dev`, bundle ID `com.iloapps.NomadDashboard.dev`) so they can run alongside production with separate macOS privacy permissions.
- Local Debug builds are unsigned unless `Config/Signing.debug.local.xcconfig` enables local automatic signing.
- Signed local Debug builds use your normal macOS home directory so Xcode can access the local developer account state; unsigned and CI builds still use an isolated temporary home for reproducible caches.
- When signed local Debug provisioning fails, `make build`, `make run`, and `make rerun` automatically retry once as unsigned builds so the app still launches, but WeatherKit remains unavailable in that fallback build.
- `make brand-assets` is still available for design-time regeneration of tracked branding assets, but it is no longer part of normal DMG packaging.
- The release-preparation script still drafts notes from commits since the latest `v*` tag and merges any curated `Unreleased` notes.
