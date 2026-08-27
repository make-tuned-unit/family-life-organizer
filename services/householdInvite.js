/**
 * Founder-sent household invite emails.
 *
 * The person who set up the household types family emails; we send each
 * recipient the invite code and the two-step join (install → "I have an
 * invite code"). This is separate from the onboarding drip, which emails
 * the founder a reminder to share — not the family members themselves.
 */

const email = require('./email');

const { BRAND, escapeHtml, emailConfig, sendEmail, isEmailEnabled } = email;

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_PER_REQUEST = 8;

function parseEmails(input) {
  const raw = Array.isArray(input) ? input : String(input || '').split(/[,;\s]+/);
  const seen = new Set();
  const emails = [];
  for (const part of raw) {
    const addr = String(part || '').trim().toLowerCase();
    if (!addr) continue;
    if (addr.length > 254 || !EMAIL_RE.test(addr)) {
      const err = new Error('Please enter a valid email address');
      err.status = 400;
      throw err;
    }
    if (seen.has(addr)) continue;
    seen.add(addr);
    emails.push(addr);
  }
  if (emails.length === 0) {
    const err = new Error('Enter at least one email address');
    err.status = 400;
    throw err;
  }
  if (emails.length > MAX_PER_REQUEST) {
    const err = new Error(`You can invite up to ${MAX_PER_REQUEST} people at a time`);
    err.status = 400;
    throw err;
  }
  return emails;
}

function householdInviteEmail({ inviterName, householdName, inviteCode }) {
  const site = emailConfig.siteUrl;
  const who = inviterName ? escapeHtml(inviterName) : 'Your family';
  const house = escapeHtml(householdName || 'our household');
  const code = escapeHtml(inviteCode || '');
  const subject = `${inviterName || 'Your family'} invited you to ${householdName || 'Kinrows'}`;
  const preheader = `Your invite code is ${inviteCode}. Open Kinrows, tap “I have an invite code,” and you’re in.`;
  const html = `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(subject)}</title>
<meta name="color-scheme" content="light dark">
<style>
  @media (prefers-color-scheme: dark) {
    .bg { background:#1b140d !important; }
    .card { background:#241a11 !important; }
    .ink1 { color:#fbe6c8 !important; }
    .ink2 { color:#dcc6a6 !important; }
    .ink3 { color:#b59a78 !important; }
    .line { border-color:#3a2c1c !important; }
  }
</style>
</head>
<body class="bg" style="margin:0; padding:0; width:100%; background:${BRAND.cream};">
  <div style="display:none; max-height:0; overflow:hidden; opacity:0;">${escapeHtml(preheader)}</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg" style="background:${BRAND.cream};">
    <tr><td align="center" style="padding:32px 16px;">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" class="card" style="max-width:600px; width:100%; background:${BRAND.card}; border-radius:20px;">
        <tr><td style="padding:36px 40px 8px; font-family:Georgia,serif; font-size:28px; color:${BRAND.ink1};">Kinrows</td></tr>
        <tr><td class="ink1" style="padding:8px 40px 0; font-family:Georgia,serif; font-size:24px; color:${BRAND.ink1};">${who} set up ${house}.</td></tr>
        <tr><td class="ink2" style="padding:16px 40px 0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:16px; line-height:1.5; color:${BRAND.ink2};">
          Kinrows is the family organizer we use together &mdash; calendar, lists, the week. Join with this code and everything they&rsquo;ve already added is waiting.
        </td></tr>
        <tr><td style="padding:28px 40px 0;">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
            <tr>
              <td class="line" align="center" style="border:1px dashed ${BRAND.saffron}; border-radius:12px; padding:16px 24px;">
                <span class="ink3" style="font-family:'Helvetica Neue',Arial,sans-serif; font-size:11px; font-weight:700; letter-spacing:0.12em; text-transform:uppercase; color:${BRAND.ink3};">Invite code</span><br>
                <span class="ink1" style="font-family:'Courier New',monospace; font-size:26px; font-weight:700; letter-spacing:0.18em; color:${BRAND.ink1};">${code}</span>
              </td>
            </tr>
          </table>
        </td></tr>
        <tr><td class="ink2" style="padding:24px 40px 0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:15px; line-height:1.55; color:${BRAND.ink2};">
          1. Install Kinrows from the App Store.<br>
          2. Tap <strong>I have an invite code</strong>.<br>
          3. Enter the code and sign in &mdash; Apple is the fastest.
        </td></tr>
        <tr><td style="padding:28px 40px 40px; font-family:'Helvetica Neue',Arial,sans-serif; font-size:13px; color:${BRAND.ink3};">
          <a href="${site}" style="color:${BRAND.terra};">kinrows.com</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  const text = [
    `${inviterName || 'Your family'} set up ${householdName || 'a household'} on Kinrows.`,
    '',
    `Your invite code: ${inviteCode}`,
    '',
    '1. Install Kinrows from the App Store.',
    '2. Tap “I have an invite code”.',
    '3. Enter the code and sign in — Apple is the fastest.',
    '',
    site,
  ].join('\n');
  return { subject, html, text };
}

/**
 * Send one invite email per address. `send` is injectable for tests.
 * Never throws on delivery failure — returns per-address ok/error.
 */
async function sendHouseholdInvites({ inviterName, householdName, inviteCode, emails, send = sendEmail }) {
  const sent = [];
  const failed = [];
  for (const to of emails) {
    const msg = householdInviteEmail({ inviterName, householdName, inviteCode });
    const result = await send({ to, subject: msg.subject, html: msg.html, text: msg.text });
    if (result && result.ok) sent.push(to);
    else failed.push({ email: to, error: result?.error || 'send failed' });
  }
  return { sent, failed };
}

module.exports = {
  MAX_PER_REQUEST,
  parseEmails,
  householdInviteEmail,
  sendHouseholdInvites,
  isEmailEnabled,
};
