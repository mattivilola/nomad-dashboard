# Release Flow

Nomad Dashboard is intended for direct distribution outside the Mac App Store.

## Tooling

- XcodeGen for project generation
- Xcode for archive builds
- Sparkle for in-app updates
- `hdiutil` for DMG creation
- `swift`, `sips`, and `tiffutil` for brand asset exports
- Apple notarization tooling for signed releases

## Current Status

- Status as of March 6, 2026: in-app Sparkle update checks are temporarily disabled.
- TODO: re-enable automatic and manual update checks after the release pipeline can publish signed app builds and `appcast.xml`.
- Blocker: the publish/update pipeline has not been created yet.

## Planned Release Steps

1. Keep `CHANGELOG.md` updated under `## [Unreleased]` with the clearest user-facing notes you have.
2. Make sure `git status --short` is empty.
3. Run one of:
   `make release-patch`
   `make release-minor`
   `make release-major`
4. Push the resulting release commit and `vX.Y.Z` tag.
5. Configure signing identities and Sparkle keys locally.
6. Regenerate branded assets with `make brand-assets`.
7. Generate the Xcode project.
8. Archive the app in Release mode.
9. Sign and notarize the archive.
10. Create the branded DMG payload for first-time installs with `make dmg`.
11. Publish the archive and appcast for Sparkle updates.

The scripts in `scripts/` support dry-run usage until real release credentials
are available.

## Notes

- Version metadata lives in `Config/Version.xcconfig`.
- Release tags use the exact format `vX.Y.Z`.
- `make brand-assets` regenerates the app icon set, logo exports, DMG background,
  and custom volume icon from the source in `Branding/`.
- The release-preparation script always drafts notes from commits since the
  latest `v*` tag, groups them into `Added`, `Changed`, and `Fixed`, and then
  merges in any curated `Unreleased` notes.
- Curated `Unreleased` notes still matter. They are the place to tighten or
  override wording when commit subjects are too implementation-focused.
- The release-preparation command aborts on a dirty git tree.
- The DMG now uses the classic drag-install layout: app on the left,
  `Applications` symlink on the right, branded background, and custom volume
  icon.
