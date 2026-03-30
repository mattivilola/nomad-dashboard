# AGENTS.md

This repository is intended for coding agents and human contributors working on
Nomad Dashboard.

## Non-Negotiables

- Never remove files without explicit approval from Matti Vilola.
- Keep the app native to macOS and menu-bar-first.
- Do not commit generated `.xcodeproj` output. Regenerate from `project.yml`.
- Never add private API keys, secrets, tokens, or customer credentials to tracked config, app bundle metadata, or any file that can ship to the public repo or release artifacts. Follow `docs/security.md`.

## Working Agreements

- Put reusable logic in `Packages/NomadCore`.
- Put shared presentation code in `Packages/NomadUI`.
- Keep `App/` thin and focused on lifecycle, windows, and system glue.
- Prefer non-destructive changes and document any release-flow changes in
  `docs/release.md`.
- When a user-facing feature, privacy behavior, or product capability changes,
  update the relevant docs in the same task. Always review
  `docs/marketing/features.md`, `docs/marketing/marketing.md`, and
  `docs/privacy.md`, and update whichever of them are affected.

## Validation

- `make test` for package tests
- `make build` for app compilation after project generation
- `make lint` when formatter tooling is available
