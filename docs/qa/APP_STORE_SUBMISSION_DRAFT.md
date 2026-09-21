# App Store submission draft

Prepared copy, not a submitted or approved App Store Connect record. Validate against the final signed build and complete the account fields below before submission.

## Listing

**Name:** Kinrows

**Subtitle:** Your family's shared organizer

**Description:**

Keep everyday family plans together with Kinrows.

Coordinate your household calendar, tasks and shopping lists. Track spending and recurring payments, organize pantry items, save notes, and keep routines in one place. Family groups and messages help everyone stay connected, while trips and itineraries keep travel plans easy to find.

Ask Concierge to help with supported planning tasks, find information and make updates. When a workflow needs a photo, device permission or your review, continue in the relevant app screen. Review important changes and shared information before relying on them.

Optional Concierge subscriptions cover your household and are purchased through the App Store. The purchase screen shows the available plan, localized price and renewal terms. Manage or cancel an Apple subscription in your App Store account settings.

Cloud AI features are optional and explain what information is sent before first use. Health and fitness features require the relevant permissions and are for general wellness and organization, not diagnosis or treatment.

**Support URL:** https://kinrows.com/support.html

**Privacy URL:** https://kinrows.com/privacy.html

## Review notes

Kinrows is a household organization app intended for adult account holders. A household can contain information about dependents; the app is not submitted as a Kids Category app.

Provide an active reviewer account and fictional household data in App Store Connect's protected review-credentials fields. Do not place passwords in this repository. Include a second fictional member if the reviewer needs to exercise shared workflows, messaging, voting or coverage. Confirm the reviewer can access paid features and that the exact submitted build can verify App Review sandbox purchases on the production backend; neither condition has been verified yet.

Suggested review path:

1. Sign in to the supplied account and open the calendar, a list, budget, pantry and a routine.
2. Open Concierge from the daily brief. The brief works without sending data to cloud AI. Optional chat requests feature-specific consent before sending data to Anthropic.
3. Ask Concierge to add a fictional task, verify it in the app, then ask to remove it. Ask to scan a receipt to see the native handoff and review flow.
4. Open Messages to find reporting and member blocking. The supplied household must contain only fictional content.
5. Find account deletion in Settings. Apple-linked accounts reauthenticate with Apple; the revocation-compatible client/backend must be deployed together before this path is represented as ready.
6. Review the subscription paywall, Restore Purchases and legal links. Permission-denied states should remain usable without the corresponding feature.

Camera, Photos, Calendar, HealthKit, speech, location and notifications support specific optional workflows. Do not grant permissions that are unrelated to the workflow under review. Location sharing is user initiated. Educational health content does not provide medical diagnoses or contraception advice.

## Fields still requiring developer-account evidence

- Final bundle/build/version and signed app/widget archive; upload validation and TestFlight install.
- Distribution certificate/profiles and entitlements; Sign in with Apple revocation key.
- Four Concierge product records, localized prices, group/rank, agreements and sandbox review strategy.
- Updated App Privacy answers checked against `docs/APP_PRIVACY_LABEL.md`, provider behavior and final manifests.
- Current age-rating questionnaire, territories, export compliance and trader/business declarations.
- Screenshots captured from the final signed candidate, with fictional data and accurate feature/paywall states.
- Reviewer credentials, second-member access if needed, review contact and a staffed support/moderation inbox.
- Final launch date and whether the public website should remain a waitlist or link to the approved App Store listing.
