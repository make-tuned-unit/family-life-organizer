> **Repo notes (not part of the vendor kit):** `mascot/higgsfield/` is checked in as `mascot/sources/` (the `mascot/png/` copies were byte-identical and are dropped); `mascot/motion/` holds the generated Rowan clips + `encode.sh`; `mascot/retouched/` holds the one retouched still (see its README); `app-icons/` keeps only the 512/1024 masters — Xcode and the site derive the rest. Implementation guide: `docs/BRAND.md` at the repo root.

# Kinrows Brand Kit — Direction 2.0

## Brand idea
**Kin that rows together.** Kinrows is the family operating system that helps a household pull in the same direction. The visual metaphor is a crew in a boat: coordinated, warm and capable, not nautical-themed software.

This package is the implementation handoff for the approved illustrated direction: evergreen editorial wordmark, sage/clay/river support colours, Rowan mascot, family-in-a-boat imagery, and Fraunces + Inter typography.

## Start here
1. Use `references/approved-direction-board.png` as the visual north star.
2. Use `tokens/kinrows-brand-tokens.json` as the source of truth for colour/motion values.
3. Use `logos/png/` for exact approved raster artwork; `logos/svg/*live-text.svg` is developer convenience artwork and may render differently unless Fraunces is installed.
4. Use `icons/product/svg/` in product UI whenever your stack supports SVG; PNG equivalents are in `icons/product/png/`.
5. Use `mascot/higgsfield/` as animation inputs. Do not animate screenshots or the full brand board.
6. Read `docs/CLAUDE_CODEX_HANDOFF.md` before an AI coding agent changes the app.
7. Read `docs/HIGGSFIELD_ONBOARDING_ANIMATION.md` before generating motion.

## Folder map
- `logos/png` — primary illustrated logo, horizontal lockup, wordmark, boat mark, lettermark; transparent PNG.
- `logos/svg` — live-text developer SVGs.
- `app-icons` — opaque app icon exports from 16–1024 px.
- `icons/product` — Home, Calendar, Lists, Budgets plus Meals, Family, Moments, Trips, Growth, Settings. SVG + transparent PNG.
- `mascot/png` — isolated Rowan poses, transparent 1024×1024.
- `mascot/higgsfield` — same poses standardized as animation-source files.
- `illustrations/png` — isolated boat/oar/waves/leaf/sun/mountains/trees/home/cloud/foliage.
- `patterns` — opaque repeating motifs and scenic family-row illustration.
- `onboarding/reference-frames` — five visual references; use them as composition guides, not final production screens.
- `tokens` — JSON, CSS, TypeScript, Swift, Flutter/Dart starter tokens.
- `docs` — implementation, animation and usage guidance.
- `references` — approved board + production asset board.

## Core palette
| Token | Hex | Use |
|---|---|---|
| Evergreen | `#0F3D37` | Primary brand, nav, high-emphasis text/actions |
| Sage | `#8FAE8F` | Secondary brand, supportive states, leaf/crew accents |
| Oat | `#F7F3E9` | Main warm background |
| Clay | `#C76F4F` | Warm accent, moments, attention |
| River | `#6B8FB0` | Links, travel, water, informational UI |
| Sun | `#F2C94C` | Celebration/highlight only |
| Ink | `#1F2A24` | Body text |
| Mist | `#E8EEE9` | Secondary surfaces and dividers |

## Typography
- Display/headings: **Fraunces**.
- Product UI/body: **Inter**.
- Never ship font binaries from this kit. Install fonts through your normal licensed dependency/font pipeline.

## Logo rules
- Prefer the illustrated primary logo for launch, marketing and onboarding.
- Prefer the wordmark or boat mark in dense UI.
- Minimum wordmark width: 120 px. Minimum boat mark: 28 px.
- Clear space: 0.5× cap height around the mark.
- Do not recolour Rowan/family figures with arbitrary user colours or gradients.
- Do not place the illustrated primary logo over photography.

## Transparency rules
Transparent PNGs are used for mascots, isolated illustration elements, logo artwork and product icons. App icons, pattern tiles and scenic backgrounds are intentionally opaque. Higgsfield input assets have large transparent margins to reduce edge morphing during generation.
