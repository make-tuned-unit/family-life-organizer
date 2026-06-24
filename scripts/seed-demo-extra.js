#!/usr/bin/env node
/**
 * Extends the demo household with a second member (Theo), a DM thread, a care
 * team (contacts), and a coverage request — so the Chat and Care Cascade screens
 * render populated for screenshots. Run after seed-demo.js, server on :3456.
 */

const BASE = process.env.DEMO_BASE || 'http://localhost:3456';
const INVITE = process.env.HAYES_INVITE || 'KCU3EQTILA';

function jar() {
  let cookie = '';
  return async function api(path, method = 'GET', body) {
    const res = await fetch(BASE + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    const text = await res.text();
    let json; try { json = JSON.parse(text); } catch { json = text; }
    if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${text}`);
    return json;
  };
}

const iso = (off) => { const d = new Date(); d.setDate(d.getDate() + off); return d.toISOString().slice(0, 10); };

async function main() {
  const maya = jar();
  const theo = jar();

  // Log in maya
  const mayaLogin = await maya('/api/auth/login', 'POST', { username: 'maya', password: 'demo1234' });
  const mayaId = mayaLogin.user?.id;

  // Register theo into the Hayes household (or log in if already there)
  let theoUser;
  try {
    const r = await theo('/api/auth/register', 'POST', { username: 'theo', password: 'demo1234', name: 'Theo Hayes', invite_code: INVITE });
    theoUser = r.user;
    console.log('Registered Theo, joined Hayes family');
  } catch (e) {
    if (String(e).includes('409')) {
      const r = await theo('/api/auth/login', 'POST', { username: 'theo', password: 'demo1234' });
      theoUser = r.user;
      console.log('Theo already existed; logged in');
    } else throw e;
  }
  const theoId = theoUser?.id;

  // --- DM thread between Maya and Theo ---
  const convo = [
    [theo, mayaId, "Heading out — can you grab Ella from soccer at 5:30?"],
    [maya, theoId, "Yep got it. Want me to start dinner too?"],
    [theo, mayaId, "That'd be amazing 🙏 tacos?"],
    [maya, theoId, "Taco night it is 🌮"],
    [theo, mayaId, "You're the best. Home by 6."],
  ];
  for (const [who, to, text] of convo) {
    await who('/api/messages', 'POST', { recipient_id: to, text });
  }
  console.log('Seeded', convo.length, 'DMs (Maya ↔ Theo)');

  // --- Care team (contacts) ---
  const contacts = [
    { name: 'Grandma Sue', relationship: 'mom', avatar_initial: 'S', phone: '555-0148' },
    { name: 'Uncle Ben', relationship: 'brother', avatar_initial: 'B', phone: '555-0172' },
    { name: 'Priya (next door)', relationship: 'neighbor', avatar_initial: 'P', phone: '555-0193' },
    { name: 'Aunt Mei', relationship: 'aunt', avatar_initial: 'M', phone: '555-0110' },
  ];
  const contactIds = [];
  for (const c of contacts) {
    const r = await maya('/api/contacts', 'POST', c);
    contactIds.push(r.id);
  }
  console.log('Seeded', contacts.length, 'care-team contacts');

  // --- A coverage request (asked the circle) ---
  await maya('/api/coverage', 'POST', {
    reason: 'School pickup',
    note: "Stuck in a meeting until 4 — anyone free for the 3:00 pickup?",
    windows: [{ window_date: iso(1), start_time: '15:00', end_time: '17:00' }],
    contact_ids: contactIds.slice(0, 3),
  });
  console.log('Seeded coverage request');

  console.log(`\nExtra seed complete. Theo id=${theoId} (use for chat DM).`);
  // Emit theo id for the harness
  process.stdout.write(`THEO_ID=${theoId}\n`);
}

main().catch((e) => { console.error('EXTRA SEED FAILED:', e); process.exit(1); });
