// Preloaded into a spawned test server (node --require) to record every push
// the server enqueues, one JSON line per call, in PUSH_CAPTURE_FILE. Nothing
// reaches APNs; tests assert on who would have been notified and with what.
const fs = require('node:fs');
const jobs = require('../../services/jobs');
const file = process.env.PUSH_CAPTURE_FILE;
const record = entry => fs.appendFileSync(file, JSON.stringify(entry) + '\n');
jobs.pushToUser = async (db, userId, title, body, data) => record({ kind: 'user', userId, title, body, data });
jobs.pushToGroup = async (db, groupId, excludeUserId, title, body, data) => record({ kind: 'group', groupId, excludeUserId, title, body, data });
