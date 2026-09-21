#!/usr/bin/env node
// Static wiring gate. Does not claim HTTP behavior, Swift decoding or model accuracy.
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const registry = require('../services/conciergeTools');
const routes = [...read('dashboard.js').matchAll(/app\.(get|post|put|delete|patch)\('([^']+)'/g)].map(m => ({
  method: m[1], route: m[2], pattern: new RegExp('^' + m[2].split('/').map(s => s.startsWith(':') ? '[^/]+' : s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('/') + '$'),
}));
const calls = [...read('FamilyLife/Services/APIService.swift').matchAll(/\b(get|post|put|delete)\("([^"\n]+)"/g)].map(m => ({method: m[1], route: m[2].replace(/\\\([^)]*\)/g, ':value')}));
const missingRoutes = calls.filter(c => !routes.some(r => r.method === c.method && r.pattern.test(c.route)));
const manifest = JSON.parse(read('docs/qa/concierge-workflows.json'));
const names = new Set(registry.TOOLS.map(t => t.name));
const workflows = manifest.requirements.map(w => ({ ...w, missing: w.operations.filter(op => !names.has(op)) }));
const surface = { handlers: names.size, modelTools: registry.definitions().length, workflows, nativeHandoffsUnverified: manifest.native_handoffs_unverified };
const result = { checkedAt: new Date().toISOString(), clientCalls: calls.length, serverRoutes: routes.length, missingRoutes, concierge: surface };
if (process.argv.includes('--json')) console.log(JSON.stringify(result, null, 2));
else {
  console.log(`Client/API routes: ${calls.length} call sites, ${routes.length} routes; ${missingRoutes.length} unmatched.`);
  console.log(`Concierge: ${names.size} handlers, ${surface.modelTools} tools.`);
  for (const w of workflows.filter(w => w.missing.length)) console.log(`GAP ${w.workflow}: ${w.missing.join(', ')}`);
  console.log(`Native handoffs awaiting verification: ${surface.nativeHandoffsUnverified.length}`);
}
const parityFailed = workflows.some(w => w.missing.length) || surface.nativeHandoffsUnverified.length;
process.exitCode = missingRoutes.length || (process.argv.includes('--require-parity') && parityFailed) ? 1 : 0;
