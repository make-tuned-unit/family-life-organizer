#!/usr/bin/env node
/**
 * Password recovery, run against the database directly.
 *
 * There is no forgot-password flow yet, so an account whose password is lost is
 * unreachable through the API — and a device that used to hold a refresh token
 * loses it whenever the app's bundle ID or signing team changes, because the
 * keychain is scoped to both. This is the way back in.
 *
 *   node scripts/reset-password.js --list
 *   node scripts/reset-password.js --user jesse --password 'a new password'
 *
 * On Railway, run it where the volume is mounted so it edits the real DB:
 *   railway run node scripts/reset-password.js --list
 *
 * TRUST MODEL: this bypasses authentication entirely. It is safe only because
 * it needs filesystem access to family.db, and anyone with that already has
 * every row. It must never be reachable over HTTP.
 */

const bcrypt = require('bcryptjs');
const FamilyDB = require('../database');

const args = process.argv.slice(2);
const argOf = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
};

const GREEN = '\x1b[32m', RED = '\x1b[31m', DIM = '\x1b[2m', OFF = '\x1b[0m';

const all = (db, sql, params = []) =>
  new Promise((resolve, reject) => db.db.all(sql, params, (e, r) => (e ? reject(e) : resolve(r || []))));
const run = (db, sql, params = []) =>
  new Promise((resolve, reject) => db.db.run(sql, params, function (e) { e ? reject(e) : resolve(this); }));

async function list(db) {
  // Enough to recognise yourself, and the 2FA state — an account with no email
  // cannot be recovered by any emailed flow we might add later.
  const rows = await all(db, `
    SELECT u.id, u.username, u.name, u.email, u.email_verified, u.two_factor_enabled,
           (SELECT COUNT(*) FROM auth_tokens WHERE user_id = u.id) AS devices,
           u.created_at
    FROM users u ORDER BY u.id`);
  if (!rows.length) {
    console.log(`\n${RED}No users in this database.${OFF} Check FAMILY_DB_DIR points at the mounted volume.\n`);
    return;
  }
  console.log('');
  console.log('  id  username             name                 email                          2FA  devices');
  console.log('  ──  ───────────────────  ───────────────────  ─────────────────────────────  ───  ───────');
  for (const u of rows) {
    console.log(
      `  ${String(u.id).padEnd(3)} ${String(u.username || '').padEnd(20)} ${String(u.name || '').padEnd(20)} ` +
      `${String(u.email || '—').padEnd(30)} ${u.two_factor_enabled ? 'on ' : 'off'}  ${u.devices}`);
  }
  console.log(`\n${DIM}Reset one with: node scripts/reset-password.js --user <username> --password '<new>'${OFF}\n`);
}

async function reset(db, who, password) {
  // Mirror the API's own rules so a password set here can also be set later
  // through change-password, rather than being one this app would have refused.
  if (password.length < 8) throw new Error('Password must be at least 8 characters');
  if (Buffer.byteLength(password, 'utf8') > 72) throw new Error('Password must be at most 72 bytes (bcrypt limit)');

  const rows = await all(db, 'SELECT id, username FROM users WHERE username = ? OR id = ?', [who, parseInt(who, 10) || -1]);
  if (!rows.length) throw new Error(`No user matching "${who}" — run --list to see them.`);
  if (rows.length > 1) throw new Error(`"${who}" is ambiguous.`);
  const user = rows[0];
  if (password === user.username) throw new Error('Password must not equal the username');

  // Cost 12, matching register and change-password.
  const hash = await bcrypt.hash(password, 12);
  await db.updateUserPassword(user.id, hash);

  // Same posture as change-password: a password reset signs out every device,
  // with no grace window. A lost password is exactly when you must assume the
  // old sessions are not yours.
  const { changes } = await run(db, 'DELETE FROM auth_tokens WHERE user_id = ?', [user.id]);

  console.log(`\n${GREEN}✓${OFF} Password reset for ${user.username} (id ${user.id}).`);
  console.log(`  ${DIM}${changes} device token${changes === 1 ? '' : 's'} revoked — every device signs in again.${OFF}\n`);
}

(async () => {
  const db = new FamilyDB();
  try {
    if (args.includes('--list')) return await list(db);
    const who = argOf('--user');
    const password = argOf('--password');
    if (!who || !password) {
      console.log(`
Usage:
  node scripts/reset-password.js --list
  node scripts/reset-password.js --user <username|id> --password '<new password>'
`);
      process.exitCode = 1;
      return;
    }
    await reset(db, who, password);
  } catch (err) {
    // Pointing at the wrong directory is the easy mistake — FamilyDB creates an
    // empty file rather than failing, so the first sign is a missing table.
    const msg = /no such table/.test(err.message)
      ? `This database has no tables — FAMILY_DB_DIR is almost certainly pointing somewhere other than the mounted volume.\n  On Railway, run it inside the deployment: railway run node scripts/reset-password.js --list`
      : err.message;
    console.error(`\n${RED}✗ ${msg}${OFF}\n`);
    process.exitCode = 1;
  } finally {
    db.close();
  }
})();
