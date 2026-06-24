#!/usr/bin/env node
/**
 * Seeds a fictional demo household ("The Hayes Family") into the local backend
 * via the public API, for capturing marketing screenshots. No real family data.
 *
 * Usage: node scripts/seed-demo.js   (server must be running on localhost:3456)
 */

const BASE = process.env.DEMO_BASE || 'http://localhost:3456';
const USER = { username: 'maya', password: 'demo1234', name: 'Maya Hayes', household_name: 'The Hayes Family' };

let cookie = '';

async function api(path, method = 'GET', body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const setCookie = res.headers.get('set-cookie');
  if (setCookie) cookie = setCookie.split(';')[0];
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${text}`);
  return json;
}

const iso = (offsetDays) => {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.toISOString().slice(0, 10);
};

async function main() {
  // Register (or log in if already there)
  try {
    await api('/api/auth/register', 'POST', USER);
    console.log('Registered', USER.username);
  } catch (e) {
    if (String(e).includes('409')) {
      await api('/api/auth/login', 'POST', { username: USER.username, password: USER.password });
      console.log('Logged in (already existed)');
    } else throw e;
  }

  // --- Tasks (shows the new grouped Tasks view; "Packing" is a category) ---
  const tasks = [
    { title: 'Pack ball gloves', category: 'Packing', priority: 'medium' },
    { title: 'Pack the pack-and-play', category: 'Packing', priority: 'medium' },
    { title: 'Pack baby bag for the weekend', category: 'Packing', priority: 'high' },
    { title: 'Renew library books', category: 'general', priority: 'medium', due_date: iso(0) },
    { title: 'Book swim lessons', category: 'general', priority: 'low' },
    { title: 'Call the dentist back', category: 'general', priority: 'high', due_date: iso(-1) },
  ];
  for (const data of tasks) await api('/api/add', 'POST', { type: 'task', data });
  console.log('Seeded', tasks.length, 'tasks');

  // --- Appointments (hero event + today + week) ---
  const appts = [
    { title: 'Soccer practice', appointment_date: iso(0), appointment_time: '16:30', location: 'Riverside Park', person_tags: 'Ella', category: 'sports' },
    { title: 'Family movie night', appointment_date: iso(0), appointment_time: '19:30', location: 'Home', person_tags: 'Maya,Theo', category: 'family' },
    { title: 'Dentist — Ella', appointment_date: iso(2), appointment_time: '09:15', location: 'Bright Smiles Dental', person_tags: 'Ella', category: 'health' },
    { title: 'Parent-teacher night', appointment_date: iso(4), appointment_time: '18:00', location: 'Maple Elementary', person_tags: 'Theo', category: 'school' },
    { title: 'Grandma visits', appointment_date: iso(6), appointment_time: '12:00', location: 'Home', person_tags: 'Maya', category: 'family' },
  ];
  for (const a of appts) await api('/api/appointments', 'POST', a);
  console.log('Seeded', appts.length, 'appointments');

  // --- Lists: a pinned grocery "Weekend list" with items ---
  const list = await api('/api/lists', 'POST', { name: 'Weekend list', icon: 'cart.fill', list_type: 'grocery' });
  await api(`/api/lists/${list.id}`, 'PUT', { pinned: 1 });
  const items = ['Sunscreen & bug spray', 'Strawberries', 'Burger buns', 'Oat milk', 'Paper towels', 'Goldfish crackers', 'Ground beef'];
  for (const title of items) await api(`/api/lists/${list.id}/items`, 'POST', { title });
  console.log('Seeded list "Weekend list" with', items.length, 'items');

  // A second simple list
  const packing = await api('/api/lists', 'POST', { name: 'Camping trip', icon: 'tent.fill' });
  for (const title of ['Tent + stakes', 'Sleeping bags', 'Cooler', 'Marshmallows', 'First-aid kit']) {
    await api(`/api/lists/${packing.id}/items`, 'POST', { title });
  }
  console.log('Seeded list "Camping trip"');

  // --- Decision poll ---
  await api('/api/decisions', 'POST', {
    title: 'Pizza or tacos for Friday?',
    decision_type: 'poll',
    poll_options: JSON.stringify(['Pizza night', 'Taco bar', 'Breakfast for dinner']),
  });
  console.log('Seeded decision poll');

  console.log('\nDemo seed complete. Login: maya / demo1234');
}

main().catch((e) => { console.error('SEED FAILED:', e); process.exit(1); });
