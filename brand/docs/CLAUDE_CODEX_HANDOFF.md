# Claude / Codex implementation handoff

## Objective
Integrate the Kinrows Direction 2.0 visual system without redesigning the product architecture. This kit is an asset and token source of truth.

## Non-negotiables
1. Do not regenerate or approximate mascot/logo art in code. Use the provided assets.
2. Do not sample colours from screenshots. Import the token file.
3. Do not introduce a second green palette. Evergreen + Sage are the brand greens.
4. Product UI stays calm and functional; mascot art appears at high-emotion/high-explanation moments, not everywhere.
5. Every animated/decorative mascot must have an accessible text equivalent and respect Reduce Motion.
6. Preserve transparent padding on `mascot/higgsfield/*`. Do not auto-trim those source files.

## Recommended integration order
### 1 — Tokens
Wire the relevant token file into the app theme. Map existing colours to the nearest semantic Kinrows token before replacing individual hardcoded values.

### 2 — Typography
Install Fraunces for display roles and Inter for UI/body. Use Fraunces sparingly: onboarding titles, marketing, large empty-state headings. Keep navigation, forms, lists and controls in Inter.

### 3 — App icon + brand entry points
Replace app icon, splash/launch branding, auth/welcome lockup, and settings/about branding.

### 4 — Product icons
Use the provided SVGs for Home, Calendar, Lists and Budgets. Stroke width and round joins are part of the system; do not mix with thin outlined glyphs in the same nav cluster.

### 5 — Rowan moments
Suggested mapping:
- Welcome: `rowan-wave-source.png`
- Planning/list creation: `rowan-on-it-source.png`
- Background work/AI: `rowan-thinking-source.png`
- Empty state / family cooperation: `rowan-rowing-source.png`
- Completion: `rowan-celebrating-source.png`
- Positive acknowledgement: `rowan-grateful-source.png`
- Neutral helper: `rowan-idle-smile-source.png`

### 6 — Onboarding motion
Implement still-image fallback first. Add video/Lottie/mp4/webm only after the layout is stable. Preload the next scene, never block onboarding on a decorative animation, and stop loops when the page is offscreen.

## Asset component contract
Create one shared `BrandAsset`/`KinrowsIllustration` component rather than scattering file paths. It should support:
- asset key
- accessible label or decorative mode
- aspect-fit rendering
- max size
- reduced-motion fallback
- dark/light surface handling if needed

## Suggested semantic asset keys
`logo.primary`, `logo.wordmark`, `logo.boat`, `logo.lettermark`, `mascot.welcome`, `mascot.thinking`, `mascot.done`, `mascot.rowing`, `icon.home`, `icon.calendar`, `icon.lists`, `icon.budgets`.

## Acceptance checks
- No hardcoded brand colours outside token files.
- No distorted assets; preserve aspect ratio.
- Transparent assets have no cream rectangle around them.
- Mascot is not used as a status indicator without text.
- Reduce Motion disables nonessential video/looping animation.
- Onboarding works with animation files unavailable/offline.
- App icon is tested at 16/32/64/180/512/1024 sizes for legibility.
