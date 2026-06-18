#!/usr/bin/env node
/**
 * One-time corrective migration: re-attribute household-scoped rows to the
 * CORRECT household after the legacy aggressive backfill (and the round-2 NULL
 * backfill) lumped everyone's data into the primary household.
 *
 * The actual re-attribution logic lives in FamilyDB.reattributeHouseholds()
 * (database.js) so it is shared with the one-time startup pass
 * (reattributeHouseholdsOnce, run automatically on deploy). This CLI is the
 * manual/ad-hoc entrypoint: it adds a dry-run preview, an orphan-household
 * report, the list of tables that can't be auto-split, and a DB backup before
 * applying.
 *
 * Strategy (in the shared method): the only durable ownership signal that
 * survived the bad backfill is the NAME on each row. We map it -> the user ->
 * that user's household and move the row there, but ONLY when the name resolves
 * UNAMBIGUOUSLY to a single household. Unresolved/ambiguous owners are left
 * alone. Tables with no owner column (budget_categories, gift_people, ...)
 * can't be split and are only reported.
 *
 * Usage:
 *   node scripts/fix-household-attribution.js            # dry run (no writes)
 *   node scripts/fix-household-attribution.js --apply    # back up + apply
 */

const fs = require('fs');
const FamilyDB = require('../database.js');

const APPLY = process.argv.includes('--apply');

// Tables with no per-row owner signal — cannot be split, report only.
const UNSPLITTABLE = ['budget_categories', 'gift_people', 'gift_ideas', 'special_events'];

(async () => {
  const db = new FamilyDB();
  const all = (sql, p = []) => new Promise((r, j) => db.db.all(sql, p, (e, x) => e ? j(e) : r(x)));
  const get = (sql, p = []) => new Promise((r, j) => db.db.get(sql, p, (e, x) => e ? j(e) : r(x)));
  const run = (sql, p = []) => new Promise((r, j) => db.db.run(sql, p, function (e) { e ? j(e) : r(this); }));

  console.log(`\n=== Household re-attribution ${APPLY ? '(APPLY)' : '(DRY RUN)'} ===\n`);

  // Ensure schema + standard migrations have run so group_id columns exist.
  await db.initSchema();
  await db.runHouseholdMigrations();

  const households = await all(`SELECT id, name FROM groups WHERE group_type = 'household'`);
  const hhName = Object.fromEntries(households.map(h => [h.id, h.name]));
  console.log('Households:', households.map(h => `${h.id}:${h.name}`).join(', ') || '(none)');
  for (const h of households) {
    const c = await get('SELECT COUNT(*) n FROM group_members WHERE group_id = ?', [h.id]);
    if (c.n === 0) console.log(`  ⚠ household ${h.id}:${h.name} has NO members (orphan)`);
  }

  // Compute proposed moves via the shared core (no writes yet).
  const { moves } = await db.reattributeHouseholds({ apply: false });

  console.log('\n--- Tables with no owner signal (left in place, manual review if needed) ---');
  for (const t of UNSPLITTABLE) {
    try {
      const byGroup = await all(`SELECT group_id, COUNT(*) n FROM ${t} GROUP BY group_id`);
      console.log(`${t}: ` + (byGroup.map(g => `group ${g.group_id}=${g.n}`).join(', ') || '(empty)'));
    } catch { console.log(`${t}: (no group_id column / table)`); }
  }

  if (!moves.length) {
    console.log('\n✅ Nothing to re-attribute — every owned row is already in the correct household.');
    db.close();
    return;
  }

  console.log(`\n--- Proposed moves (${moves.length}) ---`);
  console.table(moves.map(m => ({
    table: m.table, id: m.id, owner: m.by,
    from: `${m.from}:${hhName[m.from] || '?'}`, to: `${m.to}:${hhName[m.to] || '?'}`,
  })));

  if (!APPLY) {
    console.log('\nDRY RUN — no changes written. Re-run with --apply to back up the DB and apply.');
    db.close();
    return;
  }

  // Snapshot the DB file (checkpoint WAL first for a consistent copy).
  await run('PRAGMA wal_checkpoint(TRUNCATE)');
  const dbPath = db.db.filename;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = `${dbPath}.bak-${stamp}`;
  fs.copyFileSync(dbPath, backup);
  console.log(`\nBackup written: ${backup}`);

  const res = await db.reattributeHouseholds({ apply: true });
  console.log(`✅ Applied ${res.applied} re-attributions.`);
  db.close();
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
