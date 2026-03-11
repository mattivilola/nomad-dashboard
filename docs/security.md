# Credential Handling Policy

This repository is public-facing. Assume any tracked file, generated project
setting, or shipped app bundle can become visible to contributors, Git hosting,
and end users.

## Non-Negotiable Rule

- Never place private API keys, bearer tokens, client secrets, signing secrets,
  service-account credentials, or customer credentials in tracked files.
- Never place private credentials in `Info.plist`, `project.yml`, tracked
  `.xcconfig` files, source constants, or any other build input that becomes
  part of the shipped app bundle.
- If the macOS app ships with a value, users can extract it. Do not treat local
  config injection as secrecy.

## Decision Rule For New Integrations

Before adding a new provider, answer this:

1. Is the value public by design?
2. Is it only meant to stay out of git, but acceptable if visible in the built app?
3. Must it remain private even after the app ships?

Use these rules:

- Public values:
  Safe to inject at build or release time. Example: Sparkle public verification
  key.
- Local-only but okay to ship:
  Keep them out of tracked files and inject them from gitignored local config or
  release env. Example: approved ReliefWeb app name.
- Private values:
  Do not bundle them into the app. Redesign the feature instead.

## Allowed Patterns

- Gitignored local config for non-secret build inputs:
  `Config/AppConfig.local.xcconfig`
  `Config/Signing.local.xcconfig`
  `Config/Signing.debug.local.xcconfig`
  `Config/Signing.env`
- User-supplied credentials stored on the local machine when the feature can
  work with per-user configuration.
- Server-side proxying or token minting when a shared upstream secret must stay
  private.
- Environment-variable overrides for local developer tooling and probes, as long
  as release builds do not depend on bundling those secrets.

## Forbidden Patterns

- Adding secrets to `project.yml`
- Adding secrets to tracked `Config/*.xcconfig`
- Adding secrets to `App/Info.plist`
- Hardcoding secrets in Swift source
- Using release-only build injection for a value that must stay private after
  shipping
- Assuming `.gitignore` alone makes a client secret safe

## Feature Review Checklist

When adding a new integration, document these answers in the PR or change note:

- What credential or identifier does the integration need?
- Is that value public, local-only, or private?
- Where is it stored during development?
- Where is it injected during release, if anywhere?
- Does it end up in the shipped app bundle?
- If it is private, what architecture keeps it out of the client?
- What test or release guard prevents accidental bundling later?

## Current Examples

- Sparkle public key:
  Public value. Injected locally at release time and intentionally shipped.
- ReliefWeb app name:
  Kept out of git, but allowed in the shipped app bundle. Stored in gitignored
  local config.
- Tankerkönig API key:
  Must not ship as a shared secret. The app uses a user-provided key stored
  locally in app settings instead of bundling one shared key.

## Practical Review Standard

If a change adds a new API integration and the implementation path is
"put credential in config so the app works", stop and redesign it first.

Convenience is not an exception to this policy.
