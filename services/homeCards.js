const { expandRecurrence } = require('./calendarRecurrence');
const OPTIONS = [
  { id: 'budget', title: 'Budget', icon: 'creditcard' },
  { id: 'trips', title: 'Trips', icon: 'airplane' },
  { id: 'calendar', title: 'Calendar', icon: 'calendar' },
  { id: 'lists', title: 'Lists', icon: 'list.bullet.rectangle' },
  { id: 'tasks', title: 'Tasks', icon: 'checkmark.circle' },
  { id: 'routines', title: 'Routines', icon: 'repeat' },
  { id: 'pantry', title: 'Pantry', icon: 'cabinet' },
  { id: 'people', title: 'People', icon: 'person.2' },
];
const query = (db, sql, params = []) => new Promise((resolve, reject) => db.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows)));
async function getPins(db, userId) {
  const rows = await query(db, 'SELECT pins FROM home_preferences WHERE user_id = ?', [userId]);
  try { return JSON.parse(rows[0]?.pins || '[]').filter(id => OPTIONS.some(o => o.id === id)); } catch { return []; }
}
async function setPins(db, userId, pins) {
  if (!Array.isArray(pins) || pins.length > OPTIONS.length || new Set(pins).size !== pins.length || pins.some(id => !OPTIONS.some(o => o.id === id))) throw new Error('Choose unique supported Home cards');
  await new Promise((resolve, reject) => db.db.run('INSERT INTO home_preferences (user_id, pins) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET pins = excluded.pins', [userId, JSON.stringify(pins)], err => err ? reject(err) : resolve()));
  return pins;
}
async function buildCards(db, userId, groupId, today) {
  const pins = await getPins(db, userId);
  const cards = [];
  for (const id of pins) {
    const option = OPTIONS.find(o => o.id === id);
    let headline = '', detail = '', status = 'neutral';
    if (id === 'budget') {
      const month = today.slice(0,7);
      const budget = await db.getBudgetSummary(month, groupId);
      const rows = await query(db, "SELECT COALESCE(SUM(amount),0) AS spent FROM receipts WHERE group_id = ? AND substr(date,1,7) = ? AND itinerary_id IS NULL", [groupId, month]);
      const spent = Number(rows[0].spent), limit = budget.reduce((n, b) => n + Number(b.monthly_limit || 0), 0);
      const [year, m, day] = today.split('-').map(Number), days = new Date(year, m, 0).getDate();
      const money = n => n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      headline = limit <= 0 ? 'Set a monthly budget' : spent > limit ? 'Over monthly budget' : spent > limit * day / days ? 'Above this month’s pace' : 'On track this month';
      detail = `$${money(spent)} spent${limit > 0 ? ` of $${money(limit)} · $${money(Math.max(0, limit - spent))} left` : ' this month'}`;
      status = limit > 0 && spent > limit * day / days ? 'attention' : 'neutral';
    } else if (id === 'trips') {
      const trips = (await db.getItineraries(userId)).filter(t => t.end_date >= today && !['completed','cancelled'].includes(t.status)).sort((a,b) => a.start_date.localeCompare(b.start_date));
      headline = trips.length ? `${trips.length} upcoming or current ${trips.length === 1 ? 'trip' : 'trips'}` : 'No upcoming trips';
      detail = trips.slice(0,3).map(t => `${t.title} · ${t.start_date}${t.group_id && t.group_id !== groupId ? ' · Clan' : ''}`).join('\n') || 'Your trips and itineraries shared with your clans appear here.';
    } else if (id === 'calendar') {
      const origins = await db.getAppointments({}, userId);
      const from = new Date(today + 'T12:00:00'), until = new Date(from); until.setDate(until.getDate() + 90);
      const rows = origins.filter(e => e.appointment_date >= today);
      for (const event of origins.filter(e => e.recurrence_rule && e.appointment_date < today)) {
        const dates = expandRecurrence(event.recurrence_rule, new Date(event.appointment_date + 'T12:00:00'), from, until, event.recurrence_end ? new Date(event.recurrence_end + 'T12:00:00') : null);
        if (dates[0]) rows.push({ ...event, appointment_date: dates[0].toLocaleDateString('en-CA') });
      }
      rows.sort((a,b) => (a.appointment_date + (a.appointment_time || '')).localeCompare(b.appointment_date + (b.appointment_time || '')));
      headline = rows[0]?.title || 'Calendar'; detail = rows[0] ? `${rows[0].appointment_date} · ${rows[0].appointment_time || 'All day'}` : 'Open your calendar to plan what’s next.';
    } else if (id === 'lists') {
      const rows = await db.getLists(userId);
      headline = `${rows.length} lists`; detail = rows.slice(0,3).map(l => `${l.name} · ${l.active_count || 0} remaining`).join('\n');
    } else if (id === 'tasks') {
      const rows = await db.getTasks({ status: 'active' }, userId);
      headline = `${rows.length} open tasks`; detail = rows.slice(0,3).map(t => t.title).join('\n');
    } else if (id === 'routines') {
      const rows = (await db.getRoutines(groupId, userId)).filter(r => r.active !== 0);
      headline = `${rows.length} active routines`; detail = rows.slice(0,3).map(r => r.name).join('\n');
    } else if (id === 'pantry') {
      const rows = await query(db, 'SELECT COUNT(*) AS count FROM pantry WHERE group_id = ?', [groupId]);
      headline = `${rows[0].count} pantry items`; detail = 'See what you have before your next shop.';
    } else if (id === 'people') {
      const rows = await query(db, 'SELECT COUNT(*) AS count FROM gift_people WHERE group_id = ?', [groupId]);
      headline = `${rows[0].count} people`; detail = 'Birthdays, milestones and the people you care about.';
    }
    cards.push({ ...option, headline, detail, status });
  }
  return { pins, cards, options: OPTIONS };
}
module.exports = { OPTIONS, getPins, setPins, buildCards };
