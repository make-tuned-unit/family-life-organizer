// Concierge chat system prompt + source handling (no Anthropic call).

const { test } = require('node:test');
const assert = require('node:assert');
const { buildSystem, sanitizeName, normalizeSource } = require('../services/conciergeChat');

test('normalizeSource accepts voice and chat_extract, defaults unknowns to text', () => {
  assert.equal(normalizeSource('voice'), 'voice');
  assert.equal(normalizeSource('chat_extract'), 'chat_extract');
  assert.equal(normalizeSource('text'), 'text');
  assert.equal(normalizeSource(undefined), 'text');
  assert.equal(normalizeSource('VOICE'), 'voice');
  assert.equal(normalizeSource('inject'), 'text');
});

test('voice source tells the model to execute dictated actions', () => {
  const system = buildSystem('Jesse', '2026-08-27', [], 'voice');
  assert.match(system, /VOICE:/);
  assert.match(system, /execute them with tools now/);
  assert.doesNotMatch(system, /CHAT EXTRACT:/);
});

test('chat_extract source tells the model to break a thread into household items', () => {
  const system = buildSystem('Jesse', '2026-08-27', [], 'chat_extract');
  assert.match(system, /CHAT EXTRACT:/);
  assert.match(system, /calendar events, tasks, list items, routines/);
  assert.doesNotMatch(system, /VOICE:/);
});

test('plain text source does not add voice or extract guidance', () => {
  const system = buildSystem('Jesse', '2026-08-27', []);
  assert.doesNotMatch(system, /VOICE:/);
  assert.doesNotMatch(system, /CHAT EXTRACT:/);
  assert.match(system, /Jesse/);
});

test('sanitizeName strips control chars and falls back', () => {
  assert.equal(sanitizeName('Ada\nLovelace'), 'Ada Lovelace');
  assert.equal(sanitizeName(''), 'the user');
});
