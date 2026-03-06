# AGENTS.md

This repository is intended for coding agents and human contributors working on
Nomad Dashboard.

## Non-Negotiables

- Never remove files without explicit approval from Matti Vilola.
- Keep the app native to macOS and menu-bar-first.
- Do not commit generated `.xcodeproj` output. Regenerate from `project.yml`.

## Working Agreements

- Put reusable logic in `Packages/NomadCore`.
- Put shared presentation code in `Packages/NomadUI`.
- Keep `App/` thin and focused on lifecycle, windows, and system glue.
- Prefer non-destructive changes and document any release-flow changes in
  `docs/release.md`.

## Validation

- `make test` for package tests
- `make build` for app compilation after project generation
- `make lint` when formatter tooling is available

