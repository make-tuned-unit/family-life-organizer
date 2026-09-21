#!/usr/bin/env node
// Fail-closed release DAG. External gates require separate evidence; this runner
// can never silently certify device/provider or App Store Connect acceptance.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.join(__dirname, '..');
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'kinrows-release-gates-'));
const native = process.argv.includes('--native');
const gates = [
  { id: 'A', name: 'Client route inventory', deps: [], cmd: [process.execPath, 'scripts/verify-release-wiring.js'] },
  { id: 'B', name: 'Backend behavior, isolation and wiring', deps: ['A'], cmd: ['npm', 'test'] },
  { id: 'C', name: 'Native Release build (unsigned simulator)', deps: ['A'], cmd: native ? ['xcodebuild', '-project', 'FamilyLife.xcodeproj', '-scheme', 'FamilyLife', '-configuration', 'Release', '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', process.env.KINROWS_QA_DERIVED_DATA || path.join(output, 'DerivedData'), 'CODE_SIGNING_ALLOWED=NO', 'build'] : null },
  { id: 'D', name: 'ALL non-Settings Concierge workflows', deps: ['A'], cmd: [process.execPath, 'scripts/verify-release-wiring.js', '--require-parity'] },
  { id: 'E', name: 'Generated marketing consistency', deps: ['A'], cmd: ['npm', 'run', 'seo:check'] },
  // MCP harness uses ports also used by npm test, so it must follow B.
  { id: 'P', name: 'MCP protocol conformance', deps: ['B'], cmd: ['npm', 'run', 'test:mcp:conformance'] },
  { id: 'R', name: 'Structural model routing', deps: ['A'], cmd: ['npm', 'run', 'test:ai:routing'] },
  { id: 'F', name: 'Integrated acceptance', deps: ['B', 'C', 'D', 'E', 'P', 'R'], cmd: null },
  { id: 'G', name: 'Physical device, accessibility and live provider acceptance', deps: ['F'], cmd: null },
  { id: 'H', name: 'App Store Connect and signed distribution acceptance', deps: ['G'], cmd: null },
];
const results = [];
for (const gate of gates) {
  const blockedBy = gate.deps.filter(id => results.find(r => r.id === id)?.status !== 'PASS');
  const row = { id: gate.id, name: gate.name, deps: gate.deps, status: 'NOT_VERIFIED' };
  if (blockedBy.length) { row.status = 'BLOCKED'; row.blockedBy = blockedBy; }
  else if (gate.cmd) {
    const log = path.join(output, `${gate.id}.log`);
    const fd = fs.openSync(log, 'w');
    const run = spawnSync(gate.cmd[0], gate.cmd.slice(1), { cwd: root, stdio: ['ignore', fd, fd], timeout: 15 * 60 * 1000 });
    fs.closeSync(fd);
    row.status = run.status === 0 ? 'PASS' : 'FAIL'; row.exitCode = run.status; row.log = log;
    if (run.error) row.error = run.error.message;
  }
  results.push(row);
  console.log(`${row.id} ${row.status}: ${row.name}`);
}
const report = { checkedAt: new Date().toISOString(), decision: 'HOLD', results,
  note: 'Static routing is not live model verification. Unsigned simulator compilation is not distribution validation. Manual gates cannot pass from this runner.' };
fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`Evidence: ${output}`);
process.exitCode = 1; // HOLD until externally reviewed G/H evidence exists.
