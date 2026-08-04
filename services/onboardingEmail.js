/**
 * Onboarding email drip for registered app users.
 *
 * Five stages, spaced from the PREVIOUS send (never from account age), so a
 * user who adds their email weeks after signing up still gets the sequence
 * gently from the start instead of a burst of "catch-up" mail:
 *
 *   welcome    — immediately once a verified address exists
 *   household  — +2 days: invite your people (the product is better together)
 *   concierge  — +3 days: what the AI Concierge can do (tailored to tier)
 *   rhythm     — +4 days: deeper features (calendar sync, routines, budget, trips)
 *   checkin    — +5 days: two-week check-in, reply-to-a-human
 *
 * The hourly sweep (dashboard.js startOnboardingEmails) sends AT MOST one
 * stage per user per run; the onboarding_emails UNIQUE(user_id, email_key) log
 * is the idempotence guard. Every message carries an unsubscribe link plus
 * RFC 8058 one-click List-Unsubscribe headers; opted-out users are excluded at
 * the candidate query. This drip is separate from the marketing waitlist
 * (which promised "one email" and keeps that promise).
 */

const email = require('./email');
const subscription = require('./subscription');

const { BRAND, escapeHtml, emailConfig } = email;

// Public URL of THIS server (unsubscribe links must land on the API, not the
// static marketing site).
const API_URL = (process.env.APP_API_URL
  || 'https://family-life-organizer-production.up.railway.app').replace(/\/$/, '');

const STAGES = [
  { key: 'welcome', afterDays: 0 },
  { key: 'household', afterDays: 2 },
  { key: 'concierge', afterDays: 3 },
  { key: 'rhythm', afterDays: 4 },
  { key: 'checkin', afterDays: 5 },
];

// ── Shared shell ─────────────────────────────────────────────────────────────

/**
 * Wraps a stage's content in the Kinrows email chrome: 600px card, dark-mode
 * aware, hidden preheader, wordmark, footer with a real unsubscribe link.
 * `sections` is pre-built HTML rows (use the p/box/cta helpers below).
 */
function shell({ subject, preheader, eyebrow, eyebrowColor, title, sections, unsubUrl }) {
  const site = emailConfig.siteUrl;
  const html = `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${escapeHtml(subject)}</title>
<!--[if mso]><style>* {font-family: Georgia, serif !important;}</style><![endif]-->
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
  @media only screen and (max-width:620px) {
    .px { padding-left:24px !important; padding-right:24px !important; }
    .brand { font-size:30px !important; }
    .h1 { font-size:28px !important; }
  }
</style>
</head>
<body class="bg" style="margin:0; padding:0; width:100%; background:${BRAND.cream}; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;">
  <div style="display:none; max-height:0; overflow:hidden; opacity:0; mso-hide:all;">${escapeHtml(preheader)}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg" style="background:${BRAND.cream};">
    <tr>
      <td align="center" style="padding:40px 16px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px;">
          <tr>
            <td align="center" style="padding:8px 0 22px;">
              <span class="brand ink1" style="font-family:Georgia,'Times New Roman',serif; font-size:34px; font-weight:600; letter-spacing:-0.5px; color:${BRAND.ink1};">Kinrows</span>
            </td>
          </tr>
          <tr>
            <td class="card" style="background:${BRAND.card}; border-radius:20px; box-shadow:0 1px 0 ${BRAND.line};">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td class="px" style="padding:44px 48px 8px;">
                    <div style="font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; font-weight:700; letter-spacing:0.12em; text-transform:uppercase; color:${eyebrowColor || BRAND.sage};">${escapeHtml(eyebrow)}</div>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:6px 48px 0;">
                    <h1 class="h1 ink1" style="margin:0; font-family:Georgia,'Times New Roman',serif; font-size:32px; line-height:1.15; font-weight:600; letter-spacing:-0.5px; color:${BRAND.ink1};">${title}</h1>
                  </td>
                </tr>
${sections}
                <tr>
                  <td class="px" style="padding:34px 48px 8px;">
                    <div class="hr" style="height:1px; line-height:1px; font-size:0; background:${BRAND.line};">&nbsp;</div>
                  </td>
                </tr>
                <tr>
                  <td class="px" style="padding:14px 48px 44px;">
                    <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:13px; line-height:1.6; color:${BRAND.ink3};">Questions? Just reply &mdash; a real person reads every message.</p>
                    <p class="ink3" style="margin:8px 0 0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:13px; color:${BRAND.ink3};">&mdash; Jesse, Kinrows</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td class="px" style="padding:26px 48px 8px;" align="center">
              <img src="${site}/assets/logo.png" width="44" height="44" alt="Kinrows" style="display:block; margin:0 auto 14px; border-radius:11px;">
              <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; line-height:1.6; color:${BRAND.ink3};">
                A few getting-started notes because you created a Kinrows account &mdash; then we go quiet.<br>
                <a href="${unsubUrl}" style="color:${BRAND.ink3};">Unsubscribe</a> any time; account and security emails still reach you.
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
  return html;
}

// Row helpers — each returns one <tr> for the card table.
function p(html, pad = '18px 48px 0') {
  return `                <tr>
                  <td class="px" style="padding:${pad};">
                    <p class="ink2" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:16px; line-height:1.62; color:${BRAND.ink2};">${html}</p>
                  </td>
                </tr>`;
}

// Bordered feature box with a heading and item rows [{title, body}].
function box(heading, items) {
  const rows = items.map(it => `
                          <p class="ink1" style="margin:12px 0 2px; font-family:'Helvetica Neue',Arial,sans-serif; font-size:14px; font-weight:600; color:${BRAND.ink1};">${it.title}</p>
                          <p class="ink3" style="margin:0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:14px; line-height:1.6; color:${BRAND.ink3};">${it.body}</p>`).join('');
  return `                <tr>
                  <td class="px" style="padding:26px 48px 0;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="line" style="border:1px solid ${BRAND.line}; border-radius:14px;">
                      <tr>
                        <td style="padding:8px 20px 18px;">
                          <p style="margin:12px 0 0; font-family:'Helvetica Neue',Arial,sans-serif; font-size:12px; font-weight:700; letter-spacing:0.1em; text-transform:uppercase; color:${BRAND.saffron};">${escapeHtml(heading)}</p>${rows}
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}

// "Chat bubble" rows for the concierge email — asks the reader could type.
function bubbles(prompts) {
  const rows = prompts.map(t => `
                      <tr>
                        <td style="padding:5px 0;">
                          <span class="line ink1" style="display:inline-block; padding:10px 16px; border:1px solid ${BRAND.line}; border-radius:16px; font-family:'Helvetica Neue',Arial,sans-serif; font-size:14px; line-height:1.5; color:${BRAND.ink1};">&ldquo;${escapeHtml(t)}&rdquo;</span>
                        </td>
                      </tr>`).join('');
  return `                <tr>
                  <td class="px" style="padding:22px 48px 0;">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0">${rows}
                    </table>
                  </td>
                </tr>`;
}

function cta(label, href) {
  return `                <tr>
                  <td class="px" style="padding:28px 48px 0;">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td align="center" bgcolor="${BRAND.terra}" style="border-radius:999px;">
                          <a href="${href}" style="display:inline-block; padding:14px 30px; font-family:'Helvetica Neue',Arial,sans-serif; font-size:15px; font-weight:600; color:#fffaf0; text-decoration:none; border-radius:999px;">${escapeHtml(label)} &rarr;</a>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}

// Highlighted invite-code chip.
function inviteChip(code) {
  if (!code) return '';
  return `                <tr>
                  <td class="px" style="padding:22px 48px 0;">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td class="line" align="center" style="border:1px dashed ${BRAND.saffron}; border-radius:12px; padding:12px 26px;">
                          <span class="ink3" style="font-family:'Helvetica Neue',Arial,sans-serif; font-size:11px; font-weight:700; letter-spacing:0.12em; text-transform:uppercase; color:${BRAND.ink3};">Your household invite code</span><br>
                          <span class="ink1" style="font-family:'Courier New',monospace; font-size:24px; font-weight:700; letter-spacing:0.18em; color:${BRAND.ink1};">${escapeHtml(code)}</span>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>`;
}

// ── Stage templates ──────────────────────────────────────────────────────────
// ctx: { firstName, inviteCode, tier ('premium'|'lite'|null), unsubUrl }

const TEMPLATES = {
  welcome(ctx) {
    const site = emailConfig.siteUrl;
    const hi = ctx.firstName ? `Hi ${escapeHtml(ctx.firstName)} &mdash; welcome` : 'Welcome';
    const sections = [
      p(`${hi} to Kinrows: one calm place for everything your household carries. The calendar, the lists, the meals, the trips, the little decisions &mdash; out of scattered group chats and into a home everyone can see.`),
      box('Three quick wins for today', [
        { title: 'Put the week on the calendar', body: 'Add tonight&rsquo;s plans and this week&rsquo;s appointments. Everyone in your household sees them instantly.' },
        { title: 'Start your first list', body: 'A grocery list is the classic opener &mdash; add a few staples and watch items check off in real time.' },
        { title: 'Say hello in the family feed', body: 'Post a photo or a note. The feed is your family&rsquo;s private timeline &mdash; no ads, no algorithm.' },
      ]),
      ctx.inviteCode ? inviteChip(ctx.inviteCode) + p(`Kinrows really starts when your people join. Share this code from the app (More &rarr; Household) and your partner lands in the same household automatically.`, '14px 48px 0') : '',
      cta('See what Kinrows can do', `${site}/#how`),
    ].join('\n');
    return {
      subject: 'Welcome to Kinrows — your household, in one calm place',
      preheader: 'Three quick wins for your first day, and your household invite code.',
      eyebrow: 'Welcome aboard', eyebrowColor: BRAND.sage,
      title: 'One calm place for the whole&nbsp;household.',
      sections,
      text: [
        `${ctx.firstName ? `Hi ${ctx.firstName} — welcome` : 'Welcome'} to Kinrows: one calm place for everything your household carries.`,
        '',
        'Three quick wins for today:',
        '  1. Put the week on the calendar — everyone sees it instantly.',
        '  2. Start your first list — groceries are the classic opener.',
        '  3. Say hello in the family feed — your private, ad-free timeline.',
        '',
        ctx.inviteCode ? `Your household invite code: ${ctx.inviteCode} (share it from More → Household)` : '',
        '',
        `See what Kinrows can do: ${site}/#how`,
      ].filter(l => l !== null).join('\n'),
    };
  },

  household(ctx) {
    const sections = [
      p(`Kinrows on your own is a good organizer. Kinrows with your people is a different thing entirely &mdash; the calendar fills itself in, the grocery list updates from the store aisle, and the mental load finally gets shared.`),
      box('Bringing everyone in', [
        { title: 'Your partner', body: `They install Kinrows, tap &ldquo;Join a household&rdquo; at sign-up, and enter your invite code. Everything you&rsquo;ve added is already there.` },
        { title: 'Kids without phones', body: 'Add them under People. They get birthdays, milestones, appointments and gift ideas of their own — no account needed.' },
        { title: 'Grandparents &amp; cousins', body: 'Clans connect whole households — share a feed and key dates across families while daily life stays private to yours.' },
      ]),
      ctx.inviteCode ? inviteChip(ctx.inviteCode) : '',
      p(`Everything in Kinrows is scoped to your household by design. What you share, you choose &mdash; nothing leaks, ever.`, '22px 48px 0'),
    ].join('\n');
    return {
      subject: 'Kinrows is better with your people in it',
      preheader: 'Invite your partner, add the kids, connect the grandparents.',
      eyebrow: 'Better together', eyebrowColor: BRAND.terra,
      title: 'A family does better when it rows&nbsp;together.',
      sections,
      text: [
        'Kinrows on your own is a good organizer. With your people, the mental load finally gets shared.',
        '',
        'Bringing everyone in:',
        '  • Your partner: they join with your invite code at sign-up.',
        '  • Kids without phones: add them under People — no account needed.',
        '  • Grandparents & cousins: Clans connect whole households while daily life stays private.',
        '',
        ctx.inviteCode ? `Your household invite code: ${ctx.inviteCode}` : '',
      ].join('\n'),
    };
  },

  concierge(ctx) {
    const site = emailConfig.siteUrl;
    const premium = ctx.tier === 'premium' || ctx.tier === 'lite';
    const prompts = [
      'Add swim practice every Tuesday at 4',
      'What should we make for dinner with what’s in the pantry?',
      'Plan Rowan’s birthday — party list, gift ideas, and a budget',
      'What does our week look like?',
    ];
    const sections = premium ? [
      p(`Your household has the Concierge &mdash; here&rsquo;s how to get your money&rsquo;s worth. It already knows your calendar, lists, budget, trips and birthdays, so you can hand it real work in plain words:`),
      bubbles(prompts),
      box('Make it a habit', [
        { title: 'Start the day with the brief', body: 'A warm, prioritized &ldquo;here&rsquo;s your family right now&rdquo; digest — open the Concierge tab each morning.' },
        { title: 'Hold to talk', body: 'Press and hold the sparkle button to speak instead of type. Perfect with your hands full.' },
        { title: 'Let it nudge you', body: 'The Concierge quietly watches for expiring pantry items, empty weekends and looming birthdays, and taps you on the shoulder.' },
      ]),
    ].join('\n') : [
      p(`Every feature you&rsquo;ve seen so far, you drive yourself. The <strong style="color:${BRAND.ink1};">Concierge</strong> is the optional assistant that drives them for you &mdash; it knows your family&rsquo;s calendar, lists, budget, trips and birthdays, and does the doing when you ask:`),
      bubbles(prompts),
      box('What it does all day', [
        { title: 'Briefs you', body: 'A warm morning digest of what your family has on — free to read in the Concierge tab.' },
        { title: 'Does things for you', body: 'One sentence becomes a calendar event, a stocked list, or a planned trip. No forms.' },
        { title: 'Stays a step ahead', body: 'Gentle nudges before things fall through the cracks — the pantry item expiring, the birthday two weeks out.' },
      ]),
      p(`It&rsquo;s off until you say otherwise, and your daily brief is free. Flip it on in the app under <strong style="color:${BRAND.ink1};">More &rarr; AI Concierge</strong> to see it work on your own family&rsquo;s week.`, '22px 48px 0'),
      cta('See the Concierge in action', `${site}/#concierge`),
    ].join('\n');
    return {
      subject: premium ? 'Getting the most from your Concierge' : 'Meet the Concierge — the assistant for the invisible work',
      preheader: premium ? 'The morning brief, hold-to-talk, and proactive nudges.' : 'It knows your week and does the doing. Off until you say otherwise.',
      eyebrow: 'Meet the Concierge', eyebrowColor: BRAND.saffron,
      title: premium ? 'Your Concierge is on the&nbsp;clock.' : 'The assistant that keeps family life running&nbsp;smoothly.',
      sections,
      text: [
        premium
          ? 'Your household has the Concierge — here’s how to get your money’s worth. Hand it real work in plain words:'
          : 'The Concierge is the optional assistant that drives Kinrows for you. Ask things like:',
        ...prompts.map(pr => `  • "${pr}"`),
        '',
        premium
          ? 'Make it a habit: read the morning brief, hold the sparkle button to talk, and let it nudge you before things slip.'
          : 'It briefs you each morning (free), does things for you, and stays a step ahead with gentle nudges.\n\nIt’s off until you say otherwise — flip it on under More → AI Concierge.',
        '',
        premium ? '' : `See it in action: ${site}/#concierge`,
      ].join('\n'),
    };
  },

  rhythm(ctx) {
    const sections = [
      p(`By now the basics are humming. This is the layer underneath &mdash; the features that turn Kinrows from a shared calendar into the operating system for your family&rsquo;s week.`),
      box('Worth five minutes each', [
        { title: 'Sync your device calendar', body: 'Settings &rarr; Household calendar mirrors everyone&rsquo;s existing calendars into one merged, color-coded view — Google and Apple included.' },
        { title: 'Routines', body: 'Nap schedules, sleep training, cycles — private trackers that quietly nudge you at the right moment.' },
        { title: 'Budget &amp; recurring payments', body: 'Scan receipts, watch category progress, and never be surprised by a renewal again.' },
        { title: 'Trips', body: 'Itineraries, packing lists and travel expenses in one hub — with &ldquo;time to leave&rdquo; nudges for located events.' },
      ]),
      p(`Pick whichever one touches your week most &mdash; each takes minutes to set up and then just runs.`, '22px 48px 0'),
    ].join('\n');
    return {
      subject: 'Find your family’s rhythm',
      preheader: 'Calendar sync, routines, budget and trips — the layer underneath.',
      eyebrow: 'Going deeper', eyebrowColor: BRAND.sage,
      title: 'Find your family&rsquo;s&nbsp;rhythm.',
      sections,
      text: [
        'By now the basics are humming. This is the layer underneath:',
        '',
        '  • Sync your device calendar — one merged, color-coded household view.',
        '  • Routines — nap schedules, sleep training, cycles, with timely nudges.',
        '  • Budget & recurring payments — receipts, categories, renewals.',
        '  • Trips — itineraries, packing lists and travel expenses in one hub.',
        '',
        'Pick whichever touches your week most — each takes minutes to set up.',
      ].join('\n'),
    };
  },

  checkin(ctx) {
    const premium = ctx.tier === 'premium' || ctx.tier === 'lite';
    const sections = [
      p(`${ctx.firstName ? escapeHtml(ctx.firstName) + ', you' : 'You'}&rsquo;ve had Kinrows for a couple of weeks &mdash; long enough to know whether it&rsquo;s earning its place on your home screen. Two things, then we&rsquo;ll leave your inbox in peace:`),
      box('Before we go quiet', [
        { title: 'Tell us one true thing', body: 'Reply to this email with the one thing that&rsquo;s working — or the one thing that isn&rsquo;t. Replies come straight to the family that builds Kinrows, and they steer what we build next.' },
        premium
          ? { title: 'Squeeze the Concierge', body: 'If you haven&rsquo;t yet: open the morning brief tomorrow, and try handing it one chore you&rsquo;d normally type out by hand.' }
          : { title: 'Give the Concierge one honest try', body: 'The morning brief is free. Flip it on under More &rarr; AI Concierge and let it read your week back to you once — that&rsquo;s usually the moment it clicks.' },
        { title: 'Know someone drowning in group chats?', body: 'Kinrows grows family by family, not by ad budget. If it&rsquo;s helping yours, telling one other household is the biggest thanks there is.' },
      ]),
      p(`That&rsquo;s the whole onboarding series &mdash; from here, the only emails you&rsquo;ll get are the ones your account needs.`, '22px 48px 0'),
    ].join('\n');
    return {
      subject: 'Two weeks in — how’s it rowing?',
      preheader: 'One question, one favor, and then we leave your inbox in peace.',
      eyebrow: 'Checking in', eyebrowColor: BRAND.terra,
      title: 'How&rsquo;s it&nbsp;rowing?',
      sections,
      text: [
        'You’ve had Kinrows for a couple of weeks — long enough to know if it’s earning its place.',
        '',
        '  • Tell us one true thing: reply with what’s working, or what isn’t. A real person reads it.',
        premium
          ? '  • Squeeze the Concierge: open the morning brief tomorrow and hand it one chore.'
          : '  • Give the Concierge one honest try: the morning brief is free — More → AI Concierge.',
        '  • If Kinrows is helping your family, telling one other household is the biggest thanks there is.',
        '',
        'That’s the whole onboarding series — from here, only the emails your account needs.',
      ].join('\n'),
    };
  },
};

// ── Sweep ────────────────────────────────────────────────────────────────────

function parseSqliteUtc(s) {
  // SQLite CURRENT_TIMESTAMP is 'YYYY-MM-DD HH:MM:SS' in UTC.
  const t = Date.parse(String(s).replace(' ', 'T') + 'Z');
  return Number.isNaN(t) ? Date.parse(s) : t;
}

/**
 * Which stage (if any) is due for a user, given their send log.
 * The first unsent stage in order is the candidate; it becomes due
 * `afterDays` after the PREVIOUS stage was sent (welcome is due at once).
 */
function nextDueStage(sentRows, nowMs = Date.now()) {
  const sentByKey = new Map(sentRows.map(r => [r.email_key, r]));
  for (let i = 0; i < STAGES.length; i++) {
    const stage = STAGES[i];
    if (sentByKey.has(stage.key)) continue;
    if (i === 0) return stage;
    const prev = sentByKey.get(STAGES[i - 1].key);
    if (!prev) return null; // shouldn't happen (stages send in order)
    const dueAt = parseSqliteUtc(prev.sent_at) + stage.afterDays * 24 * 60 * 60 * 1000;
    return nowMs >= dueAt ? stage : null;
  }
  return null; // sequence complete
}

async function buildContext(db, user) {
  let inviteCode = null;
  let tier = null;
  try {
    const groupId = await db.getUserHouseholdId(user.id);
    if (groupId) {
      const group = await db.getGroupById(groupId);
      inviteCode = group?.invite_code || null;
    }
    tier = await subscription.getHouseholdTier(db, user.id);
  } catch { /* context is best-effort; templates degrade gracefully */ }
  return {
    firstName: String(user.name || '').trim().split(/\s+/)[0] || null,
    inviteCode,
    tier,
  };
}

function unsubscribeUrl(token) {
  return `${API_URL}/api/email/unsubscribe?token=${encodeURIComponent(token)}`;
}

/**
 * Send at most one due onboarding stage per eligible user. Safe to call
 * repeatedly — the onboarding_emails log is the guard. `send` is injectable
 * for tests; when it's the real sender, we bail early if email is off.
 */
async function runOnboardingEmailSweep(db, { send = email.sendEmail, nowMs = Date.now() } = {}) {
  const summary = { candidates: 0, sent: 0, errors: 0 };
  if (send === email.sendEmail && !email.isEmailEnabled()) return summary;

  const users = await db.getOnboardingEmailCandidates();
  for (const user of users) {
    try {
      const sentRows = await db.getOnboardingEmailsSent(user.id);
      const stage = nextDueStage(sentRows, nowMs);
      if (!stage) continue;
      summary.candidates++;

      const ctx = await buildContext(db, user);
      const token = await db.ensureUnsubscribeToken(user.id);
      const unsubUrl = unsubscribeUrl(token);
      const t = TEMPLATES[stage.key]({ ...ctx, unsubUrl });
      const html = shell({ ...t, unsubUrl });

      // Record BEFORE sending — the log is the duplicate-send guard.
      const { recorded } = await db.recordOnboardingEmail(user.id, stage.key);
      if (!recorded) continue;

      const r = await send({
        to: user.email,
        subject: t.subject,
        html,
        text: `${t.text}\n\nUnsubscribe: ${unsubUrl}`,
        headers: {
          'List-Unsubscribe': `<${unsubUrl}>`,
          'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
        },
      });
      if (r && r.ok === false) summary.errors++;
      else summary.sent++;
    } catch (err) {
      summary.errors++;
      console.error(`Onboarding email failed for user ${user.id}:`, err.message);
    }
  }
  return summary;
}

module.exports = { STAGES, TEMPLATES, nextDueStage, runOnboardingEmailSweep, unsubscribeUrl };
