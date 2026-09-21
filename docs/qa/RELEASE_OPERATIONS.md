# Release operations and remaining acceptance

These procedures are prepared and tested with synthetic local data. A named operator, production email delivery, external backup policy and real-device acceptance still need confirmation. This document does not certify App Store readiness.

## Reports

User reports commit with a durable email job in the same transaction. Notification email carries only the report ID/type/reference, not reported content or the reporter's explanation. Failed delivery retries with backoff; exhausted jobs remain visible. Deleted or resolved reports are skipped at delivery time.

In the trusted server environment, set `FAMILY_DB_DIR` to the mounted database directory. Do not download the production database or print report bodies into shared logs.

```sh
node scripts/moderation.js status
node scripts/moderation.js list
node scripts/moderation.js resolve REPORT_ID remove OPERATOR
node scripts/moderation.js resolve REPORT_ID dismiss OPERATOR
```

`status` prints counts only and exits nonzero for undelivered exhausted reports or reports older than 24 hours. Connect this to the operator's monitoring destination before launch. `list` is privileged and includes the reporter's reason; inspect the referenced record in the protected database before deciding. `remove` permanently removes the reported message/photo or feed post and its children. `dismiss` leaves the content intact. Both record an operator decision and time. Resolution is not reversible through this CLI; do not run it without reviewing the report. Review urgent threats promptly and every open report at least daily; 24 hours is the escalation threshold, not a promise that an unstaffed queue is monitored.

Before launch, prove an actual test report reaches `REPORTS_TO`, confirm who covers the inbox and absences, and exercise a removal with fictional content. Broad text/image filtering remains a separate acceptance gap; the local prohibited-phrase filter is not comprehensive moderation.

## Backup and deletion

Application-owned `backups/family-YYYY-MM-DD.db` snapshots expire by date after 14 days at startup/daily maintenance. New files are mode 0600 in a 0700 directory. Pruning runs before snapshot creation, so a failed new snapshot does not prevent age-based expiry. Unrecognized filenames are not deleted. Snapshots share the database volume: this is not offsite disaster recovery.

A synthetic restore drill opens the snapshot read-only, runs `PRAGMA integrity_check`, and verifies persisted rows. Production restore acceptance still requires a controlled maintenance window, a verified external copy, and reconciliation of account/content deletions made after the selected snapshot. Never reopen a stale snapshot to users until those deletions are reapplied. Historical ad-hoc `.bak` files and provider-managed volume snapshots require an explicit operator retention policy; the application cannot claim it controls them.

Account deletion erases authored social content, direct messages, owned health routines (including shared routines), authored routine entries, linked person profiles, identified trips and owned itineraries, plus auth/device state and queued actor previews. Shared household planning records can survive for other members. Legacy name-only attribution remains ambiguous: do not erase another person's records based on a first-name guess. An ID-based trip ownership field now records only unambiguous household matches; older unlinked trips still require reconciliation.

## Distribution prerequisites

- Draft PR #15 contains Apple authorization-code exchange/revocation. It requires the Sign in with Apple `.p8` key configuration and a compatible native build before deployment.
- This Mac has an Apple Development signing identity; no Apple Distribution identity was found. No signed archive, upload, or TestFlight install has been certified.
- Verify StoreKit product availability, sandbox/review-account strategy, renewals/restores/refunds and server notifications against the real developer account.
- Complete real-device camera, EventKit, HealthKit, speech, background location, APNs, accessibility and small-screen/iPad acceptance.
- Finish App Store Connect privacy, rating, screenshots, territories, agreements, reviewer account and review notes. Do not mark these gates passed from source inspection or a simulator compile.

Apple requirements reviewed against [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) on 2026-09-21. UGC filtering/reporting/blocking, account deletion, working purchases and complete reviewer access remain release criteria.
