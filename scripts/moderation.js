#!/usr/bin/env node
// Run inside the trusted application environment. Never exposes a web route.
// No defaults to a local/production DB: the operator must select one explicitly.
if (!process.env.FAMILY_DB_DIR) {
  console.error('Set FAMILY_DB_DIR to the intended database directory.');
  process.exit(1);
}
const FamilyDB = require('../database');
const reports = require('../services/contentReports');
const [command = 'list', id, decision, operator] = process.argv.slice(2);
(async () => {
  const db = new FamilyDB();
  try {
    if (command === 'list') {
      console.log(JSON.stringify(await reports.listOpen(db), null, 2));
    } else if (command === 'status') {
      const summary = await reports.status(db);
      console.log(JSON.stringify(summary));
      if (summary.overdue || summary.delivery_failed) process.exitCode = 1;
    } else if (command === 'resolve' && /^[1-9]\d*$/.test(id || '')) {
      console.log(JSON.stringify(await reports.resolve(db, Number(id), { decision, operator })));
    } else throw new Error('Usage: moderation.js list|status | resolve REPORT_ID remove|dismiss OPERATOR');
  } finally { db.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
