// Pure age helpers for sleep training — calendar months vs day-based phases.
const { test } = require('node:test');
const assert = require('node:assert');
const sleep = require('../services/sleepTraining');

test('sleepTraining: ageInMonths is calendar months, not mean-month floor', () => {
  // Exact 6-month anniversary — the screenshot bug: floor(days/30.4375) was 5.
  assert.equal(sleep.ageInMonths('2026-03-02', '2026-09-02'), 6);
  assert.equal(sleep.guidanceForBirthdate('2026-03-02', '2026-09-02').age_months, 6);

  // Day before the anniversary is still 5 calendar months.
  assert.equal(sleep.ageInMonths('2026-03-02', '2026-09-01'), 5);

  // Jan→Jul edge where mean-month arithmetic undercounts on the anniversary.
  assert.equal(sleep.ageInMonths('2026-01-02', '2026-07-02'), 6);
  assert.ok(sleep.ageInDays('2026-01-02', '2026-07-02') < 183);
  assert.equal(Math.floor(sleep.ageInDays('2026-01-02', '2026-07-02') / 30.4375), 5,
    'documents the old mean-month undercount this fix replaces');
});

test('sleepTraining: phase bands still use age_days, not months', () => {
  // 184 days → consolidate (foundations ends at day 182); months still calendar.
  const g = sleep.guidanceForBirthdate('2026-03-02', '2026-09-02');
  assert.equal(g.age_months, 6);
  assert.equal(g.age_days, 184);
  assert.equal(g.current_phase.key, 'consolidate');
  assert.equal(g.ready_for_training, true);

  // Still inside foundations by days, but calendar months already 5.
  const mid = sleep.guidanceForBirthdate('2026-03-02', '2026-08-20');
  assert.equal(mid.current_phase.key, 'foundations');
  assert.equal(mid.age_months, 5);
});
