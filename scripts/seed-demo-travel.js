#!/usr/bin/env node
/**
 * Seeds a step rivalry, an active trip, and an itinerary into the demo household
 * so the Rivalries and Travel screens render populated for screenshots.
 * Run after seed-demo.js + seed-demo-extra.js, server on :3456.
 */

const BASE = process.env.DEMO_BASE || 'http://localhost:3456';

async function makeJar() {
  let cookie = '';
  const api = async (path, method = 'GET', body) => {
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
  return api;
}

const iso = (off) => { const d = new Date(); d.setDate(d.getDate() + off); return d.toISOString().slice(0, 10); };

async function main() {
  const api = await makeJar();
  await api('/api/auth/login', 'POST', { username: 'maya', password: 'demo1234' });

  // --- Step rivalry: Maya vs Theo, this week ---
  const r = await api('/api/rivalries', 'POST', {
    title: 'Step Showdown',
    challenge_type: 'steps',
    initiator_name: 'Maya Hayes',
    opponent_name: 'Theo Hayes',
    start_date: iso(-5),
    end_date: iso(2),
    status: 'active',
  });
  const rid = r.id;
  const days = [
    ['Maya Hayes', [9120, 11050, 8430, 12760, 10240]],
    ['Theo Hayes', [8740, 9980, 12010, 7650, 11320]],
  ];
  for (const [name, vals] of days) {
    for (let i = 0; i < vals.length; i++) {
      await api(`/api/rivalries/${rid}/entries`, 'POST', {
        member_name: name, value: vals[i], activity_date: iso(-5 + i), note: 'Synced from Apple Health', is_verified: true,
      });
    }
  }
  console.log('Seeded rivalry "Step Showdown" with entries');

  // --- Active trip (shows live "on the way" card) ---
  await api('/api/trips', 'POST', {
    traveler: 'Theo',
    origin: 'Halifax, NS',
    destination: "Grandma Sue's",
    purpose: 'Sunday dinner',
    status: 'active',
    eta_minutes: 18,
    destination_lat: 44.6488, destination_lng: -63.5752,
  });
  console.log('Seeded active trip (Theo → Grandma Sue\'s)');

  // --- Itinerary for the Itineraries tab ---
  const it = await api('/api/itineraries', 'POST', {
    title: 'Cape Breton long weekend',
    start_date: iso(20),
    end_date: iso(24),
    travelers: 'Maya, Theo, Ella, Jude',
    notes: 'Cabot Trail + the beach',
    status: 'upcoming',
  });
  try {
    await api(`/api/itineraries/${it.id}/stays`, 'POST', {
      location_name: 'Keltic Lodge', host_name: 'Ingonish', check_in: iso(20), check_out: iso(22),
    });
    await api(`/api/itineraries/${it.id}/stays`, 'POST', {
      location_name: "Aunt Mei's cottage", host_name: 'Baddeck', check_in: iso(22), check_out: iso(24),
    });
  } catch (e) { console.warn('(stay seed skipped:', String(e).slice(0, 80), ')'); }
  console.log('Seeded itinerary "Cape Breton long weekend"');

  console.log('\nTravel/rivalry seed complete.');
}

main().catch((e) => { console.error('TRAVEL SEED FAILED:', e); process.exit(1); });
