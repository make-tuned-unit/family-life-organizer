const fs = require('node:fs');
const path = require('node:path');
const RETENTION_DAYS = 14;

// Age-based expiry still works after downtime or infrequent deployments.
// Only application-owned dated snapshots may be removed.
function pruneSnapshots(directory, now = new Date()) {
  if (!fs.existsSync(directory)) return [];
  const cutoff = now.getTime() - RETENTION_DAYS * 86400000;
  const removed = [];
  for (const name of fs.readdirSync(directory)) {
    const match = /^family-(\d{4}-\d{2}-\d{2})\.db$/.exec(name);
    if (!match) continue;
    const stamp = Date.parse(`${match[1]}T00:00:00.000Z`);
    if (!Number.isFinite(stamp) || stamp > cutoff) continue;
    const file = path.join(directory, name);
    if (!fs.lstatSync(file).isFile()) continue;
    fs.unlinkSync(file);
    removed.push(name);
  }
  return removed;
}

async function createSnapshot(db, directory, now = new Date()) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const removed = pruneSnapshots(directory, now);
  const destination = path.join(directory, `family-${now.toISOString().slice(0, 10)}.db`);
  if (!fs.existsSync(destination)) await db.backupTo(destination);
  fs.chmodSync(destination, 0o600);
  return { destination, removed };
}

module.exports = { RETENTION_DAYS, pruneSnapshots, createSnapshot };
