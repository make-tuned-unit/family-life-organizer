#!/usr/bin/env node
// One-off: grant comp ("on the house") premium to specific users' households.
//   node scripts/grant-comp.js jesse sophie ariel
// Run inside the environment whose DB you want to touch (e.g. on Railway).
// Idempotent — safe to run more than once.

const FamilyDB = require('../database');
const { grantCompForGroup } = require('../services/subscription');

(async () => {
  const names = process.argv.slice(2);
  if (!names.length) {
    console.error('usage: node scripts/grant-comp.js <username> [username...]');
    process.exit(1);
  }
  const db = new FamilyDB();
  const seen = new Set();
  for (const name of names) {
    const user = await db.getUserByUsername(name);
    if (!user) { console.log(`no user "${name}" — skipped`); continue; }
    const groupId = await db.getUserHouseholdId(user.id);
    if (!groupId) { console.log(`"${name}" has no household — skipped`); continue; }
    if (seen.has(groupId)) { console.log(`"${name}" shares an already-comped household`); continue; }
    seen.add(groupId);
    await grantCompForGroup(db, groupId, user.id);
    console.log(`✅ comp premium → household ${groupId} (${name})`);
  }
  db.close();
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
