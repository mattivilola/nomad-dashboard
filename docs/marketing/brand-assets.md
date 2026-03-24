# Nomad Dashboard Brand Assets And Visual Guidance

This document links the existing brand source of truth and translates it into website-facing guidance.

The landing page should be brand-led. The repository currently includes brand exports and app icons, but it does not include a committed library of real product screenshots for a screenshot-led homepage.

## Source Of Truth

- [../../Branding/README.md](../../Branding/README.md)
- [../../Branding/Source/NomadBrandRenderer.swift](../../Branding/Source/NomadBrandRenderer.swift)

## Primary Exported Assets

- [../../Branding/Exports/NomadDashboard-logo-lockup.png](../../Branding/Exports/NomadDashboard-logo-lockup.png)
- [../../Branding/Exports/NomadDashboard-symbol-mark.png](../../Branding/Exports/NomadDashboard-symbol-mark.png)
- [../../Branding/Exports/NomadDashboard-icon-1024.png](../../Branding/Exports/NomadDashboard-icon-1024.png)
- [../../Branding/Exports/NomadDashboard-dmg-background.png](../../Branding/Exports/NomadDashboard-dmg-background.png)

## Brand Direction

Nomad Dashboard should feel like a compact travel instrument panel rather than a generic productivity app or a hard-edged infrastructure monitor.

The brand cues already present in the app and brand renderer are:

- warm sand accents
- teal as a core functional color
- coral for energy and contrast
- cream, seafoam, and shell tones in lighter backgrounds
- dark midnight and deep-sea tones for richer contrast states
- soft gradients and polished surfaces
- compact, practical, non-generic visual hierarchy

## Core Palette

These values are already represented in the repo brand system and UI theme:

- Sand: `#A56E17` / bright sand `#F0C987`
- Teal: `#0E8C92` / bright teal `#5FC3C8`
- Coral: `#C85C34` / bright coral `#F68B63`
- Cream: `#F6EEDD`
- Seafoam: `#E7F4F2`
- Shell: `#FCEBDD`
- Midnight: `#101A24`
- Deep Sea: `#17303A`
- Slate: `#425663`

## Visual Personality

The website should feel:

- native
- warm
- polished
- compact
- travel-aware
- intentional

The website should not feel:

- generic SaaS
- enterprise infrastructure tooling
- cyberpunk
- App Store clone marketing
- screenshot-fake or mockup-heavy without grounding

## Guidance For The Website Builder

- Use the exported logo, mark, icon, and palette as source material.
- Mirror the app’s warm sand, teal, and coral direction instead of inventing a separate color system.
- Keep the visual language compact and precise, not card-spam-heavy.
- Favor gradients, atmospheric backgrounds, and instrument-like composition over generic software marketing blocks.
- If product UI visuals are needed, use restrained brand-led compositions or clearly stylized mockups rather than fake “official screenshots”.
- Reserve room for real screenshots later, but do not make the first version depend on them.

## Messaging Alignment Rules

- Do not imply Mac App Store distribution.
- Do not imply enterprise support, uptime guarantees, or formal service commitments.
- Do highlight that the app is free.
- Do highlight that the app is provided as-is.
- Do keep GitHub visible as part of the product trust story.
- Do present the product as a native macOS download.

## Recommended Homepage Visual Strategy

### Hero

Lead with the logo or symbol mark, strong typographic messaging, and a brand-led background derived from the existing palette and travel-instrument feel.

### Support Visuals

Use abstracted dashboard-inspired shapes, status motifs, map/travel references, or subtle telemetry cues instead of pretending there is a screenshot library in the repo.

### CTA Area

Keep `Download for macOS` and `View on GitHub` equally visible, with short trust cues such as:

- Free
- Open source
- Native macOS
- Direct download
- Provided as-is

## Asset Handling Rules

- Link to or reuse the existing brand exports from `Branding/Exports/`.
- Treat `Branding/Source/NomadBrandRenderer.swift` as the brand source of truth.
- Do not duplicate or move master brand files into the marketing docs folder.
- Do not hand-edit generated brand exports without also updating the renderer-based source workflow.
