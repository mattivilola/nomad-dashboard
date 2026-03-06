# Release Flow

Nomad Dashboard is intended for direct distribution outside the Mac App Store.

## Tooling

- XcodeGen for project generation
- Xcode for archive builds
- Sparkle for in-app updates
- `hdiutil` for DMG creation
- Apple notarization tooling for signed releases

## Current Status

- Status as of March 6, 2026: in-app Sparkle update checks are temporarily disabled.
- TODO: re-enable automatic and manual update checks after the release pipeline can publish signed app builds and `appcast.xml`.
- Blocker: the publish/update pipeline has not been created yet.

## Planned Release Steps

1. Keep `CHANGELOG.md` updated under `## [Unreleased]`.
2. Make sure `git status --short` is empty.
3. Run one of:
   `make release-patch`
   `make release-minor`
   `make release-major`
4. Push the resulting release commit and `vX.Y.Z` tag.
5. Configure signing identities and Sparkle keys locally.
6. Generate the Xcode project.
7. Archive the app in Release mode.
8. Sign and notarize the archive.
9. Create the DMG payload for first-time installs.
10. Publish the archive and appcast for Sparkle updates.

The scripts in `scripts/` support dry-run usage until real release credentials
are available.

## Notes

- Version metadata lives in `Config/Version.xcconfig`.
- Release tags use the exact format `vX.Y.Z`.
- If `Unreleased` is empty, the release-preparation script drafts notes from git
  commit subjects since the latest `v*` tag.
- The release-preparation command aborts on a dirty git tree.
