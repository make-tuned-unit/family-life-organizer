# Higgsfield + onboarding animation guide

## Source files
Use only `mascot/higgsfield/*-source.png` as character inputs. They are transparent, square, centered and padded specifically to reduce clipping/morphing. Use `illustrations/png/` only when an oar/boat/leaf/etc. needs independent motion.

## Global generation rules
- Camera locked; no zoom, pan or parallax unless the product storyboard explicitly calls for it.
- Preserve Rowan's face, leaf/hat silhouette, line weight and exact evergreen/sage/cream/clay palette.
- One primary action per clip.
- Keep motion small, warm and readable. Rowan is calm, not hyperactive.
- Do not create text in the generated video. App copy remains native UI text.
- Do not add a background when generating a transparent character clip.
- Do not add props unless the reference source already includes that prop.
- Avoid morphing the leaf, hands, eyes, boat or oar.

## Negative prompt / constraint block
Paste this into every generation when the tool supports negative guidance:

`No new characters. No extra limbs or fingers. No face redesign. No costume changes. No photorealism. No 3D rendering. No camera movement. No background. No typography. No logo mutation. No object duplication. No exaggerated squash-and-stretch. Keep the exact flat hand-drawn Kinrows illustration style and colours.`

## Output settings
Preferred master: 1024×1024 or 1080×1080, 24 or 30 fps, 3–4 seconds, transparent/alpha-capable output when available. If the generation product cannot export alpha, generate on a clean chroma background that does not occur in the character palette, key it out, then export ProRes 4444/WebM alpha or a PNG sequence. Do not ship a keyed background in the app.

## Five onboarding beats
### 01 — Welcome / “A calmer home together.”
Source: `rowan-wave-source.png`
Prompt: `Rowan gives one small friendly wave, blinks once, then settles. The leaf follows with subtle secondary motion. Body movement under 5 percent. Camera locked. Preserve exact illustration.`
Duration: 2.8–3.2s. Loop: no; freeze on final frame.

### 02 — Plan / “Plan meals. Organize life.”
Source: `rowan-on-it-source.png`
Prompt: `Rowan glances at the checklist and makes one tiny satisfied check-off gesture. One blink. Clipboard stays structurally unchanged. Camera locked.`
Duration: 3.0–3.5s. Loop: optional only after a long 1.5s still hold.

### 03 — Stay in sync / “Keep everyone on the same page.”
Source: `rowan-thinking-source.png`
Prompt: `Rowan thinks for a moment, eyes shift gently to the side, then a small knowing nod. Leaf moves subtly after the nod. Camera locked.`
Duration: 3.0s. Loop: very gentle if needed.

### 04 — Make time / “More time for what matters.”
Source: `rowan-grateful-source.png`
Prompt: `Rowan hugs the heart/round object closer, closes eyes briefly with a warm grateful expression, then returns to neutral. Camera locked.`
Duration: 3.2s. Loop: no.

### 05 — Further together / “Kin that rows together.”
Use: `patterns/kinrows-scenic-family-row.png` as scene reference plus `rowan-rowing-source.png` for character motion reference.
Prompt: `A family crew rows in calm synchronization. Oars dip once together, water receives two small clean ripples, boat rocks only slightly. Preserve the flat Kinrows editorial illustration style. No camera move.`
Duration: 4.0s. Loop: can loop if first/last boat position matches.

## App implementation
- Keep headline/body/button as native UI layered separately from video.
- Animation must never contain required information.
- Start clips muted/autoplay only if platform policy allows; there is no audio requirement.
- Pause when scene loses focus.
- Preload next clip after current screen is interactive.
- Respect `prefers-reduced-motion` / iOS Reduce Motion / Android animator scale. Reduced-motion fallback = still PNG from the same source asset.
- Prefer a single play-through + hold over infinite looping.

## Higgsfield consistency workflow
1. Upload the exact `*-source.png`.
2. Use the same constraint block for every pose.
3. Generate 3–5 candidates.
4. Reject any clip where the face/leaf silhouette changes.
5. Export the chosen clip with alpha or key cleanly.
6. Compare first and last still against the source at 100% zoom.
7. Name final files `onboarding-01-welcome`, `02-plan`, etc. and keep the original source PNG beside each master.
