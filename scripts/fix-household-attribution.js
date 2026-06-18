#!/usr/bin/env node
/**
 * One-time corrective migration: re-attribute household-scoped rows to the
 * CORRECT household after the legacy aggressive backfill (and the round-2 NULL
 * backfill) lumped everyone's data into the primary "Fairbanks" household.
 *
 * Data model (per the household/clan design):
 *   - Each person belongs to exactly ONE household (group_type='household').
 *     Household-scoped data (budgets, appointments, pantry, trips, gifts, etc.)
 *     must live in that one household.
 *   - "Clan" groups (group_type 'family'/'tribe') are cross-household OVERLAP
 *     groups (e.g. Sharratt Clan = Jesse ∩ Ariel). Clans are NOT touched here —
 *     this script only fixes household attribution.
 *
 * Strategy: the only durable ownership signal that survived the bad backfill is
 * the NAME stored on each row. We map that name -> the user -> that user's
 * household, and move the row there. Rows whose owner-name doesn't resolve to a
 * known user (e.g. 'email', 'manual', a contact-only name) are LEFT ALONE.
 * Tables with no owner column at all (budget_categories, gift_people, etc.)
 * cannot be split automatically and are only REPORTED.
 *
 * Safe by default: DRY RUN unless run with --apply. With --apply it first runs
 * the app's own (idempotent) migrations, then snapshots the DB file, then
 * re-attributes inside a single transaction. Re-running is idempotent.
 *
 * Usage:
 *   node scripts/fix-household-attribution.js            # dry run (no writes)
 *   node scripts/fix-household-attribution.js --apply    # back up + apply
 */

const fs = require('fs');
const path = require('path');
const FamilyDB = require('../database.js');

const APPLY = process.argv.includes('--apply');

// Tables we CAN re-attribute, with the column holding the owning person's name.
// `tags: true` means the column is a list of names (appointments.person_tags);
// we only move when every listed name resolves to a single household.
const OWNED = [
  { table: 'receipts',         col: 'added_by' },
  { table: 'pantry',           col: 'added_by' },
  { table: 'trips',            col: 'traveler' },
  { table: 'budget_projects',  col: 'created_by' },
  { table: 'decisions',        col: 'creator_name' },
  { table: 'rivalries',        col: 'initiator_name' },
  { table: 'family_addresses', col: 'created_by' },
  { table: 'appointments',     col: 'person_tags', tags: true, fallback: 'with_person' },
];

// Tables with no per-row owner signal — cannot be split, report only.
const UNSPLITTABLE = ['budget_categories', 'gift_people', 'gift_ideas', 'special_events'];

function main() {
  const db = new FamilyDB();
  const all = (sql, p = []) => new Promise((r, j) => db.db.all(sql, p, (e, x) => e ? j(e) : r(x)));
  const get = (sql, p = []) => new Promise((r, j) => db.db.get(sql, p, (e, x) => e ? j(e) : r(x)));
  const run = (sql, p = []) => new Promise((r, j) => db.db.run(sql, p, function (e) { e ? j(e) : r(this); }));

  const nameCache = new Map(); // lower(name|username) -> householdId|null
  async function householdForName(rawName) {
    if (!rawName) return null;
    const key = String(rawName).trim().toLowerCase();
    if (!key) return null;
    if (nameCache.has(key)) return nameCache.get(key);
    // Refuse to resolve an ambiguous name: if it maps to users in MORE than one
    // household, we can't safely attribute the row — leave it in place.
    const rows = await all(
      `SELECT DISTINCT g.id FROM users u
       JOIN group_members gm ON gm.user_id = u.id
       JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
       WHERE LOWER(u.name) = ? OR LOWER(u.username) = ?`, [key, key]);
    const hh = rows.length === 1 ? rows[0].id : null;
    if (rows.length > 1) console.log(`  ⚠ name "${rawName}" maps to ${rows.length} households — left unresolved (ambiguous)`);
    nameCache.set(key, hh);
    return hh;
  }

  // Resolve a person_tags value to a single household, or null if ambiguous.
  async function householdForTags(value, fallback) {
    let parts = [];
    const v = (value || '').trim();
    if (v.startsWith('[')) { try { parts = JSON.parse(v); } catch { parts = []; } }
    else if (v) { parts = v.split(','); }
    parts = parts.map(s => String(s).trim()).filter(Boolean);
    if (!parts.length && fallback) parts = [String(fallback).trim()].filter(Boolean);
    if (!parts.length) return null;
    const households = new Set();
    for (const p of parts) {
      const hh = await householdForName(p);
      if (!hh) return null;            // an unrecognized tag (e.g. "Family") -> too risky, leave it
      households.add(hh);
    }
    return households.size === 1 ? [...households][0] : null; // mixed-household event -> leave it
  }

  (async () => {
    console.log(`\n=== Household re-attribution ${APPLY ? '(APPLY)' : '(DRY RUN)'} ===\n`);

    // Ensure schema + standard migrations have run so group_id columns exist.
    await db.initSchema();
    await db.runHouseholdMigrations();

    const households = await all(`SELECT id, name FROM groups WHERE group_type = 'household'`);
    const hhName = Object.fromEntries(households.map(h => [h.id, h.name]));
    console.log('Households:', households.map(h => `${h.id}:${h.name}`).join(', ') || '(none)');

    // Flag orphan households (no members) — their rows would be invisible.
    for (const h of households) {
      const c = await get('SELECT COUNT(*) n FROM group_members WHERE group_id = ?', [h.id]);
      if (c.n === 0) console.log(`  ⚠ household ${h.id}:${h.name} has NO members (orphan)`);
    }
    console.log('');

    const moves = []; // {table, id, from, to, by}
    for (const cfg of OWNED) {
      const cols = await all(`PRAGMA table_info(${cfg.table})`);
      if (!cols.some(c => c.name === 'group_id')) { console.log(`skip ${cfg.table}: no group_id column`); continue; }
      const extra = cfg.fallback ? `, ${cfg.fallback}` : '';
      const rows = await all(`SELECT id, group_id, ${cfg.col}${extra} FROM ${cfg.table}`);
      let moved = 0, skipped = 0;
      for (const row of rows) {
        const target = cfg.tags
          ? await householdForTags(row[cfg.col], cfg.fallback ? row[cfg.fallback] : null)
          : await householdForName(row[cfg.col]);
        if (!target) { skipped++; continue; }       // unresolved/ambiguous owner -> leave
        if (target === row.group_id) continue;        // already correct
        moves.push({ table: cfg.table, id: row.id, from: row.group_id, to: target, by: row[cfg.col] });
        moved++;
      }
      console.log(`${cfg.table}: ${rows.length} rows — ${moved} to re-attribute, ${skipped} left (owner unresolved/ambiguous)`);
    }

    console.log('\n--- Tables with no owner signal (left in place, manual review if needed) ---');
    for (const t of UNSPLITTABLE) {
      try {
        const byGroup = await all(`SELECT group_id, COUNT(*) n FROM ${t} GROUP BY group_id`);
        console.log(`${t}: ` + byGroup.map(g => `group ${g.group_id}=${g.n}`).join(', '));
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

    await run('BEGIN');
    try {
      for (const m of moves) {
        await run(`UPDATE ${m.table} SET group_id = ? WHERE id = ?`, [m.to, m.id]);
      }
      await run('COMMIT');
      console.log(`✅ Applied ${moves.length} re-attributions.`);
    } catch (e) {
      await run('ROLLBACK');
      console.error('❌ Rolled back due to error:', e.message);
      process.exitCode = 1;
    }
    db.close();
  })().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
}

main();
