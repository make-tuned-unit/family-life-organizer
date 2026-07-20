#!/usr/bin/env node
// Concierge tool-routing sanity eval.
//
// Feeds real user phrasings to the concierge tool surface and checks the model
// picks the right domain tool + action. Two halves:
//   1. STRUCTURAL (always runs, no API): every case's expected {tool, action}
//      exists in definitions() and is routable — catches spec typos / gaps.
//   2. LIVE (runs when ANTHROPIC_API_KEY is set): one Haiku call per case with
//      the real definitions + system prompt, tool_choice=auto, and checks the
//      first tool_use the model emits.
//
// Usage:
//   node scripts/concierge-tool-eval.js               # structural only
//   ANTHROPIC_API_KEY=sk-... node scripts/concierge-tool-eval.js   # + live

const tools = require('../services/conciergeTools');
const { buildSystem } = require('../services/conciergeChat');

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-haiku-4-5';

// Each case: a phrasing plus the domain tool it must hit and the acceptable
// action(s). For update/complete/delete intents the model may legitimately read
// first (look up the id), so those accept the domain's list action too.
const CASES = [
  { say: 'add a dentist appointment for Rowan next Tuesday at 3pm', tool: 'calendar', actions: ['add'] },
  { say: "what's on the calendar this week?", tool: 'calendar', actions: ['list'] },
  { say: 'invite Sophie to the birthday dinner on the calendar', tool: 'calendar', actions: ['update', 'list', 'add'] },
  { say: 'add milk and eggs to the groceries list', tool: 'lists', actions: ['add'] },
  { say: 'take a note to call the plumber tomorrow', tool: 'notes', actions: ['add'] },
  { say: 'remember that Sophie is allergic to shellfish', tool: 'remember', actions: null },
  { say: 'add a task to renew the car insurance', tool: 'tasks', actions: ['add'] },
  { say: 'mark the laundry task as done', tool: 'tasks', actions: ['complete', 'list'] },
  { say: 'how much have we spent on groceries this month?', tool: 'budget', actions: ['get'] },
  { say: "what's in the pantry right now?", tool: 'pantry', actions: ['list'] },
  { say: 'log that Jude took his first steps today', tool: 'people', actions: ['log_milestone'] },
  { say: "add Grandma's birthday on July 20th as a key date", tool: 'special_events', actions: ['add'] },
  { say: 'start a step-count competition between me and Sophie', tool: 'rivalries', actions: ['create'] },
  { say: 'post to the family feed that soccer practice is cancelled', tool: 'feed', actions: ['post'] },
  { say: 'track our Netflix subscription at $17 a month', tool: 'recurring_payments', actions: ['add'] },
  { say: 'save a contact for Dr. Patel, our pediatrician', tool: 'contacts', actions: ['add'] },
  { say: 'we need a babysitter Friday night, ask the care team', tool: 'coverage', actions: ['create'] },
  { say: "start a trip — I'm driving to the airport now", tool: 'trips', actions: ['add'] },
  // Full-CRUD coverage (edit / delete / move / create everywhere)
  { say: 'move the dentist task to Friday', tool: 'tasks', actions: ['update', 'list'] },
  { say: 'delete the car insurance task, we sold the car', tool: 'tasks', actions: ['delete', 'list'] },
  { say: 'make a new packing list for the cottage', tool: 'lists', actions: ['create'] },
  { say: 'take the milk off the grocery list, we already have some', tool: 'lists', actions: ['delete_item', 'get'] },
  { say: 'move the batteries from Groceries to the Costco list', tool: 'lists', actions: ['move_item', 'get'] },
  { say: 'I spent $42 at Costco today on groceries', tool: 'budget', actions: ['log_expense'] },
  { say: 'start a poll: pizza or tacos for Friday dinner?', tool: 'decisions', actions: ['create'] },
  { say: 'mark the Lego set for Jude as purchased', tool: 'gifts', actions: ['update_idea', 'list_ideas'] },
  { say: 'did anyone ask me for babysitting help?', tool: 'coverage', actions: ['incoming'] },
  { say: 'cancel my babysitter request for Friday night', tool: 'coverage', actions: ['list', 'cancel'] },
  { say: "tell Sophie I'll be home late tonight", tool: 'send_message', actions: null },
  { say: 'end the step competition and call the winner', tool: 'rivalries', actions: ['complete', 'list'] },
];

const defs = tools.definitions();
const byName = new Map(defs.map(d => [d.name, d]));

function structural() {
  let ok = 0;
  const fails = [];
  for (const c of CASES) {
    const def = byName.get(c.tool);
    if (!def) { fails.push(`${c.tool}: not a model-facing tool`); continue; }
    if (c.actions) {
      const enum_ = def.input_schema.properties.action && def.input_schema.properties.action.enum;
      const missing = c.actions.filter(a => !enum_ || !enum_.includes(a));
      if (missing.length) { fails.push(`${c.tool}: actions not in enum -> ${missing.join(', ')}`); continue; }
    }
    ok++;
  }
  console.log(`\nSTRUCTURAL: ${ok}/${CASES.length} intents expressible & routable`);
  fails.forEach(f => console.log('  FAIL', f));
  return fails.length === 0;
}

async function callModel(say) {
  const system = buildSystem('Jesse', '2026-07-03', []);
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: MODEL, max_tokens: 512, system,
      tools: defs, tool_choice: { type: 'auto' },
      messages: [{ role: 'user', content: say }],
    }),
  });
  if (!res.ok) throw new Error(`API ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const data = await res.json();
  const tu = (data.content || []).find(b => b.type === 'tool_use');
  return tu ? { name: tu.name, action: tu.input && tu.input.action } : { name: '(no tool)', action: undefined };
}

async function live() {
  console.log(`\nLIVE (${MODEL}):`);
  let pass = 0;
  for (const c of CASES) {
    let got;
    try { got = await callModel(c.say); }
    catch (e) { console.log('  ERR ', c.say, '::', e.message); continue; }
    const toolOk = got.name === c.tool;
    const actionOk = !c.actions || c.actions.includes(got.action);
    const good = toolOk && actionOk;
    if (good) pass++;
    console.log(`  ${good ? 'PASS' : 'FAIL'}  "${c.say}"`);
    if (!good) console.log(`        expected ${c.tool}${c.actions ? ' (' + c.actions.join('/') + ')' : ''}, got ${got.name}${got.action ? ' (' + got.action + ')' : ''}`);
  }
  console.log(`\nLIVE: ${pass}/${CASES.length} routed correctly`);
  return pass;
}

(async () => {
  console.log(`Concierge surface: ${defs.length} model-facing tools`);
  const sOk = structural();
  if (!process.env.ANTHROPIC_API_KEY) {
    console.log('\n(no ANTHROPIC_API_KEY — skipping live model eval)');
    console.log('Run live:  ANTHROPIC_API_KEY=sk-... node scripts/concierge-tool-eval.js');
    process.exit(sOk ? 0 : 1);
  }
  const pass = await live();
  process.exit(pass === CASES.length ? 0 : 1);
})();
