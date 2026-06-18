// Concierge context builder.
// Composes existing FamilyDB reads into one structured, household-scoped
// snapshot of "what needs attention right now". Pure data — no AI here.

const HORIZON_DAYS = 7;        // calendar / events look-ahead
const PANTRY_DAYS = 3;         // flag pantry expiring within N days
const EVENT_DAYS = 14;         // flag birthdays/anniversaries within N days
const BUDGET_NEAR = 0.8;       // flag categories >= 80% of limit

function todayISO() {
  return new Date().toLocaleDateString('en-CA'); // YYYY-MM-DD in server TZ
}

function currentMonth() {
  return todayISO().slice(0, 7); // YYYY-MM
}

// Whole days from today to an absolute YYYY-MM-DD (negative = past).
function daysUntil(dateStr) {
  if (!dateStr) return null;
  const today = new Date(todayISO() + 'T00:00:00');
  const target = new Date(String(dateStr).slice(0, 10) + 'T00:00:00');
  if (isNaN(target)) return null;
  return Math.round((target - today) / 86400000);
}

// Days until the next annual recurrence of a date (for birthdays/anniversaries).
function daysUntilAnnual(dateStr) {
  if (!dateStr) return null;
  const src = new Date(String(dateStr).slice(0, 10) + 'T00:00:00');
  if (isNaN(src)) return null;
  const today = new Date(todayISO() + 'T00:00:00');
  let next = new Date(today.getFullYear(), src.getMonth(), src.getDate());
  if (next < today) next = new Date(today.getFullYear() + 1, src.getMonth(), src.getDate());
  return Math.round((next - today) / 86400000);
}

// Resolve a promise, falling back (and logging) on error so one bad
// query never blanks the whole brief.
async function safe(promise, fallback, label) {
  try {
    return await promise;
  } catch (err) {
    console.error(`[concierge] ${label} failed:`, err.message);
    return fallback;
  }
}

async function buildSnapshot(db, userId) {
  const today = todayISO();
  const month = currentMonth();

  const [tasks, appts, decisions, pantry, events, coverage, budget, trips, itineraries] = await Promise.all([
    safe(db.getTasks({ status: 'active' }, userId), [], 'tasks'),
    safe(db.getAppointments({}, userId), [], 'appointments'),
    safe(db.getDecisions({ status: 'active' }, userId), [], 'decisions'),
    safe(db.getPantry(), [], 'pantry'),
    safe(db.getSpecialEvents(), [], 'events'),
    safe(db.getIncomingCoverageRequests(userId), [], 'coverage'),
    safe(db.getBudgetSummary(month), [], 'budget'),
    safe(db.getTrips({ status: 'active' }), [], 'trips'),
    safe(db.getItineraries(userId), [], 'itineraries'),
  ]);

  const overdueTasks = tasks
    .filter(t => t.due_date && daysUntil(t.due_date) < 0)
    .map(t => ({ id: t.id, title: t.title, due_date: t.due_date, assigned_to: t.assigned_to }));

  const upcomingAppointments = appts
    .map(a => ({ ...a, _d: daysUntil(a.appointment_date) }))
    .filter(a => a._d !== null && a._d >= 0 && a._d <= HORIZON_DAYS)
    .sort((a, b) => a._d - b._d)
    .map(a => ({ id: a.id, title: a.title, date: a.appointment_date, time: a.appointment_time, location: a.location }));

  const openDecisions = decisions
    .filter(d => d.status === 'active')
    .map(d => ({ id: d.id, title: d.title, creator_name: d.creator_name }));

  const expiringPantry = pantry
    .map(p => ({ ...p, _d: daysUntil(p.expiry_date) }))
    .filter(p => p._d !== null && p._d <= PANTRY_DAYS)
    .sort((a, b) => a._d - b._d)
    .map(p => ({ id: p.id, item: p.item, expiry_date: p.expiry_date, daysLeft: p._d }));

  const upcomingEvents = events
    .map(e => ({ ...e, _d: e.is_recurring ? daysUntilAnnual(e.date) : daysUntil(e.date) }))
    .filter(e => e._d !== null && e._d >= 0 && e._d <= EVENT_DAYS)
    .sort((a, b) => a._d - b._d)
    .map(e => ({ title: e.title, date: e.date, daysUntil: e._d, type: e.event_type }));

  const pendingCoverage = coverage
    .filter(c => c.recipient_status === 'pending' || c.recipient_status === 'viewed')
    .map(c => ({ id: c.id, reason: c.reason, requester_name: c.requester_name, recipient_id: c.recipient_id }));

  const budgetAlerts = budget
    .filter(b => b.monthly_limit > 0 && b.spent / b.monthly_limit >= BUDGET_NEAR)
    .map(b => ({
      category: b.category,
      spent: b.spent,
      monthly_limit: b.monthly_limit,
      pct: Math.round((b.spent / b.monthly_limit) * 100),
      over: b.spent > b.monthly_limit,
    }))
    .sort((a, b) => b.pct - a.pct);

  const activeTrips = trips
    .map(t => ({ id: t.id, traveler: t.traveler, destination: t.destination, eta_minutes: t.eta_minutes }));

  // In-progress or upcoming itineraries (not yet ended, not completed/cancelled).
  const upcomingItineraries = itineraries
    .filter(i => i.status !== 'completed' && i.status !== 'cancelled')
    .map(i => ({ ...i, _end: daysUntil(i.end_date), _start: daysUntil(i.start_date) }))
    .filter(i => i._end === null || i._end >= 0)
    .sort((a, b) => (a._start ?? 0) - (b._start ?? 0))
    .map(i => ({
      id: i.id, title: i.title, traveler: i.traveler_name,
      start_date: i.start_date, end_date: i.end_date, status: i.status,
      daysUntilStart: i._start,
    }));

  return {
    date: today,
    counts: {
      overdueTasks: overdueTasks.length,
      upcomingAppointments: upcomingAppointments.length,
      openDecisions: openDecisions.length,
      expiringPantry: expiringPantry.length,
      upcomingEvents: upcomingEvents.length,
      pendingCoverage: pendingCoverage.length,
      budgetAlerts: budgetAlerts.length,
      activeTrips: activeTrips.length,
      upcomingItineraries: upcomingItineraries.length,
    },
    overdueTasks,
    upcomingAppointments,
    openDecisions,
    expiringPantry,
    upcomingEvents,
    pendingCoverage,
    budgetAlerts,
    activeTrips,
    upcomingItineraries,
  };
}

module.exports = { buildSnapshot, daysUntil, daysUntilAnnual, todayISO };
