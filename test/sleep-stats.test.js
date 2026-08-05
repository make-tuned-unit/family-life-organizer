// Bedtime/wake averages must reduce each night to its real marks first: the
// bedtime is the FIRST night_sleep start of the night and the wake is the LAST
// end — overnight resettles logged as extra night_sleep entries are neither.
// (Regression: averaging every start dragged a 7:15pm bedtime to ~10:30pm and
// fired the wind-down reminder at 10pm, hours after the child was asleep.)

const { test } = require('node:test');
const assert = require('node:assert');

const sleepStats = require('../services/sleepStats');

// A night_sleep row the way the API stores it: JSON value with timestamps.
function night(date, start, end, minutes, startDate = date, endDate = null) {
  const endD = endDate || (end < start ? nextDay(date) : date);
  return {
    entry_type: 'night_sleep', entry_date: date,
    value: JSON.stringify({
      sleep_start: `${startDate} ${start}`,
      sleep_end: `${endD} ${end}`,
      duration_minutes: minutes,
    }),
  };
}
function nextDay(date) {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

// Three nights: 19:15 bedtime, a ~23:00 resettle and a ~01:30 resettle each
// night, morning wake 06:30. The old flat average called bedtime ~10:30pm.
function threeNightsWithResettles() {
  const entries = [];
  for (const date of ['2026-08-01', '2026-08-02', '2026-08-03']) {
    entries.push(night(date, '19:15', '22:40', 205));
    entries.push(night(date, '23:00', '01:00', 120, date, nextDay(date)));
    entries.push(night(date, '01:30', '06:30', 300, nextDay(date), nextDay(date)));
  }
  return entries;
}

test('bedtime average uses the first sleep of each night, not every resettle', () => {
  const stats = sleepStats.compute(threeNightsWithResettles(), { today: '2026-08-04' });
  assert.equal(stats.bedtime.average, '7:15pm', 'bedtime is the actual put-down time');
  assert.equal(stats.wake_time.average, '6:30am', 'wake is the morning wake, not a mid-night one');
});

test('bedtimePrep works back from the true bedtime', () => {
  const stats = sleepStats.compute(threeNightsWithResettles(), { today: '2026-08-04' });
  const prep = sleepStats.bedtimePrep(stats);
  assert.ok(prep, 'three nights is enough to speak');
  assert.equal(prep.start_time, '18:45', 'wind-down = bedtime minus 30');
  assert.equal(prep.bedtime, '7:15pm');
});

test('an after-midnight bedtime still averages correctly (noon-anchored ordering)', () => {
  // Older-kid pattern: bedtime just past midnight, no resettles.
  const entries = ['2026-08-01', '2026-08-02', '2026-08-03'].map(date =>
    night(date, '00:20', '07:20', 420, nextDay(date), nextDay(date)));
  const stats = sleepStats.compute(entries, { today: '2026-08-04' });
  assert.equal(stats.bedtime.average, '12:20am');
  assert.equal(stats.wake_time.average, '7:20am');
});
