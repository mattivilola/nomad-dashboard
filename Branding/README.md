# Nomad Dashboard Branding

This directory holds the repo-owned source of truth for Nomad Dashboard brand
artwork.

- `Source/NomadBrandRenderer.swift` renders the travel-instrument mark, lockup,
  app icon master, and DMG background using AppKit drawing code.
- `Exports/` contains generated outputs that are committed so app builds and DMG
  packaging work without a pre-step.

Regenerate the exported assets with:

```sh
make brand-assets
```

Do not hand-edit files in `App/Resources/Assets.xcassets/AppIcon.appiconset/`.
The exporter rewrites that icon set deterministically from the brand source.
