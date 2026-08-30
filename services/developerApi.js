// Developer API — lets a paid household plug its own agent into Kinrows.
//
// A user mints an API key in Settings (session-authenticated, premium
// required). The key then authenticates the `/v1/*` surface, which exposes the
// exact same tool catalog the built-in Concierge drives, in two shapes:
//   • plain REST   — GET /v1/tools, POST /v1/tools/:name
//   • MCP          — POST /v1/mcp (official SDK; modern + stateless legacy)
// so it works with Claude / ChatGPT / Cursor style agents out of the box and
// with hand-rolled agents alike.
//
// Security model: the key is bound to ONE user, and every tool call runs with
// that user's household context (ctx.userId / ctx.groupId), so the existing
// per-handler guards (assertHousehold, assertListAccess, …) apply unchanged.
// Only the SHA-256 hash of a key is stored; the plaintext is shown once.
// Entitlement is re-checked on every request — a lapsed subscription turns the
// key off immediately (402), and revoking a key is a single UPDATE.

const crypto = require('crypto');
const tools = require('./conciergeTools');
const subscription = require('./subscription');
const jobs = require('./jobs');
const oauthServer = require('./oauthServer');
const { buildSnapshot, todayISO, nowTimeHM } = require('./conciergeContext');

const KEY_PREFIX = 'kr_live_';
const MAX_ACTIVE_KEYS = 10;
const SCOPES = new Set(['read', 'write']);

function hashKey(key) {
  return crypto.createHash('sha256').update(String(key)).digest('hex');
}

function dbRun(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.run(sql, params, function (err) { err ? reject(err) : resolve(this); });
  });
}
function dbGet(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
  });
}
function dbAll(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows || []));
  });
}

function publicKeyRow(row) {
  return {
    id: row.id,
    name: row.name,
    key_prefix: row.key_prefix,
    scope: row.scope,
    last_used_at: row.last_used_at,
    created_at: row.created_at,
  };
}

// ── Key management (session-authenticated) ───────────────────────────────────

async function listKeys(db, userId) {
  const rows = await dbAll(db, 'SELECT * FROM api_keys WHERE user_id = ? AND revoked = 0 ORDER BY created_at DESC', [userId]);
  return rows.map(publicKeyRow);
}

// Returns { key, ...publicRow }. `key` is the only time the plaintext exists.
async function createKey(db, userId, { name, scope }) {
  const cleanName = String(name || '').trim().slice(0, 60) || 'My agent';
  const cleanScope = SCOPES.has(scope) ? scope : 'write';
  const active = await dbGet(db, 'SELECT COUNT(*) AS n FROM api_keys WHERE user_id = ? AND revoked = 0', [userId]);
  if (active.n >= MAX_ACTIVE_KEYS) {
    const err = new Error(`You can have at most ${MAX_ACTIVE_KEYS} active keys. Revoke one first.`);
    err.status = 409; throw err;
  }
  const key = KEY_PREFIX + crypto.randomBytes(32).toString('hex');
  const prefix = key.slice(0, KEY_PREFIX.length + 8);
  const r = await dbRun(db, 'INSERT INTO api_keys (user_id, name, key_hash, key_prefix, scope) VALUES (?, ?, ?, ?, ?)',
    [userId, cleanName, hashKey(key), prefix, cleanScope]);
  const row = await dbGet(db, 'SELECT * FROM api_keys WHERE id = ?', [r.lastID]);
  return { key, ...publicKeyRow(row) };
}

// Revokes only the caller's own key. Returns false if no such active key.
async function revokeKey(db, userId, keyId) {
  const r = await dbRun(db, 'UPDATE api_keys SET revoked = 1 WHERE id = ? AND user_id = ? AND revoked = 0', [keyId, userId]);
  return r.changes > 0;
}

// ── Bearer auth for /v1 ─────────────────────────────────────────────────────

// Resolves an API key or OAuth access token to a household-bound principal.
// Throws { status, message } on any failure so the middleware can answer
// uniformly. Also stamps last_used_at (fire-and-forget).
async function authenticateKey(db, authorization) {
  const m = /^Bearer\s+(\S+)$/i.exec(authorization || '');
  if (!m) {
    const err = new Error('Missing bearer credential. Send `Authorization: Bearer …`.');
    err.status = 401; throw err;
  }
  let principal;
  if (m[1].startsWith(KEY_PREFIX)) {
    const row = await dbGet(db, 'SELECT * FROM api_keys WHERE key_hash = ?', [hashKey(m[1])]);
    if (row && !row.revoked) {
      principal = {
        userId: row.user_id, scope: row.scope, keyId: row.id,
        oauthTokenId: null, keyName: row.name, authKind: 'api_key',
      };
      dbRun(db, 'UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP WHERE id = ?', [row.id]).catch(() => {});
    }
  } else {
    principal = await oauthServer.authenticateAccessToken(db, m[1]);
  }
  if (!principal) {
    const err = new Error('Invalid, expired, or revoked bearer credential.');
    err.status = 401; throw err;
  }
  const premium = await subscription.isHouseholdPremium(db, principal.userId);
  if (!premium) {
    const err = new Error('The Developer API requires an active Concierge subscription for this household.');
    err.status = 402; throw err;
  }
  const [groupId, tier] = await Promise.all([
    db.getUserHouseholdId(principal.userId),
    subscription.getHouseholdTier(db, principal.userId),
  ]);
  return { ...principal, groupId, tier };
}

// Build the same ctx the Concierge hands to tool handlers.
async function buildToolContext(db, auth) {
  const user = await db.getUserById(auth.userId);
  return {
    db,
    userId: auth.userId,
    userName: user?.name || 'there',
    groupId: auth.groupId,
    push: jobs,
    today: todayISO(),
    nowTime: nowTimeHM(),
    source: 'developer_api',
  };
}

// Run one tool call under the key's scope. Returns { result } (never throws for
// tool-level errors; scope violations are surfaced as a result error so both
// REST and MCP callers see the same shape).
async function recordToolAudit(db, auth, {
  transport = 'rest', name, input = {}, status, durationMs = 0, errorCode = null,
}) {
  const meta = tools.operationMetadata(name, input);
  await dbRun(db, `INSERT INTO developer_api_audit
    (api_key_id, oauth_token_id, user_id, group_id, transport, tool_name, action, is_write, status, duration_ms, error_code)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [
    auth.keyId, auth.oauthTokenId, auth.userId, auth.groupId, transport, String(name || '').slice(0, 80),
    input?.action == null ? null : String(input.action).slice(0, 80), meta.readOnly ? 0 : 1,
    status, Math.max(0, Math.round(durationMs)), errorCode,
  ]);
}

async function callTool(db, auth, name, input, { transport = 'rest' } = {}) {
  const started = Date.now();
  input = input && typeof input === 'object' ? input : {};
  if (auth.scope === 'read' && !tools.isReadOnly(name, input)) {
    await recordToolAudit(db, auth, {
      transport, name, input, status: 'forbidden', durationMs: Date.now() - started,
      errorCode: 'read_only_scope',
    }).catch(() => {});
    return { result: { error: `This API key is read-only; "${name}"${input.action ? ` (${input.action})` : ''} would modify data. Create a write-scoped key to allow this.` }, forbidden: true };
  }
  const ctx = await buildToolContext(db, auth);
  const out = await tools.run(name, ctx, input);
  const payload = out?.result ?? out;
  await recordToolAudit(db, auth, {
    transport, name, input,
    status: payload && typeof payload === 'object' && payload.error ? 'error' : 'ok',
    durationMs: Date.now() - started,
    errorCode: payload && typeof payload === 'object' && payload.error ? 'tool_error' : null,
  }).catch(() => {});
  return out;
}

// Catalog in Anthropic shape (name/description/input_schema) or OpenAI shape.
function catalog(format) {
  const defs = tools.definitions();
  if (format === 'openai') {
    return defs.map(d => ({ type: 'function', function: { name: d.name, description: d.description, parameters: d.input_schema } }));
  }
  return defs;
}

async function whoami(db, auth) {
  const user = await db.getUserById(auth.userId);
  const household = auth.groupId ? await dbGet(db, 'SELECT id, name FROM groups WHERE id = ?', [auth.groupId]) : null;
  return {
    user: { id: auth.userId, name: user?.name || null },
    household: household ? { id: household.id, name: household.name } : null,
    key: { id: auth.keyId, name: auth.keyName, scope: auth.scope },
    tier: auth.tier,
    today: todayISO(),
    now_time: nowTimeHM(),
  };
}

async function snapshot(db, auth) {
  return buildSnapshot(db, auth.userId);
}

async function auditLog(db, auth, limit = 50) {
  const safeLimit = Math.min(100, Math.max(1, Number.parseInt(limit, 10) || 50));
  return dbAll(db, `SELECT id, transport, tool_name, action, is_write, status,
      duration_ms, error_code, created_at
    FROM developer_api_audit WHERE user_id = ?
    ORDER BY id DESC LIMIT ?`, [auth.userId, safeLimit]);
}

module.exports = {
  KEY_PREFIX, MAX_ACTIVE_KEYS,
  listKeys, createKey, revokeKey,
  authenticateKey, callTool, recordToolAudit, catalog, whoami, snapshot, auditLog,
};
