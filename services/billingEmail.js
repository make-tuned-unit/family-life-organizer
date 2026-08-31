/**
 * Transactional billing emails (purchase confirmation, payment failed,
 * cancellation). Separate from the waitlist and onboarding drip — these are
 * account/billing mail and still send when a user has opted out of product
 * tips. Stripe continues to send its own receipts; we add a branded Kinrows
 * confirmation plus a portal path when a card fails or a plan ends.
 */

const email = require('./email');
const { BRAND, escapeHtml, emailConfig, sendEmail, isEmailEnabled } = email;

function siteUrl() {
  return (emailConfig.siteUrl || 'https://kinrows.com').replace(/\/$/, '');
}

function shell({ subject, preheader, eyebrow, title, sections }) {
  const site = siteUrl();
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>${escapeHtml(subject)}</title>
<style>
  @media (prefers-color-scheme: dark) {
    .bg { background:#1b140d !important; }
    .card { background:#241a11 !important; }
    .ink1, .brand { color:#fbe6c8 !important; }
    .ink2 { color:#dcc6a6 !important; }
    .ink3 { color:#b59a78 !important; }
    .line { border-color:#3a2c1c !important; }
    .hr { background:#3a2c1c !important; }
  }
  a { color:${BRAND.terra}; }
</style>
</head>
<body class="bg" style="margin:0;padding:0;background:${BRAND.cream};">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(preheader)}&nbsp;&zwnj;</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg" style="background:${BRAND.cream};">
    <tr><td align="center" style="padding:40px 16px;">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;">
        <tr><td align="center" style="padding:8px 0 22px;">
          <span class="brand ink1" style="font-family:Georgia,serif;font-size:34px;font-weight:600;color:${BRAND.ink1};">Kinrows</span>
        </td></tr>
        <tr><td class="card" style="background:${BRAND.card};border-radius:20px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
            <tr><td style="padding:44px 48px 8px;">
              <div style="font-family:Helvetica,Arial,sans-serif;font-size:12px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:${BRAND.sage};">${escapeHtml(eyebrow)}</div>
            </td></tr>
            <tr><td style="padding:6px 48px 0;">
              <h1 class="ink1" style="margin:0;font-family:Georgia,serif;font-size:32px;line-height:1.15;font-weight:600;color:${BRAND.ink1};">${title}</h1>
            </td></tr>
${sections}
            <tr><td style="padding:34px 48px 44px;">
              <div class="hr" style="height:1px;background:${BRAND.line};">&nbsp;</div>
              <p class="ink3" style="margin:14px 0 0;font-family:Helvetica,Arial,sans-serif;font-size:13px;color:${BRAND.ink3};">Questions? Reply to this email &mdash; a real person reads it.</p>
              <p class="ink3" style="margin:8px 0 0;font-family:Helvetica,Arial,sans-serif;font-size:13px;color:${BRAND.ink3};">&mdash; Jesse, Kinrows</p>
            </td></tr>
          </table>
        </td></tr>
        <tr><td align="center" style="padding:26px 48px 8px;">
          <p class="ink3" style="margin:0;font-family:Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:${BRAND.ink3};">
            Billing for your Kinrows household. Stripe also emails a receipt separately.<br>
            Manage or cancel anytime at <a href="${site}/subscribe.html" style="color:${BRAND.ink3};">kinrows.com/subscribe</a>.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
  return html;
}

function p(html) {
  return `            <tr><td style="padding:18px 48px 0;">
              <p class="ink2" style="margin:0;font-family:Helvetica,Arial,sans-serif;font-size:16px;line-height:1.62;color:${BRAND.ink2};">${html}</p>
            </td></tr>`;
}

function cta(label, href) {
  return `            <tr><td style="padding:28px 48px 0;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr><td bgcolor="${BRAND.terra}" style="border-radius:999px;">
                  <a href="${href}" style="display:inline-block;padding:14px 30px;font-family:Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#fffaf0;text-decoration:none;border-radius:999px;">${escapeHtml(label)} &rarr;</a>
                </td></tr>
              </table>
            </td></tr>`;
}

function tierLabel(tier) {
  return tier === 'lite' ? 'Lite' : 'Premium';
}

function subscriptionStartedEmail({ name, tier, period, chats }) {
  const site = siteUrl();
  const who = name ? escapeHtml(name.split(' ')[0]) : 'there';
  const plan = `${tierLabel(tier)}${period === 'yearly' ? ' yearly' : ''}`;
  const subject = `Concierge is on — ${tierLabel(tier)} for your household`;
  const html = shell({
    subject,
    preheader: `Up to ${chats} chats a day, for everyone at home.`,
    eyebrow: 'You\'re in',
    title: `Welcome to Concierge, ${who}.`,
    sections: [
      p(`Your household is on <strong>${escapeHtml(plan)}</strong> &mdash; up to <strong>${Number(chats) || 0} chats a day</strong>, shared by everyone at home. Open Kinrows on your iPhone and tap Concierge.`),
      p('Stripe will email a receipt separately. You can change plans or cancel anytime from the web.'),
      cta('Open billing', `${site}/subscribe.html`),
    ].join('\n'),
  });
  const text = [
    `Concierge is on for your household (${plan}, up to ${chats} chats a day).`,
    'Open Kinrows on your iPhone and tap Concierge.',
    `Manage billing: ${site}/subscribe.html`,
  ].join('\n');
  return { subject, html, text };
}

function paymentFailedEmail({ name, tier }) {
  const site = siteUrl();
  const who = name ? escapeHtml(name.split(' ')[0]) : 'there';
  const subject = 'We couldn\'t renew Kinrows Concierge';
  const html = shell({
    subject,
    preheader: 'Update your card to keep Concierge unlocked.',
    eyebrow: 'Billing',
    title: `${who}, your card didn't go through.`,
    sections: [
      p(`We couldn't renew your household's ${escapeHtml(tierLabel(tier))} plan. Concierge stays on while Stripe retries, then it pauses.`),
      p('Update the card in a minute &mdash; no one else in the household has to do anything.'),
      cta('Update billing', `${site}/subscribe.html`),
    ].join('\n'),
  });
  const text = [
    `We couldn't renew Kinrows Concierge (${tierLabel(tier)}).`,
    `Update billing: ${site}/subscribe.html`,
  ].join('\n');
  return { subject, html, text };
}

function subscriptionCanceledEmail({ name, tier, accessUntil }) {
  const site = siteUrl();
  const who = name ? escapeHtml(name.split(' ')[0]) : 'there';
  const until = accessUntil ? ` Access continues until ${escapeHtml(accessUntil)}.` : '';
  const subject = 'Kinrows Concierge has been canceled';
  const html = shell({
    subject,
    preheader: 'You can resubscribe any time.',
    eyebrow: 'Billing',
    title: `You're unsubscribed, ${who}.`,
    sections: [
      p(`Your household's ${escapeHtml(tierLabel(tier))} plan is canceled.${until} The daily brief stays free; chat needs an active plan.`),
      cta('Resubscribe', `${site}/subscribe.html`),
    ].join('\n'),
  });
  const text = [
    `Kinrows Concierge (${tierLabel(tier)}) is canceled.${until}`,
    `Resubscribe: ${site}/subscribe.html`,
  ].join('\n');
  return { subject, html, text };
}

function eventEmailKind(type) {
  if (type === 'checkout.session.completed' || type === 'checkout.session.async_payment_succeeded') {
    return 'started';
  }
  if (type === 'invoice.payment_failed') return 'failed';
  if (type === 'customer.subscription.deleted') return 'canceled';
  return null;
}

/**
 * Send the matching billing email after a webhook has been applied.
 * Never throws. `send` is injectable for tests.
 */
async function notifyStripeEvent(db, event, result, send = sendEmail) {
  if (!result?.applied) return { sent: false, reason: 'not_applied' };
  const kind = eventEmailKind(event?.type);
  if (!kind) return { sent: false, reason: 'no_email' };
  if (!isEmailEnabled() && send === sendEmail) return { sent: false, reason: 'email_disabled' };

  const userId = result.userId;
  if (!userId) return { sent: false, reason: 'no_user' };
  const user = await db.getUserById(userId);
  const to = user?.email;
  if (!to) return { sent: false, reason: 'no_email_address' };

  const productId = result.productId || '';
  const { tierForProduct, chatsForProduct, PRODUCTS } = require('./subscription');
  const spec = PRODUCTS[productId] || {};
  const payload = {
    name: user.name,
    tier: result.tier || tierForProduct(productId) || 'premium',
    period: spec.period,
    chats: chatsForProduct(productId),
    accessUntil: result.expiresAt || null,
  };

  const tpl = kind === 'started' ? subscriptionStartedEmail(payload)
    : kind === 'failed' ? paymentFailedEmail(payload)
    : subscriptionCanceledEmail(payload);

  const out = await send({ to, ...tpl });
  if (!out?.ok) return { sent: false, reason: out?.error || 'send_failed' };
  return { sent: true, kind, id: out.id };
}

module.exports = {
  subscriptionStartedEmail,
  paymentFailedEmail,
  subscriptionCanceledEmail,
  notifyStripeEvent,
  eventEmailKind,
};
