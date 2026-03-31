# CLAUDE.md

Repository-specific instructions for Claude-compatible agents working in this
project.

## Project Intent

- Build a polished native macOS menu bar dashboard for nomad and travel-heavy
  laptop workflows.
- Keep the product compact, visually intentional, and privacy-conscious.
- Favor energy-efficient passive monitoring over heavy active probing.

## Repo Rules

- Never remove files without explicit approval from Matti Vilola.
- Treat `project.yml` as the source of truth for the Xcode project.
- Prefer editing local Swift packages over pushing logic directly into the app
  target.
- Keep release secrets out of the repository. Use environment variables and
  local config templates from `Config/`.
- When changing user-facing features, privacy behavior, or product capabilities,
  update the relevant docs in the same task. Always check
  `docs/marketing/features.md`, `docs/marketing/marketing.md`, and
  `docs/privacy.md`, and update whichever files are affected.

## Architecture Boundaries

- `App/` owns lifecycle, menu bar scenes, settings/about windows, and platform
  integration glue.
- `Packages/NomadCore/` owns models, monitors, persistence, settings, weather/IP
  providers, and update abstractions.
- `Packages/NomadUI/` owns theme, cards, charts, and reusable dashboard views.

## Expected Tooling

- Bootstrap with Homebrew from `Brewfile`
- Generate with XcodeGen
- Use Swift Package Manager for local modules and tests
- Release through scripts in `scripts/`
