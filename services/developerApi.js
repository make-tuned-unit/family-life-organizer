// Developer API — lets a paid household plug its own agent into Kinrows.
//
// A user mints an API key in Settings (session-authenticated, premium
// required). The key then authenticates the `/v1/*` surface, which exposes the
// exact same tool catalog the built-in Concierge drives, in two shapes:
//   • plain REST   — GET /v1/tools, POST /v1/tools/:name
//   • MCP          — POST /v1/mcp (Streamable HTTP, JSON-RPC 2.0, stateless)
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
const push = require('../push');
const { buildSnapshot, todayISO, nowTimeHM } = require('./conciergeContext');

const KEY_PREFIX = 'kr_live_';
const MAX_ACTIVE_KEYS = 10;
const SCOPES = new Set(['read', 'write']);
const MCP_PROTOCOL_VERSION = '2025-03-26';

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

// Resolves a bearer key to { userId, groupId, scope, keyId, keyName, tier }.
// Throws { status, message } on any failure so the middleware can answer
// uniformly. Also stamps last_used_at (fire-and-forget).
async function authenticateKey(db, authorization) {
  const m = /^Bearer\s+(\S+)$/i.exec(authorization || '');
  if (!m || !m[1].startsWith(KEY_PREFIX)) {
    const err = new Error('Missing or malformed API key. Send `Authorization: Bearer kr_live_…`.');
    err.status = 401; throw err;
  }
  const row = await dbGet(db, 'SELECT * FROM api_keys WHERE key_hash = ?', [hashKey(m[1])]);
  if (!row || row.revoked) {
    const err = new Error('Invalid or revoked API key.');
    err.status = 401; throw err;
  }
  const premium = await subscription.isHouseholdPremium(db, row.user_id);
  if (!premium) {
    const err = new Error('The Developer API requires an active Concierge subscription for this household.');
    err.status = 402; throw err;
  }
  const [groupId, tier] = await Promise.all([
    db.getUserHouseholdId(row.user_id),
    subscription.getHouseholdTier(db, row.user_id),
  ]);
  dbRun(db, 'UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP WHERE id = ?', [row.id]).catch(() => {});
  return { userId: row.user_id, groupId, scope: row.scope, keyId: row.id, keyName: row.name, tier };
}

// Build the same ctx the Concierge hands to tool handlers.
async function buildToolContext(db, auth) {
  const user = await db.getUserById(auth.userId);
  return {
    db,
    userId: auth.userId,
    userName: user?.name || 'there',
    groupId: auth.groupId,
    push,
    today: todayISO(),
    nowTime: nowTimeHM(),
    source: 'developer_api',
  };
}

// Run one tool call under the key's scope. Returns { result } (never throws for
// tool-level errors; scope violations are surfaced as a result error so both
// REST and MCP callers see the same shape).
async function callTool(db, auth, name, input) {
  input = input && typeof input === 'object' ? input : {};
  if (auth.scope === 'read' && !tools.isReadOnly(name, input)) {
    return { result: { error: `This API key is read-only; "${name}"${input.action ? ` (${input.action})` : ''} would modify data. Create a write-scoped key to allow this.` }, forbidden: true };
  }
  const ctx = await buildToolContext(db, auth);
  return tools.run(name, ctx, input);
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

// ── MCP (Streamable HTTP, stateless) ────────────────────────────────────────
// Implements just enough of the Model Context Protocol for hosts to list and
// call tools: initialize, ping, tools/list, tools/call. Notifications get 202.

function rpcError(id, code, message) {
  return { jsonrpc: '2.0', id: id ?? null, error: { code, message } };
}
function rpcResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

async function handleMcp(db, auth, message) {
  if (!message || message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    return rpcError(message?.id, -32600, 'Invalid Request');
  }
  const { id, method, params = {} } = message;
  const isNotification = id === undefined || id === null;
  if (isNotification) return null; // notifications/initialized etc. — nothing to send

  switch (method) {
    case 'initialize':
      return rpcResult(id, {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'kinrows', version: '1.0.0' },
        instructions: `You are connected to the Kinrows household of ${auth.keyName ? `"${auth.keyName}"` : 'this user'}. Every tool acts on that household only. Today is ${todayISO()}.`,
      });
    case 'ping':
      return rpcResult(id, {});
    case 'tools/list':
      return rpcResult(id, {
        tools: tools.definitions().map(d => ({ name: d.name, description: d.description, inputSchema: d.input_schema })),
      });
    case 'tools/call': {
      const name = params?.name;
      if (typeof name !== 'string') return rpcError(id, -32602, 'params.name is required');
      const out = await callTool(db, auth, name, params.arguments || {});
      const payload = out?.result ?? out;
      const isError = !!(payload && typeof payload === 'object' && payload.error);
      return rpcResult(id, {
        content: [{ type: 'text', text: typeof payload === 'string' ? payload : JSON.stringify(payload) }],
        isError,
      });
    }
    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

module.exports = {
  KEY_PREFIX, MAX_ACTIVE_KEYS, MCP_PROTOCOL_VERSION,
  listKeys, createKey, revokeKey,
  authenticateKey, callTool, catalog, whoami, snapshot, handleMcp,
};
