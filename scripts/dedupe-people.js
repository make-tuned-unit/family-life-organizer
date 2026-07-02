#!/usr/bin/env node
/**
 * De-duplicate the People registry (gift_people).
 *
 * Recurring problem: someone adds a person as a gift recipient with a fuller
 * name (e.g. "Sophie Chiasson") BEFORE that person becomes a household user.
 * When they later join, ensureHouseholdUserPeople() creates/links a second row
 * on the exact user name ("Sophie") — but never matches the fuller name, so the
 * same real person shows up twice in the People hub.
 *
 * This script finds those pairs and merges the orphan (the non-user-linked row)
 * INTO the canonical, user-linked row: it re-points every person_id reference
 * (gift_ideas, milestones, special_events, decisions) to the survivor, then
 * deletes the orphan. Conservative match: same group_id AND the orphan name is
 * the user row's name OR the user name followed by a space (a surname), so
 * "Sophie" adopts "Sophie Chiasson" but never "Sophia".
 *
 * Usage:
 *   node scripts/dedupe-people.js            # dry run (no writes)
 *   node scripts/dedupe-people.js --apply    # back up + apply
 *
 * Run inside the environment whose DB you want to touch (e.g. on Railway,
 * via `railway run node scripts/dedupe-people.js`).
 */

const fs = require('fs');
const FamilyDB = require('../database.js');

const APPLY = process.argv.includes('--apply');

// Tables whose person_id points at gift_people.id. decisions is SET NULL on
// delete; the rest CASCADE — so we must re-point BEFORE deleting the orphan.
const REPOINT = ['gift_ideas', 'milestones', 'special_events', 'decisions'];

(async () => {
  const db = new FamilyDB();
  const all = (sql, p = []) => new Promise((r, j) => db.db.all(sql, p, (e, x) => e ? j(e) : r(x)));
  const get = (sql, p = []) => new Promise((r, j) => db.db.get(sql, p, (e, x) => e ? j(e) : r(x)));
  const run = (sql, p = []) => new Promise((r, j) => db.db.run(sql, p, function (e) { e ? j(e) : r(this); }));

  console.log(`\n=== People de-dupe ${APPLY ? '(APPLY)' : '(DRY RUN)'} ===\n`);

  await db.initSchema();
  await db.runHouseholdMigrations();

  // Canonical rows = user-linked people. Orphans = non-user-linked rows in the
  // same group whose name matches a canonical name (exact or "Name <surname>").
  const canonical = await all(
    `SELECT id, name, group_id, user_id FROM gift_people WHERE user_id IS NOT NULL`
  );

  const merges = [];
  for (const c of canonical) {
    const orphans = await all(
      `SELECT id, name FROM gift_people
       WHERE group_id = ? AND user_id IS NULL AND id != ?
         AND (lower(name) = lower(?) OR lower(name) LIKE lower(?))`,
      [c.group_id, c.id, c.name, `${c.name} %`]
    );
    for (const o of orphans) {
      const counts = {};
      for (const t of REPOINT) {
        const row = await get(`SELECT COUNT(*) n FROM ${t} WHERE person_id = ?`, [o.id]);
        counts[t] = row.n;
      }
      merges.push({ orphanId: o.id, orphanName: o.name, keepId: c.id, keepName: c.name, group: c.group_id, counts });
    }
  }

  if (!merges.length) {
    console.log('✅ No duplicate people found — nothing to merge.');
    db.close();
    return;
  }

  console.log(`--- Proposed merges (${merges.length}) ---`);
  console.table(merges.map(m => ({
    'merge (orphan)': `${m.orphanId}:${m.orphanName}`,
    'into (keep)': `${m.keepId}:${m.keepName}`,
    group: m.group,
    repoint: REPOINT.map(t => `${t}=${m.counts[t]}`).join(' '),
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

  let applied = 0;
  await run('BEGIN');
  try {
    for (const m of merges) {
      for (const t of REPOINT) {
        await run(`UPDATE ${t} SET person_id = ? WHERE person_id = ?`, [m.keepId, m.orphanId]);
      }
      await run(`DELETE FROM gift_people WHERE id = ?`, [m.orphanId]);
      applied++;
    }
    await run('COMMIT');
  } catch (e) {
    await run('ROLLBACK');
    throw e;
  }

  console.log(`✅ Merged ${applied} duplicate ${applied === 1 ? 'person' : 'people'}.`);
  db.close();
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
