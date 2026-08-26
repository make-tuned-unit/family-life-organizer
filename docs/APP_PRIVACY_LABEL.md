# App Store Connect — App Privacy answers

Copy these into App Store Connect → App Privacy. Verified against the code
2026-08-27. **Every data type below: Linked to the user = YES, Used for
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
| Identifiers | **User ID** | Account id; Sign in with Apple `sub` |
| Health & Fitness | **Fitness** | Steps & flights climbed (read with HealthKit consent) → fitness challenges only |
| Location | **Precise Location** | Trip ETA (only while a trip is active) + opt-in household presence |
| Location | **Physical Address** | Family addresses you add, geocoded for maps |
| User Content | **Photos or Videos** | Profile photos, message photos, receipt photos |
| User Content | **Emails or Text Messages** | In-app household messages (DMs, group chat) |
| User Content | **Other User Content** | Calendar events, tasks, lists, notes, pantry, trips, decisions, gifts, feed posts |
| Financial Info | **Other Financial Info** | Budgets, expenses, receipt totals |
| Purchases | **Purchase History** | The signed StoreKit transaction sent for subscription verification |

## NOT collected (answer "No" / don't add)

- Device ID / advertising identifiers — none
- Usage Data (product interaction, analytics) — **none** (no analytics SDK)
- Diagnostics (crash/performance) — **none** (no crash reporter)
- Browsing/Search History — none
- Contacts (address book) — none
- Sensitive Info, Audio Data — none (voice is transcribed on-device only; the mic is hidden if the iPhone cannot do on-device speech)
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
