/**
 * Transactional email via Resend (https://resend.com).
 *
 * Sends through the verified kinrows.com domain. Configure in the host (Railway):
 *   RESEND_API_KEY   – required; from the Resend dashboard → API Keys
 *   WAITLIST_FROM    – optional; sender, default "Kinrows <hello@kinrows.com>"
 *   WAITLIST_REPLY_TO– optional; reply-to, default "hello@kinrows.com"
 *   WAITLIST_NOTIFY  – optional; address that gets a ping on each new signup
 *   SITE_URL         – optional; default "https://kinrows.com"
 *
 * No new npm dependency — talks to the Resend REST API with fetch (Node 18+).
 */

const RESEND_ENDPOINT = 'https://api.resend.com/emails';

const config = {
  apiKey: process.env.RESEND_API_KEY || '',
  from: process.env.WAITLIST_FROM || 'Kinrows <hello@kinrows.com>',
  replyTo: process.env.WAITLIST_REPLY_TO || 'hello@kinrows.com',
  notify: process.env.WAITLIST_NOTIFY || '',
  siteUrl: (process.env.SITE_URL || 'https://kinrows.com').replace(/\/$/, ''),
};

function isEmailEnabled() {
  return Boolean(config.apiKey);
}

/**
 * Low-level send. Resolves to { ok, id?, error? } — never throws, so callers
 * (e.g. the waitlist endpoint) can succeed even if email delivery hiccups.
 */
async function sendEmail({ to, subject, html, text, from, replyTo, headers }) {
  if (!isEmailEnabled()) {
    return { ok: false, error: 'RESEND_API_KEY not set' };
  }
  try {
    const res = await fetch(RESEND_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: from || config.from,
        to: Array.isArray(to) ? to : [to],
        subject,
        html,
        text,
        reply_to: replyTo || config.replyTo,
        // Custom SMTP headers (e.g. List-Unsubscribe for one-click opt-out).
        ...(headers ? { headers } : {}),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) return { ok: false, error: data?.message || `HTTP ${res.status}` };
    return { ok: true, id: data?.id };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

// ── Templates ────────────────────────────────────────────────────────────────

// Kinrows Direction 2.0 tokens (brand/tokens/kinrows-brand-tokens.json) as
// email-safe hexes. Evergreen for primary actions, Sun/Clay/Sage deep shades
// for glyph-sized accents, Oat/Ink for surfaces and text.
const BRAND = {
  cream: '#F7F3E9',      // oat — page
  card: '#FBF9F3',       // oat light — card
  ink1: '#1F2A24',
  ink2: '#3E4A43',
  ink3: '#6B756F',
  line: '#E8EEE9',       // mist
  evergreen: '#0F3D37',
  terra: '#C76F4F',      // clay
  saffron: '#B9891A',    // sun deep
  sage: '#5E8262',       // sage deep
  sun: '#F2C94C',
};

// Dark-mode palette: flat deep evergreen (the pattern tile is dropped because
// the shorthand `background` override replaces the image).
const DARK = {
  bg: '#0B2E2A', card: '#12403A', ink1: '#F7F3E9', ink2: '#D6DED8', ink3: '#A9B1AC', line: '#1F5047',
};

/** Repeating brand pattern behind every customer email (leaf / wave / sun tile). */
function patternUrl(site = config.siteUrl) {
  return `${site}/assets/brand/patterns/email-pattern.jpg`;
}

/**
 * Attributes + inline style for the full-width outer table so the pattern
 * tiles behind the card in every client that renders CSS backgrounds.
 */
function patternTableAttrs(site = config.siteUrl) {
  const url = patternUrl(site);
  return `class="bg" background="${url}" bgcolor="${BRAND.cream}" style="background-color:${BRAND.cream}; background-image:url('${url}'); background-repeat:repeat; background-position:top center; background-size:512px 768px;"`;
}

/** Outlook (Word engine) ignores CSS backgrounds; VML paints the same tile. */
function patternVml(site = config.siteUrl) {
  return `<!--[if gte mso 9]><v:background xmlns:v="urn:schemas-microsoft-com:vml" fill="true" stroke="false"><v:fill type="tile" src="${patternUrl(site)}" color="${BRAND.cream}"/></v:background><![endif]-->`;
}

/** Shared <style> block: dark mode + link colour + mobile padding. */
function sharedCss() {
  return `
  @media (prefers-color-scheme: dark) {
    .bg { background:${DARK.bg} !important; }
    .card { background:${DARK.card} !important; }
    .ink1, .brand { color:${DARK.ink1} !important; }
    .ink2 { color:${DARK.ink2} !important; }
    .ink3 { color:${DARK.ink3} !important; }
    .line { border-color:${DARK.line} !important; }
    .hr { background:${DARK.line} !important; }
  }
  a { color:${BRAND.evergreen}; }
  @media only screen and (max-width:620px) {
    .px { padding-left:24px !important; padding-right:24px !important; }
    .brand { font-size:30px !important; }
    .h1 { font-size:30px !important; }
  }`;
}

/** Footer mark: the app icon from the brand assets (the old logo.png is gone). */
function footerMark(site = config.siteUrl) {
  return `<img src="${site}/assets/brand/apple-touch-icon.png" width="44" height="44" alt="Kinrows" style="display:block; margin:0 auto 14px; border-radius:11px;">`;
}

/** Premium, table-based, dark-mode-aware welcome email for new waitlist signups. */
function waitlistWelcomeEmail() {
  const site = config.siteUrl;
  const preheader = "You're on the list. We'll send one email — the day Kinrows lands on the App Store.";
  const html = `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>Welcome to Kinrows</title>
<!--[if mso]><style>* {font-family: Georgia, serif !important;}</style><![endif]-->
<style>${sharedCss()}
</style>
</head>
<body class="bg" style="margin:0; padding:0; width:100%; background:${BRAND.cream}; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;">
  ${patternVml(site)}
  <div style="display:none; max-height:0; overflow:hidden; opacity:0; mso-hide:all;">${preheader}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" ${patternTableAttrs(site)}>
    <tr>
      <td align="center" style="padding:40px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px;">

          <!-- Wordmark -->
          <tr>
            <td align="center" style="padding:8px 0 22px;">
              <span class="brand ink1" style="font-family:Georgia,'Times New Roman',serif; font-size:34px; font-weight:600; letter-spacing:-0.5px; color:${BRAND.ink1};">Kinrows</span>
            </td>
          </tr>

          <!-- Card -->
          <tr>
            <td class="card" style="background:${BRAND.card}; border-radius:20px; box-shadow:0 1px 0 ${BRAND.line};">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="px" style="padding:44px 48px 8px;">
                    <div style="font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; font-weight:700; letter-spacing:0.12em; text-transform:uppercase; color:${BRAND.sage};">You're in</div>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:6px 48px 0;">
                    <h1 class="h1 ink1" style="margin:0; font-family:Georgia,'Times New Roman',serif; font-size:36px; line-height:1.12; font-weight:600; letter-spacing:-0.5px; color:${BRAND.ink1};">Welcome to the&nbsp;list.</h1>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:18px 48px 0;">
                    <p class="ink2" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:16px; line-height:1.62; color:${BRAND.ink2};">
                      Thanks for raising your hand. Kinrows is a calm, private home for everything your household carries &mdash; the calendar, the lists, the trips, the little decisions &mdash; gathered into one place everyone can see. No more scattered group chats and sticky notes.
                    </p>
                  </td>
                </tr>

                <!-- What to expect -->
                <tr>
                  <td class="px" style="padding:26px 48px 0;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="line" style="border:1px solid ${BRAND.line}; border-radius:14px;">
                      <tr>
                        <td style="padding:18px 20px;">
                          <p class="ink1" style="margin:0 0 4px; font-family:'Helvetica Neue',Arial,sans-serif; font-size:14px; font-weight:600; color:${BRAND.ink1};">What happens next</p>
                          <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:14px; line-height:1.6; color:${BRAND.ink3};">
                            We'll send you <strong style="color:${BRAND.ink2};">one email</strong> &mdash; the day Kinrows lands on the App Store, with early access ahead of everyone else. That's it. No list-selling, no weekly noise.
                          </p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>

                <!-- CTA -->
                <tr>
                  <td class="px" style="padding:28px 48px 0;">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td align="center" bgcolor="${BRAND.evergreen}" style="border-radius:999px;">
                          <a href="${site}/#how" style="display:inline-block; padding:14px 30px; font-family:'Helvetica Neue',Arial,sans-serif; font-size:15px; font-weight:600; color:${BRAND.cream}; text-decoration:none; border-radius:999px;">See how it works &rarr;</a>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>

                <!-- Signature -->
                <tr>
                  <td class="px" style="padding:34px 48px 8px;">
                    <div class="hr" style="height:1px; line-height:1px; font-size:0; background:${BRAND.line};">&nbsp;</div>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:14px 48px 44px;">
                    <p class="ink2" style="margin:0; font-family:Georgia,'Times New Roman',serif; font-size:16px; font-style:italic; line-height:1.5; color:${BRAND.ink2};">&ldquo;Built for our own family first. We can't wait to share it.&rdquo;</p>
                    <p class="ink3" style="margin:8px 0 0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:13px; color:${BRAND.ink3};">&mdash; Jesse, Kinrows</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td class="px" style="padding:26px 48px 8px;" align="center">
              ${footerMark(site)}
              <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; line-height:1.6; color:${BRAND.ink3};">
                You're getting this because you joined the waitlist at <a href="${site}" style="color:${BRAND.ink3};">kinrows.com</a>.<br>
                Not you, or changed your mind? Just reply &mdash; we'll take you off the list, no hard feelings.
              </p>
              <p class="ink3" style="margin:12px 0 0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; color:${BRAND.ink3};">Kinrows &middot; Private to your family &middot; No ads</p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const text = [
    "You're in — welcome to Kinrows.",
    '',
    'Thanks for raising your hand. Kinrows is a calm, private home for everything',
    'your household carries — the calendar, the lists, the trips, the little',
    'decisions — gathered into one place everyone can see.',
    '',
    "What happens next: we'll send you ONE email — the day Kinrows lands on the",
    "App Store, with early access ahead of everyone else. That's it. No list-selling,",
    'no weekly noise.',
    '',
    `See how it works: ${site}/#how`,
    '',
    "“Built for our own family first. We can't wait to share it.” — Jesse, Kinrows",
    '',
    `You're getting this because you joined the waitlist at kinrows.com.`,
    "Not you, or changed your mind? Just reply and we'll take you off the list.",
  ].join('\n');

  return { subject: 'Welcome to Kinrows — you’re in', html, text };
}


/** Sign-in verification code — same chrome as every Kinrows email, code up front. */
function loginCodeEmail(code) {
  const site = config.siteUrl;
  const safe = escapeHtml(String(code));
  const html = `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>Your Kinrows code</title>
<style>${sharedCss()}
</style>
</head>
<body class="bg" style="margin:0; padding:0; width:100%; background:${BRAND.cream}; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;">
  ${patternVml(site)}
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" ${patternTableAttrs(site)}>
    <tr>
      <td align="center" style="padding:40px 16px;">
        <table role="presentation" width="480" cellpadding="0" cellspacing="0" border="0" style="width:480px; max-width:480px;">
          <tr>
            <td align="center" style="padding:8px 0 22px;">
              <span class="brand ink1" style="font-family:Georgia,'Times New Roman',serif; font-size:30px; font-weight:600; letter-spacing:-0.5px; color:${BRAND.ink1};">Kinrows</span>
            </td>
          </tr>
          <tr>
            <td class="card" style="background:${BRAND.card}; border-radius:20px; box-shadow:0 1px 0 ${BRAND.line};">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="px" style="padding:36px 40px 6px;">
                    <div style="font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; font-weight:700; letter-spacing:0.12em; text-transform:uppercase; color:${BRAND.sage};">Sign in</div>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:6px 40px 0;">
                    <h1 class="h1 ink1" style="margin:0; font-family:Georgia,'Times New Roman',serif; font-size:28px; line-height:1.15; font-weight:600; color:${BRAND.ink1};">Your verification code</h1>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:16px 40px 0;">
                    <p class="ink2" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:15px; line-height:1.6; color:${BRAND.ink2};">Your Kinrows verification code is:</p>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:16px 40px 0;">
                    <p class="line ink1" style="margin:0; font-size:34px; font-weight:700; letter-spacing:8px; background:${BRAND.cream}; border:1px solid ${BRAND.line}; border-radius:12px; padding:16px; text-align:center; font-family:'Courier New',monospace; color:${BRAND.ink1};">${safe}</p>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:16px 40px 36px;">
                    <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:13px; line-height:1.6; color:${BRAND.ink3};">Let your iPhone fill it in, or tap to copy it. It expires in 10 minutes. If this wasn&rsquo;t you, ignore this email.</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td class="px" style="padding:26px 40px 8px;" align="center">
              ${footerMark(site)}
              <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; color:${BRAND.ink3};">Kinrows &middot; Private to your family &middot; No ads</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  return { html };
}

// Escape user-supplied text before it lands in an HTML email body. The signup
// email passes only a loose regex, so an address like `<a href=…>x</a>@x.co`
// would otherwise render attacker markup in the notification inbox.
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/** Tiny internal heads-up when someone joins. Plain + cheap. */
function waitlistNotifyEmail(email, total) {
  const safeEmail = escapeHtml(email);
  return {
    subject: `New Kinrows waitlist signup${total ? ` (#${total})` : ''}`,
    html: `<p style="font-family:system-ui,sans-serif;font-size:15px;color:#2c2017;">New waitlist signup: <strong>${safeEmail}</strong>${total ? ` — ${total} total.` : '.'}</p>`,
    text: `New waitlist signup: ${email}${total ? ` — ${total} total.` : '.'}`,
  };
}

module.exports = {
  isEmailEnabled,
  sendEmail,
  waitlistWelcomeEmail,
  waitlistNotifyEmail,
  loginCodeEmail,
  emailConfig: config,
  BRAND,
  DARK,
  escapeHtml,
  patternUrl,
  patternTableAttrs,
  patternVml,
  sharedCss,
  footerMark,
};
