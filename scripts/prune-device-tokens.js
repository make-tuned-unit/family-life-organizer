#!/usr/bin/env node
/**
 * Device-token cleanup.
 *
 * A push token is bound to the app that minted it, so changing the bundle ID
 * orphaned every token registered under the old one. They cannot be told apart
 * from good tokens by looking — only APNs knows — and it rejects them with
 * DeviceTokenNotForTopic on every single send, forever, because nothing in the
 * normal path deletes them.
 *
 * Deleting a token is safe and self-correcting: the app re-registers on its next
 * launch. The cost of removing a live one is a missed notification until then;
 * the cost of keeping a dead one is a failed send on every push from now on.
 *
 *   node scripts/prune-device-tokens.js                     # show, delete nothing
 *   node scripts/prune-device-tokens.js --before 2026-08-19 --yes
 *   node scripts/prune-device-tokens.js --all --yes
 *
 * On Railway, run it where the volume is mounted:
 *   railway run node scripts/prune-device-tokens.js
 */

const FamilyDB = require('../database');

const args = process.argv.slice(2);
const argOf = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
};

const GREEN = '\x1b[32m', RED = '\x1b[31m', DIM = '\x1b[2m', YELLOW = '\x1b[33m', OFF = '\x1b[0m';

const all = (db, sql, params = []) =>
  new Promise((resolve, reject) => db.db.all(sql, params, (e, r) => (e ? reject(e) : resolve(r || []))));
const run = (db, sql, params = []) =>
  new Promise((resolve, reject) => db.db.run(sql, params, function (e) { e ? reject(e) : resolve(this); }));

(async () => {
  const db = new FamilyDB();
  try {
    const before = argOf('--before');
    const wantsAll = args.includes('--all');
    const confirmed = args.includes('--yes');

    if (before && !/^\d{4}-\d{2}-\d{2}$/.test(before)) {
      throw new Error('--before needs a YYYY-MM-DD date');
    }

    const rows = await all(db, `
      SELECT d.id, d.user_id, d.token, d.updated_at, d.created_at, u.username
      FROM device_tokens d LEFT JOIN users u ON u.id = d.user_id
      ORDER BY d.user_id, d.updated_at`);

    if (!rows.length) {
      console.log(`\n${GREEN}No device tokens registered.${OFF} Nothing to prune.\n`);
      return;
    }

    // updated_at is refreshed on every registration, so it is the closest thing
    // to "which app build minted this" that the row actually carries.
    const doomed = wantsAll
      ? rows
      : before
      ? rows.filter(r => String(r.updated_at || r.created_at || '').slice(0, 10) < before)
      : [];

    console.log(`\n${rows.length} device token${rows.length === 1 ? '' : 's'} registered:\n`);
    console.log('   user                 last registered      status');
    console.log('   ───────────────────  ───────────────────  ──────');
    for (const r of rows) {
      const marked = doomed.includes(r);
      console.log(`   ${String(r.username || `user ${r.user_id}`).padEnd(20)} ` +
        `${String(r.updated_at || r.created_at || '—').slice(0, 19).padEnd(20)} ` +
        `${marked ? RED + 'delete' + OFF : DIM + 'keep' + OFF}`);
    }

    if (!wantsAll && !before) {
      console.log(`\n${YELLOW}Nothing selected.${OFF} Choose what to remove:`);
      console.log(`  ${DIM}--before YYYY-MM-DD${OFF}  tokens last registered before the new build shipped`);
      console.log(`  ${DIM}--all${OFF}                every token (all devices re-register on next launch)`);
      console.log(`  ${DIM}add --yes to actually delete${OFF}\n`);
      return;
    }

    if (!doomed.length) {
      console.log(`\n${GREEN}Nothing matches.${OFF} No tokens older than ${before}.\n`);
      return;
    }

    if (!confirmed) {
      console.log(`\n${YELLOW}Dry run.${OFF} ${doomed.length} token${doomed.length === 1 ? '' : 's'} would be deleted. Re-run with --yes to do it.\n`);
      return;
    }

    const ids = doomed.map(r => r.id);
    const { changes } = await run(db,
      `DELETE FROM device_tokens WHERE id IN (${ids.map(() => '?').join(',')})`, ids);
    console.log(`\n${GREEN}✓${OFF} Deleted ${changes} token${changes === 1 ? '' : 's'}.`);
    console.log(`  ${DIM}Each device registers again the next time its app is opened.${OFF}\n`);
  } catch (err) {
    const msg = /no such table/.test(err.message)
      ? `This database has no tables — FAMILY_DB_DIR is pointing somewhere other than the mounted volume.\n  On Railway: railway run node scripts/prune-device-tokens.js`
      : err.message;
    console.error(`\n${RED}✗ ${msg}${OFF}\n`);
    process.exitCode = 1;
  } finally {
    db.close();
  }
})();
