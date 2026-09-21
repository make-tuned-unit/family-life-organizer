const { expandRecurrence } = require('./calendarRecurrence');
async function getRoutineOccurrences(db, routineId, userId, todayDate = new Date().toLocaleDateString('en-CA')) {
  const offset = n => { const d = new Date(todayDate + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toLocaleDateString('en-CA'); };
    const routine = await db.getRoutineById(routineId);
    let cfg = {};
    try { cfg = JSON.parse(routine.config || '{}'); } catch {}
    const keyword = (cfg.calendar_keyword || '').trim();
    if (!keyword) return { keyword: null, occurrences: [], scheduled: 0, attended: 0 };

    const groupId = await db.getUserHouseholdId(userId);
    const today = todayDate;
    const windowStart = offset(-90);  // look back ~3 months
    const windowEnd = offset(30);     // and ~1 month ahead
    const base = await db.getAppointmentsMatching(groupId, keyword, null, windowEnd);

    // Expand each matching event's occurrences within the window.
    const rangeStart = new Date(windowStart + 'T00:00:00');
    const rangeEnd = new Date(windowEnd + 'T00:00:00');
    const dates = new Set();
    for (const appt of base) {
      const origin = new Date(appt.appointment_date + 'T00:00:00');
      if (appt.appointment_date >= windowStart && appt.appointment_date <= windowEnd) {
        dates.add(appt.appointment_date);
      }
      if (appt.recurrence_rule) {
        const endDate = appt.recurrence_end ? new Date(appt.recurrence_end + 'T00:00:00') : null;
        for (const d of expandRecurrence(appt.recurrence_rule, origin, rangeStart, rangeEnd, endDate)) {
          dates.add(d.toLocaleDateString('en-CA'));
        }
      }
    }

    // Which dates already have a logged session.
    const entries = await db.getRoutineEntries(routineId, {});
    const confirmed = new Set(entries
      .filter(e => e.entry_type === 'session' || e.entry_type === 'attended')
      .map(e => e.entry_date));

    const occurrences = [...dates].sort().map(d => ({
      date: d, confirmed: confirmed.has(d), past: d < today, today: d === today,
    }));
    const pending = occurrences.filter(o => o.past && !o.confirmed);
    return {
      keyword,
      occurrences,
      scheduled: occurrences.length,
      attended: occurrences.filter(o => o.confirmed).length,
      pending,
    };
}
module.exports = { getRoutineOccurrences };
