# Release Flow

Nomad Dashboard is distributed directly outside the Mac App Store.

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
   - optional `NOMAD_SPARKLE_BIN_DIR` if Sparkle CLI tools are not auto-discovered
6. In the Apple Developer portal, open the App ID for `com.iloapps.NomadDashboard` and enable the WeatherKit capability before shipping a release build.
7. If you want local WeatherKit access in the separate debug app, create a second App ID for `com.iloapps.NomadDashboard.dev`, enable WeatherKit there too, and add local values plus `DEBUG_CODE_SIGN_ENTITLEMENTS = App/NomadDashboard.entitlements` in `Config/Signing.debug.local.xcconfig`.

`Config/Signing.env` is ignored by git and should stay local to the release machine.

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
5. Cut the release version and tag on `main`:
   - `make release-patch`
   - `make release-minor`
   - `make release-major`
6. Push `main` and the new tag:
   - `git push origin main`
   - `git push origin --tags`
7. Run a local pipeline preview:
   `make release-dry-run`
8. Build, sign, notarize, staple, and package the release:
   `make release`
   - `make release` now does an upfront GitHub preflight and aborts immediately if the release tag has not been pushed yet.
9. Verify the GitHub release includes:
   - `NomadDashboard-<version>.zip`
   - `NomadDashboard-<version>.dmg`
   - `appcast.xml`
10. Install from the DMG, launch the app, and verify `Check for Updates` reaches the published GitHub appcast.
11. Verify the installed release can load current weather and WeatherKit-backed travel weather alerts.

## Commands

- `make archive`
  Creates the release archive. When `Config/Signing.env` is present, release signing metadata is injected at build time.
- `make dmg`
  Creates a DMG from the archived app without regenerating tracked branding exports.
- `make release-dry-run`
  Prints the exact version, tag, repository, feed URL, and artifact paths the release pipeline will use.
- `make release`
  Verifies the pushed release tag first, then runs signing/notarization and publishes the versioned Sparkle zip, DMG, and `appcast.xml` to GitHub Releases.

## Notes

- Version metadata lives in `Config/Version.xcconfig`.
- Sparkle remains unavailable in local/dev builds until both `SUFeedURL` and `SUPublicEDKey` are injected into the app bundle.
- Debug builds use a separate app identity (`Nomad Dashboard Dev`, bundle ID `com.iloapps.NomadDashboard.dev`) so they can run alongside production with separate macOS privacy permissions.
- `make brand-assets` is still available for design-time regeneration of tracked branding assets, but it is no longer part of normal DMG packaging.
- The release-preparation script still drafts notes from commits since the latest `v*` tag and merges any curated `Unreleased` notes.
