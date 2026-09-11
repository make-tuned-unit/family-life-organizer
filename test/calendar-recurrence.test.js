const { test } = require('node:test');
const assert = require('node:assert/strict');
const { expandRecurrence } = require('../services/calendarRecurrence');
const d = s => new Date(s + 'T12:00:00');
const date = d => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
const expand = (rule, start, from, to, end) => expandRecurrence(rule, d(start), d(from), d(to), end ? d(end) : null).map(date);
test('monthly recurrence clamps without drifting from the original day', () => {
  assert.deepEqual(expand('monthly', '2026-01-31', '2026-02-01', '2026-05-01'), ['2026-02-28', '2026-03-31', '2026-04-30']);
});
test('daily and weekly series remain visible years after creation', () => {
  assert.equal(expand('daily', '2020-01-01', '2026-09-01', '2026-09-08').length, 7);
  assert.deepEqual(expand('weekly', '2010-01-02', '2026-09-01', '2026-09-20', '2026-09-12'), ['2026-09-05', '2026-09-12']);
});
test('yearly leap days clamp and regain February 29 in leap years', () => {
  assert.deepEqual(expand('yearly', '2024-02-29', '2025-01-01', '2029-01-01'), ['2025-02-28', '2026-02-28', '2027-02-28', '2028-02-29']);
});
test('weekly date survives daylight saving transitions; end date is inclusive', () => {
  assert.deepEqual(expand('weekly', '2026-03-01', '2026-03-02', '2026-03-30', '2026-03-22'), ['2026-03-08', '2026-03-15', '2026-03-22']);
});
