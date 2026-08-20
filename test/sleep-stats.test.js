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

// ---------------------------------------------------------------------------
// Night-waking analysis: the "why is he waking at 4am, and why every SECOND
// night" question. The answer has to come out of the same log the parent is
// already keeping — the resettle entries carry the clock times.
// ---------------------------------------------------------------------------

function nap(date, start, end, minutes) {
  return {
    entry_type: 'nap', entry_date: date,
    value: JSON.stringify({
      sleep_start: `${date} ${start}`, sleep_end: `${date} ${end}`, duration_minutes: minutes,
    }),
  };
}

// Fourteen nights. On alternating nights a 4:00am waking lasting 25 minutes,
// and on those same days the last nap runs an hour later — the correlate the
// analysis is supposed to surface.
function alternating4amFortnight() {
  const entries = [];
  for (let i = 0; i < 14; i++) {
    const d = new Date(Date.UTC(2026, 7, 5 + i));
    const date = d.toISOString().slice(0, 10);
    const disturbed = i % 2 === 1;
    if (disturbed) {
      entries.push(night(date, '19:40', '04:00', 500, date, nextDay(date)));
      entries.push(night(date, '04:25', '06:45', 140, nextDay(date), nextDay(date)));
      entries.push(nap(date, '14:30', '16:00', 90));
    } else {
      entries.push(night(date, '19:15', '06:40', 685, date, nextDay(date)));
      entries.push(nap(date, '13:45', '15:00', 75));
    }
    entries.push(nap(date, '09:15', '10:30', 75));
  }
  return entries;
}

test('wakings: the resettle gap is read back as a timed 4am waking', () => {
  const a = sleepStats.analyzeWakings(alternating4amFortnight(), { today: '2026-08-18' });
  assert.equal(a.nights_analyzed, 14);
  assert.ok(a.cluster, 'a cluster is found');
  assert.equal(a.cluster.typical_time, '4:00am');
  assert.equal(a.cluster.nights_affected, 7, 'seven of the fourteen nights');
  assert.equal(a.cluster.median_awake_minutes, 25, 'awake 25 minutes before resettling');
});

test('wakings: an every-second-night rhythm is named as alternating', () => {
  const a = sleepStats.analyzeWakings(alternating4amFortnight(), { today: '2026-08-18' });
  assert.equal(a.rhythm.pattern, 'alternating');
  assert.equal(a.rhythm.confidence, 'high');
  assert.equal(a.rhythm.alternating_pairs, a.rhythm.consecutive_pairs);
});

test('wakings: the daytime difference behind the bad nights is surfaced', () => {
  const a = sleepStats.analyzeWakings(alternating4amFortnight(), { today: '2026-08-18' });
  const napEnd = a.differences.find(d => d.key === 'last_nap_end');
  assert.ok(napEnd, 'the late last nap is spotted');
  assert.equal(napEnd.delta_minutes, 60, 'an hour later on the disturbed nights');
  assert.equal(napEnd.direction, 'later');
  // Ordered by size so the biggest lever is the one a parent reads first.
  assert.equal(a.differences[0].key, 'last_nap_end');
});

test('wakings: a clean sleeper gets no cluster and no invented pattern', () => {
  const entries = [];
  for (let i = 0; i < 10; i++) {
    const date = new Date(Date.UTC(2026, 7, 5 + i)).toISOString().slice(0, 10);
    entries.push(night(date, '19:15', '06:40', 685, date, nextDay(date)));
  }
  const a = sleepStats.analyzeWakings(entries, { today: '2026-08-14' });
  assert.equal(a.cluster, null, 'no wakings means no cluster');
  assert.equal(a.rhythm, null);
  assert.deepEqual(a.differences, []);
  assert.equal(a.total_wakings, 0);
});

test('wakings: a logging gap breaks the chain rather than being guessed at', () => {
  // Two separated runs of nights: adjacency across the gap must not be assumed,
  // because "every second night" is a claim about consecutive nights only.
  const entries = [];
  for (const i of [0, 1, 2, 3, 4, 5, 20, 21]) {
    const date = new Date(Date.UTC(2026, 7, 1 + i)).toISOString().slice(0, 10);
    const disturbed = i % 2 === 1;
    if (disturbed) {
      entries.push(night(date, '19:30', '04:00', 510, date, nextDay(date)));
      entries.push(night(date, '04:20', '06:30', 130, nextDay(date), nextDay(date)));
    } else {
      entries.push(night(date, '19:30', '06:30', 660, date, nextDay(date)));
    }
  }
  const a = sleepStats.analyzeWakings(entries, { today: '2026-08-25', windowDays: 30 });
  assert.equal(a.nights_analyzed, 8);
  // 5 consecutive pairs in the first run + 1 in the second; the 15-day gap is
  // not a pair.
  assert.equal(a.rhythm.consecutive_pairs, 6);
});

// ---------------------------------------------------------------------------
// Recommendations
// ---------------------------------------------------------------------------

test('recommendations: the 4am cluster is treated as an early-morning waking', () => {
  const entries = alternating4amFortnight();
  const stats = sleepStats.compute(entries, { birthdate: '2025-10-02', today: '2026-08-18' });
  const analysis = sleepStats.analyzeWakings(entries, { birthdate: '2025-10-02', today: '2026-08-18' });
  const rec = sleepStats.recommend(stats, analysis, { birthdate: '2025-10-02' });

  const keys = rec.items.map(i => i.key);
  assert.ok(keys.includes('early_morning_waking'), '4am is its own problem, not a generic night waking');
  assert.ok(keys.includes('alternating_pattern'), 'the every-second-night pattern is addressed');

  // Every item must show its working and name its evidence.
  for (const item of rec.items) {
    assert.ok(item.because && item.because.length > 10, `${item.key} states what it is reacting to`);
    assert.ok(item.source, `${item.key} names a source`);
    assert.ok(item.strength, `${item.key} rates its evidence`);
    assert.ok(Array.isArray(item.what_to_try) && item.what_to_try.length, `${item.key} says what to do`);
  }
  // The alternating item leads: it explains the thing the parent noticed.
  assert.equal(rec.items[0].key, 'alternating_pattern');
});

test('recommendations: too little data says so instead of inventing advice', () => {
  const entries = [night('2026-08-01', '19:15', '06:30', 675, '2026-08-01', '2026-08-02')];
  const stats = sleepStats.compute(entries, { today: '2026-08-02' });
  const analysis = sleepStats.analyzeWakings(entries, { today: '2026-08-02' });
  const rec = sleepStats.recommend(stats, analysis, {});
  assert.deepEqual(rec.items, []);
  assert.match(rec.note, /more logged nights/i);
});

test('recommendations: under 4 months, no training method is offered', () => {
  const entries = alternating4amFortnight();
  const birthdate = '2026-06-20'; // ~8 weeks on 2026-08-18
  const stats = sleepStats.compute(entries, { birthdate, today: '2026-08-18' });
  const analysis = sleepStats.analyzeWakings(entries, { birthdate, today: '2026-08-18' });
  const rec = sleepStats.recommend(stats, analysis, { birthdate });
  const keys = rec.items.map(i => i.key);
  assert.ok(keys.includes('too_young'), 'the age gate fires');
  assert.ok(!keys.includes('method'), 'no formal method before ~4 months');
});

// ---------------------------------------------------------------------------
// Next-nap window: Home counts awake from the last finished sleep, nap or
// night. A fragile Date parse used to drop any stamp that wasn't exactly
// "yyyy-MM-dd HH:mm", so a morning nap left the bar stuck on last night.
// ---------------------------------------------------------------------------

test('nextSleepWindow: a morning nap moves the wake, not last night', () => {
  const birthdate = '2025-09-20'; // ~10 months → 3–4 hour band
  const night = {
    entry_type: 'night_sleep', entry_date: '2026-08-19',
    value: JSON.stringify({
      sleep_start: '2026-08-19 19:35', sleep_end: '2026-08-20 06:27', duration_minutes: 652,
    }),
  };
  const nap = (end) => ({
    entry_type: 'nap', entry_date: '2026-08-20',
    value: JSON.stringify({
      sleep_start: '2026-08-20 08:24', sleep_end: end, duration_minutes: 50,
    }),
  });

  const fromNight = sleepStats.nextSleepWindow([night], { birthdate });
  assert.equal(fromNight.last_wake_at, '2026-08-20 06:27');
  assert.equal(fromNight.last_sleep_type, 'night_sleep');

  const fromNap = sleepStats.nextSleepWindow([night, nap('2026-08-20 09:14')], { birthdate });
  assert.equal(fromNap.last_wake_at, '2026-08-20 09:14', 'awake counts from the nap');
  assert.equal(fromNap.last_sleep_type, 'nap');
  assert.equal(fromNap.due_from, '2026-08-20 12:14');

  // Shapes the old `new Date(stamp.replace(' ','T')+':00')` treated as invalid.
  for (const end of ['2026-08-20 09:14:00', '2026-08-20T09:14:00', '2026-08-20 9:14 AM']) {
    const w = sleepStats.nextSleepWindow([night, nap(end)], { birthdate });
    assert.equal(w.last_wake_at, '2026-08-20 09:14', `parsed ${end}`);
    assert.equal(w.last_sleep_type, 'nap');
  }
});
