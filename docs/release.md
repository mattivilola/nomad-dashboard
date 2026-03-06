# Release Flow

Nomad Dashboard is intended for direct distribution outside the Mac App Store.

## Tooling

- XcodeGen for project generation
- Xcode for archive builds
- Sparkle for in-app updates
- `hdiutil` for DMG creation
- Apple notarization tooling for signed releases

## Planned Release Steps

1. Configure signing identities and Sparkle keys locally.
2. Generate the Xcode project.
3. Archive the app in Release mode.
4. Sign and notarize the archive.
5. Create the DMG payload for first-time installs.
6. Publish the archive and appcast for Sparkle updates.

The scripts in `scripts/` support dry-run usage until real release credentials
are available.

