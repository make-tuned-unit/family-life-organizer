# Apple account revocation deployment gate

The revocation change requires a new iOS build AND Apple signing credentials. Keep it off the production branch until these prerequisites are ready: old builds do not submit an authorization code, and the new server intentionally refuses to erase an Apple-linked account without verified revocation.

Configure these Railway production variables through the protected dashboard or CLI input, never by pasting key material into chat, source, PRs or logs:

- `APPLE_SIGNIN_TEAM_ID`: the Apple Developer team that owns `com.kinrows.app`.
- `APPLE_SIGNIN_KEY_ID`: an Apple key enabled for Sign in with Apple for this app.
- `APPLE_SIGNIN_KEY_BASE64`: base64 of that key's complete `.p8` PEM contents.
- `APPLE_SIGNIN_AUD`: `com.kinrows.app` (the code default).

The APNs key is not assumed to have Sign in with Apple capability. If a new key is required, create/download it in the Apple Developer account and configure it securely. Keep the downloaded key in the team's approved secret storage.

The native deletion flow obtains a fresh identity token, nonce and authorization code. The server verifies the identity, exchanges the code, validates the exchanged ID token against the same account/nonce, revokes the refresh token (or access token), and only then erases the account. Tokens are never persisted or logged. A provider failure preserves the account and prompts a retry. Stripe cancellation also must succeed where applicable. The UI separately links to Apple's subscription management because account deletion does not cancel an App Store subscription.

Verification before deployment: mocked HTTP integration and JWT/protocol tests; Release compilation; then real-device Sign in with Apple → delete → verify app authorization removed → re-register, including a linked password account. Do not substitute mocked-provider success for this final gate.

Sources: [Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens), [token exchange](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens), [account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
