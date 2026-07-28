#!/usr/bin/env node
// Repairs the two states that predate the fixes in c01e320..b79eddf. Both are
// invisible from inside the app, which is why they need a script:
//
//   1. ORPHANED FEED POSTS — a routine or milestone was deleted (or un-shared)
//      while the post announcing it stayed behind. Tapping one opens a detail
//      page that can never load ("Couldn't load this routine"). Deleting the
//      post is safe: the thing it pointed at is already gone.
//
//   2. UNREACHABLE PRIVATE ROWS — a key date or milestone created before
//      `created_by` existed, then marked private. `created_by IS NULL` matches
//      no user, so it is hidden from EVERYONE including its author, and the
//      route guard 404s for all of them. These are REPORTED, never changed:
//      picking an owner is a guess, and guessing wrong hands someone else's
//      private row to the wrong person. The script prints the exact statement
//      to run once a human says who owns it.
//
// Dry run by default. Pass --apply to perform the deletions in (1).
//
//   node scripts/repair-orphaned-references.js
//   node scripts/repair-orphaned-references.js --apply
//   railway run node scripts/repair-orphaned-references.js --apply   (production)

const FamilyDB = require('../database');

const APPLY = process.argv.includes('--apply');

function all(db, sql, params = []) {
  return new Promise((res, rej) => db.db.all(sql, params, (e, r) => e ? rej(e) : res(r || [])));
}
function run(db, sql, params = []) {
  return new Promise((res, rej) => db.db.run(sql, params, function (e) { e ? rej(e) : res(this); }));
}

(async () => {
  const db = new FamilyDB();
  await db.initSchema();
  // Migrations queue behind initSchema on the same connection.
  await new Promise(r => setTimeout(r, 400));

  console.log(APPLY ? '=== REPAIR (applying changes) ===' : '=== DRY RUN (nothing will change) ===\n');

  // ---- 1. Feed posts pointing at rows that no longer exist ----------------
  const orphanPosts = await all(db, `
    SELECT fp.id, fp.reference_type, fp.reference_id, fp.title, fp.group_id
    FROM feed_posts fp
    WHERE fp.reference_type IN ('routine', 'milestone')
      AND (
        (fp.reference_type = 'routine'   AND NOT EXISTS (SELECT 1 FROM routines   WHERE id = fp.reference_id))
        OR (fp.reference_type = 'milestone' AND NOT EXISTS (SELECT 1 FROM milestones WHERE id = fp.reference_id))
      )
    ORDER BY fp.id`);

  console.log(`Orphaned feed posts: ${orphanPosts.length}`);
  for (const p of orphanPosts) {
    console.log(`  #${p.id}  ${p.reference_type} ${p.reference_id} (gone)  "${p.title || ''}"`);
  }
  if (APPLY && orphanPosts.length) {
    // Reactions and comments cascade (PRAGMA foreign_keys is ON).
    for (const p of orphanPosts) await run(db, 'DELETE FROM feed_posts WHERE id = ?', [p.id]);
    console.log(`  -> deleted ${orphanPosts.length}`);
  }

  // ---- 2. Private rows nobody can reach ------------------------------------
  // Reported only. See the header for why this is not auto-repaired.
  for (const [table, dateCol] of [['special_events', 'date'], ['milestones', 'milestone_date']]) {
    const cols = await all(db, `PRAGMA table_info(${table})`);
    if (!cols.some(c => c.name === 'shared_scope') || !cols.some(c => c.name === 'created_by')) continue;
    const stranded = await all(db, `
      SELECT id, title, ${dateCol} AS on_date, group_id
      FROM ${table}
      WHERE shared_scope = 'private' AND created_by IS NULL
      ORDER BY id`);
    console.log(`\nUnreachable private ${table}: ${stranded.length}`);
    for (const r of stranded) {
      console.log(`  #${r.id}  "${r.title}"  ${r.on_date}  (household ${r.group_id})`);
      console.log(`     adopt with:  UPDATE ${table} SET created_by = <user_id> WHERE id = ${r.id};`);
      console.log(`     or re-share: UPDATE ${table} SET shared_scope = 'household' WHERE id = ${r.id};`);
    }
    if (stranded.length) {
      console.log(`  -> not changed automatically: choosing an owner is a guess, and`);
      console.log(`     guessing wrong hands a private row to the wrong person.`);
    }
  }

  if (!APPLY && orphanPosts.length) {
    console.log('\nRe-run with --apply to delete the orphaned posts.');
  }
  db.close();
})().catch(err => {
  console.error('Repair failed:', err.message);
  process.exit(1);
});
