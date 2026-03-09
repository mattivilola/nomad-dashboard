# Contributing

Thanks for contributing to Nomad Dashboard.

## Ground Rules

- Keep the app native to macOS. Avoid introducing a web wrapper or web-first
  architecture.
- Preserve the menu bar utility focus. New features should support the
  travelling coder use case, not turn the project into a generic system monitor.
- Do not remove files without explicit maintainer approval.
- Keep generated Xcode files out of git. Edit `project.yml` and regenerate.

## Local Setup

1. Run `make bootstrap`
2. Run `make generate`
3. Run `make open`
4. Run `make build`
5. Run `make run`
6. Run `make test`

## Changelog And Releases

- Add user-visible changes to `## [Unreleased]` in `CHANGELOG.md`
- Keep the git working tree clean before running any release command
- Prepare releases with `make release-patch`, `make release-minor`, or
  `make release-major`
- Release preparation updates the centralized version file, refreshes the
  changelog, creates a release commit, and creates a git tag

## Pull Requests

- Keep changes focused and coherent.
- Update docs when behavior, architecture, or release steps change.
- Add or update tests for any non-trivial logic.
- Describe user-visible changes and verification steps in the pull request.

## Code Style

- Prefer simple SwiftUI composition and protocol-driven services.
- Keep system integrations isolated in `NomadCore`.
- Reuse theme tokens and dashboard components from `NomadUI`.
- Use `make lint` before opening a PR when `swiftformat` is installed.
