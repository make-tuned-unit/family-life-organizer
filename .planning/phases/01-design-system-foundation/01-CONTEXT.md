# Phase 1: Design System Foundation - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish a centralized design token system, shared ViewModifiers, reusable components, and button styles that all subsequent screen polish work depends on. Also fix performance issues (DateFormatter caching, LazyVStack migration, force-unwrap removal). This phase is purely foundational — no per-screen polish yet.

</domain>

<decisions>
## Implementation Decisions

### Color Palette & Glass Tinting
- Per-tab ambient colors (teal, blue, orange, green, purple, etc.) are retained — subtle tint, not strong
- Glass cards pick up a hint of the tab's ambient color — like Apple Health section cards
- Accent color for interactive elements: Claude's discretion based on Apple's approach
- Palette refinement: Claude can harmonize existing tab colors if needed
- Dark mode: let iOS Liquid Glass handle automatically — no custom overrides

### Card Surface Treatment
- Light and airy feel — subtle frosted glass, minimal shadow (Apple iOS 26 widget style)
- Interactive cards (tappable tasks, appointments) use `.interactive()` glass effect for scale/shimmer on press
- Display-only cards (stat summaries, section containers) use standard glass without interactive feedback
- Corner radius: system continuous corners (~16pt) — match iOS system card radius
- Each item gets its own individual glass card — no grouped container lists
- Cards should feel like they float, not like rigid containers

### Typography & Spacing Scale
- Spacious layout — generous padding like Apple Health, calm and scannable
- Section headers: bold title + subtle gray caption underneath (Apple Health style)
- System default font weights for each text style (.title is bold, .body is regular)
- Key numbers (task counts, budget totals) are prominent and large (.title size) in pills/cards — first thing you see
- Vertical spacing: ~24pt between sections, ~12pt between cards within a section
- Horizontal margins: 20pt edge padding (slightly wider than standard 16pt for premium feel)
- Text truncation: single line with ellipsis — keeps cards uniform height
- SF Symbols appear alongside text labels in cards and rows for scannability

### Component Visual Style
- **StatPills**: Glass capsules with SF Symbol icon + large number + tiny label (Apple Health ring summary style)
- **BadgeLabels**: Tinted capsule badges with semantic color (red=overdue, orange=expiring, green=done) + text label
- **FilterChips**: Glass toggle chips — unselected: subtle outline, selected: filled glass with tab tint color
- **Primary buttons (CTA)**: Filled glass with tab tint color — clearly the primary action
- **SectionHeaders**: Bold title text + smaller gray subtitle underneath

### Claude's Discretion
- Exact accent color strategy (tab-contextual vs. global) — pick what Apple's apps do
- Tab color palette refinement — harmonize if the existing colors clash
- Exact spacing token values (as long as they maintain the ~24/12pt rhythm)
- Secondary and destructive button style specifics
- Loading skeleton design specifics
- Error state visual treatment

</decisions>

<specifics>
## Specific Ideas

- "I want it to feel like Apple Health" — spacious, calm, prominent numbers, subtle glass cards
- Apple's iOS 26 widgets are the reference for card surface treatment
- Per-tab color identity through ambient background orbs is already correct — formalize it, don't replace it
- The existing `AmbientBackground` pattern with per-tab gradient orbs is the right foundation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-design-system-foundation*
*Context gathered: 2026-03-20*
