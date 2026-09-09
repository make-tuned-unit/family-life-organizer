# Kinrows Brand — Direction 2.0 implementation

**Kin that rows together.** The visual system is a crew in a boat: coordinated, warm, capable. Source of truth for every asset and value is `brand/` (the imported Brand Kit v2, minus duplicate mascot copies and the small app-icon sizes Xcode derives). Read `brand/README.md`, `brand/docs/BRAND_USAGE.md` and `brand/docs/CLAUDE_CODEX_HANDOFF.md` before touching brand surfaces.

## Tokens — where they live

| Layer | File | Notes |
|---|---|---|
| Canonical | `brand/tokens/kinrows-brand-tokens.{json,css,ts,swift,dart}` | Never edit; re-import from the kit. |
| iOS | `FamilyLife/Views/Components/DesignTokens.swift` → `KinrowsBrand` | Eight kit hexes + accessible shades (`sageDeep`, `sunDeep`, `clayDeep`, `riverDeep`) + oat tints. `WarmPalette` / `AccentTheme` / `TabAccent` keep their historical names but resolve onto these. |
| Web | `website/assets/style.css` `:root` | `--kinrows-*` primitives, then the page's semantic roles (`--cream-1`, `--terracotta`, …) remapped onto them. |

Core palette: Evergreen `#0F3D37` (primary, nav, high-emphasis actions) · Sage `#8FAE8F` (support) · Oat `#F7F3E9` (background) · Clay `#C76F4F` (attention, moments) · River `#6B8FB0` (links, travel, info) · Sun `#F2C94C` (celebration only) · Ink `#1F2A24` (text) · Mist `#E8EEE9` (secondary surfaces).

Rules that follow from the kit:
- No second green. Every green in the product is Evergreen, Sage, or a shade of one of them.
- Sage and Sun fail contrast on Oat as text; use `sageDeep` / `sunDeep` for glyphs and keep the pure tokens for fills, chips and highlights.
- No colour literals outside the token files. `AccentTheme` case names (`terracotta`, `saffron`, `rose`, …) are persisted per-person colour choices, so they are kept as identifiers; their values are Kinrows hues (see the comment block in `DesignTokens.swift`).
- Person identity colours (`PersonPalette`) use the five brand hues plus three muted companions — a household needs more distinct identities than the kit has hues.

## Typography

- **Fraunces** (display) — bundled as static instances `Fraunces72pt-SemiBold/Regular/Italic` in `FamilyLife/Resources/Fonts` (OFL, installed via our own pipeline, not shipped from the kit). Exposed as `Font.flDisplay`, `.flDisplayLarge`, `.flDisplaySmall`, `.flDisplayItalic` — all scale with Dynamic Type. Use for onboarding titles, the auth lockup, large empty-state headings and brand moments only.
- **Inter** (UI) — on the web via Google Fonts. In the app, SF Pro (the `fl*` scale) is the platform-native stand-in; navigation, forms, lists and controls stay on it.

## Assets

- iOS asset catalog (`FamilyLife/Resources/Assets.xcassets`): `Brand/` (BrandPrimary, BrandLockup, BrandWordmark, BrandBoatMark, BrandLettermark, BrandScenicRow), `Rowan/` (eleven poses), `Illustrations/` (boat, oar, waves, leaf, sun, mountains, trees, home, cloud, foliage), `ProductIcons/` (vector SVG), `AppIcon`. Never reference these names directly — go through `KinrowsIllustration` / `KinrowsAsset` (`FamilyLife/Views/Components/KinrowsIllustration.swift`).
- Web (`website/assets/brand/`): `logos/`, `mascot/`, `icons/*.svg`, `illustrations/`, `patterns/`, favicons, `motion/`.
- Regenerate rasters from the kit with the Pillow script used in the brand-kit commit (trim transparent margins, ~4% padding, @2x/@3x for iOS at the intended point size).
- `brand/mascot/retouched/rowan-grateful.png` replaces the kit source for the grateful still: the kit file carries a stray vertical mark left of the character, which is erased there (nothing redrawn). The grateful clip masks the same region.

## Rowan (mascot)

Density: high on onboarding/launch/milestones; medium on empty states and Concierge; low (none) on grids, tables, rows, forms and settings. Rowan never carries required information — every mascot moment keeps its text.

Pose mapping: welcome → `wave` · planning/list creation → `onIt` · AI / background work → `thinking` · empty state / cooperation → `rowing` · completion → `celebrating` · acknowledgement → `grateful` · neutral helper → `idleSmile`.

### Motion pipeline (Higgsfield)

Masters live in `brand/mascot/motion/` beside their source PNGs; the app bundles `FamilyLife/Resources/Motion/rowan-*.mov` (HEVC with alpha, 720×720, 24 fps, ~2.6 s), the site serves `website/assets/brand/motion/rowan-*.{webm,mov}` (VP9 alpha 480² for Chrome/Firefox, HEVC alpha for Safari) with the pose PNG as poster.

How they were made (repeat this to add a pose):
1. Upload the `brand/mascot/sources/*-source.png` (transparent, padded — do not trim) to Higgsfield.
2. Generate with **Kling 3.0 std**, 3 s, 1:1, sound off, `start_image` = the source. Prompt: one small action, "locked camera", "flat solid magenta backdrop", "keep the exact drawing, line weight and colours". Keep the prompt short and positive — long negative lists get rendered as text in the frame. If a preset is recommended instead of a job, resubmit with `declined_preset_id`.
3. Run Higgsfield **video background removal** on the result. It returns the character matted on pure black (no alpha channel).
4. Recover alpha and encode with `brand/mascot/motion/encode.sh` — a soft luma key (`max(r,g,b)` 4→26 ramp) + `unpremultiply`, trimming the first 10 frames (the model's black→magenta transition), then `hevc_videotoolbox -alpha_quality 0.9` for `.mov` and `libvpx-vp9 yuva420p` for `.webm`.
5. Reject any clip where the face or leaf silhouette changes; compare first and last frame to the source at 100%.

Playback: `RowanMotionView` (iOS) plays once and holds the last frame (loops only for thinking/idle), pauses when `isActive` is false, and falls back to the still under Reduce Motion or when the clip is missing. On the web, `assets/app.js` applies the same rules to `video.rowan` (`prefers-reduced-motion`, IntersectionObserver pause).

## Deliberate deviations from the handoff

- Tab bar keeps SF Symbols (selected/unselected fills, Dynamic Type, accessibility) — the kit's product icons are used in onboarding, empty states and marketing instead of the nav cluster.
- Product corner radii stay on `DesignTokens.CornerRadius` (22/28/18/12); the kit's 10/16/24 are exposed as `KinrowsBrand.Radius` for new brand surfaces.
