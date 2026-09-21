# App Store Connect — App Privacy answers

Copy these into App Store Connect → App Privacy. Verified against the code
2026-09-21; App Store Connect still requires verification. **Every data type below: Linked to the user = YES, Used for
tracking = NO, Purpose = App Functionality.** Kinrows uses no third-party
advertising or tracking SDKs. The marketing site has a first-party pageview
collector (not used in the iPhone app).

## "Do you or your third-party partners collect data from this app?" → **Yes**

## Data types collected

| Apple category | Type | Notes |
|---|---|---|
| Contact Info | **Name** | Account display name |
| Contact Info | **Email Address** | Login / 2FA / account / Sign in with Apple (including Hide My Email relay) |
| Contact Info | **Phone Number** | Optional numbers you add on People / contacts |
| Identifiers | **Device ID** | APNs installation/device tokens stored against the account for notifications; no advertising ID |
| Contacts | **Contacts** | User-maintained contacts and household relationships; no device address-book import |
| Identifiers | **User ID** | Account id; Sign in with Apple `sub` |
| Health & Fitness | **Health** | Menstrual-cycle/fertility entries, symptoms, sleep logs and age-based health guidance |
| Health & Fitness | **Fitness** | Steps & flights climbed (read with HealthKit consent) → fitness challenges only |
| Location | **Precise Location** | Trip ETA (only while a trip is active) + opt-in household presence |
| Contact Info | **Physical Address** | Family addresses you add, geocoded for maps |
| User Content | **Photos or Videos** | Profile photos, message photos, receipt photos |
| User Content | **Emails or Text Messages** | In-app household messages (DMs, group chat) |
| User Content | **Other User Content** | Calendar events, tasks, lists, notes, pantry, trips, decisions, gifts, feed posts |
| Financial Info | **Other Financial Info** | Budgets, expenses, receipt totals |
| Purchases | **Purchase History** | The signed StoreKit transaction sent for subscription verification |

## NOT collected (answer "No" / don't add)

- Advertising identifiers — none (APNs device identifiers are declared above)
- Usage Data (product interaction, analytics) — **none** (no analytics SDK)
- Diagnostics (crash/performance) — **none** (no crash reporter)
- Browsing/Search History — none
- Device address-book access — none (manually added contacts are declared above)
- Audio Data — none (voice is transcribed on-device only; the mic is hidden if the iPhone cannot do on-device speech)
- Payment Info (card numbers) — none (Apple handles payment)

## Tracking

- **"Do you use data to track users?" → No.** No cross-app/website tracking,
  no data shared with data brokers, `NSPrivacyTracking = false`, empty tracking
  domains.

## Third-party processors to disclose in the privacy policy (not "partners" for tracking)

- **Anthropic** — AI concierge / receipt & recipe reading (opt-in; not used to train models).
- **Apple** — Push (APNs), StoreKit, Sign in with Apple, on-device speech.
- **Railway** — hosting. **Resend** — transactional email (2FA codes, waitlist, content reports).
- **Stripe** — web Concierge subscriptions (card data stays with Stripe).

## Submission checks still required

Review Sensitive Info against the actual fields and stored content (including any pregnancy/childbirth information); do not infer that reproductive-health tracking is covered by Fitness alone. Verify the declared APNs device identifiers, contact relationships and server-side billing analytics against the final data inventory. The in-bundle manifest is not a substitute for the App Store Connect questionnaire.
