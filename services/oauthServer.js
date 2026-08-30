// OAuth 2.1 authorization server for remote MCP clients.
// Public clients use authorization code + mandatory S256 PKCE. Every opaque
// credential is SHA-256 hashed at rest and access/refresh tokens rotate.

const crypto = require('crypto');
const subscription = require('./subscription');

const ACCESS_PREFIX = 'kr_oauth_';
const REFRESH_PREFIX = 'kr_refresh_';
const ACCESS_TTL_SECONDS = 60 * 60;
const CODE_TTL_MS = 10 * 60 * 1000;
const ALLOWED_SCOPES = new Set(['kinrows:read', 'kinrows:write']);

const hash = value => crypto.createHash('sha256').update(String(value)).digest('hex');
const random = prefix => prefix + crypto.randomBytes(32).toString('base64url');
const run = (db, sql, params = []) => new Promise((resolve, reject) => db.db.run(sql, params, function (err) { err ? reject(err) : resolve(this); }));
const get = (db, sql, params = []) => new Promise((resolve, reject) => db.db.get(sql, params, (err, row) => err ? reject(err) : resolve(row)));

function requestOrigin(req) {
  const configured = String(process.env.KINROWS_PUBLIC_URL || '').trim().replace(/\/$/, '');
  if (configured) return configured;
  // Never let an untrusted Host header shape production issuer/endpoint URLs.
  if (process.env.NODE_ENV === 'production') return 'https://kinrows.com';
  return `${req.protocol}://${req.get('host')}`;
}

function resourceUrl(req) {
  return `${requestOrigin(req)}/v1/mcp`;
}

function parseScopes(raw, fallback = ['kinrows:read']) {
  const values = [...new Set(String(raw || '').split(/\s+/).filter(Boolean))];
  const scopes = values.length ? values : fallback;
  if (scopes.some(scope => !ALLOWED_SCOPES.has(scope))) {
    const err = new Error('Unsupported scope'); err.oauth = 'invalid_scope'; throw err;
  }
  return scopes;
}

function validateRedirectUri(value) {
  let uri;
  try { uri = new URL(String(value)); } catch { throw new Error('Invalid redirect_uri'); }
  const loopback = uri.protocol === 'http:' && ['127.0.0.1', '::1', 'localhost'].includes(uri.hostname);
  if (uri.protocol !== 'https:' && !loopback) throw new Error('redirect_uri must use HTTPS or an HTTP loopback address');
  if (uri.hash) throw new Error('redirect_uri must not contain a fragment');
  return uri.href;
}

async function registerClient(db, metadata) {
  const redirectUris = Array.isArray(metadata?.redirect_uris) ? metadata.redirect_uris.map(validateRedirectUri) : [];
  if (!redirectUris.length || redirectUris.length > 10) throw new Error('redirect_uris must contain 1–10 valid URLs');
  if (metadata.token_endpoint_auth_method && metadata.token_endpoint_auth_method !== 'none') {
    throw new Error('Only public clients with token_endpoint_auth_method "none" are supported');
  }
  const clientId = random('kr_client_');
  const clientName = String(metadata.client_name || 'MCP client').trim().slice(0, 100) || 'MCP client';
  await run(db, 'INSERT INTO oauth_clients (client_id, client_name, redirect_uris) VALUES (?, ?, ?)',
    [clientId, clientName, JSON.stringify(redirectUris)]);
  return {
    client_id: clientId,
    client_name: clientName,
    redirect_uris: redirectUris,
    token_endpoint_auth_method: 'none',
    grant_types: ['authorization_code', 'refresh_token'],
    response_types: ['code'],
    client_id_issued_at: Math.floor(Date.now() / 1000),
  };
}

async function authorizationRequest(db, userId, params) {
  if (params.response_type !== 'code') throw Object.assign(new Error('response_type must be code'), { oauth: 'unsupported_response_type' });
  if (!params.client_id || !params.redirect_uri) throw Object.assign(new Error('client_id and redirect_uri are required'), { oauth: 'invalid_request' });
  if (params.code_challenge_method !== 'S256' || !/^[A-Za-z0-9_-]{43,128}$/.test(String(params.code_challenge || ''))) {
    throw Object.assign(new Error('S256 PKCE is required'), { oauth: 'invalid_request' });
  }
  const client = await get(db, 'SELECT * FROM oauth_clients WHERE client_id = ?', [params.client_id]);
  if (!client) throw Object.assign(new Error('Unknown client'), { oauth: 'unauthorized_client' });
  const redirectUri = validateRedirectUri(params.redirect_uri);
  const registered = JSON.parse(client.redirect_uris || '[]');
  if (!registered.includes(redirectUri)) throw Object.assign(new Error('redirect_uri is not registered'), { oauth: 'invalid_request' });
  if (!(await subscription.isHouseholdPremium(db, userId))) {
    throw Object.assign(new Error('An active Concierge subscription is required'), { oauth: 'access_denied' });
  }
  const scopes = parseScopes(params.scope);
  return { client, redirectUri, scopes, state: params.state || null, codeChallenge: params.code_challenge };
}

async function issueAuthorizationCode(db, userId, request) {
  const code = random('kr_code_');
  await run(db, `INSERT INTO oauth_authorization_codes
    (code_hash, client_id, user_id, redirect_uri, scope, code_challenge, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)`, [
    hash(code), request.client.client_id, userId, request.redirectUri,
    request.scopes.join(' '), request.codeChallenge,
    new Date(Date.now() + CODE_TTL_MS).toISOString(),
  ]);
  return code;
}

async function issueTokenPair(db, { userId, clientId, scope }) {
  const accessToken = random(ACCESS_PREFIX);
  const refreshToken = random(REFRESH_PREFIX);
  const expiresAt = new Date(Date.now() + ACCESS_TTL_SECONDS * 1000).toISOString();
  const inserted = await run(db, `INSERT INTO oauth_tokens
    (user_id, client_id, access_hash, refresh_hash, scope, expires_at)
    VALUES (?, ?, ?, ?, ?, ?)`, [userId, clientId, hash(accessToken), hash(refreshToken), scope, expiresAt]);
  return {
    token_type: 'Bearer', access_token: accessToken, refresh_token: refreshToken,
    expires_in: ACCESS_TTL_SECONDS, scope, tokenId: inserted.lastID,
  };
}

function verifierMatches(verifier, challenge) {
  if (!/^[A-Za-z0-9._~-]{43,128}$/.test(String(verifier || ''))) return false;
  const actual = crypto.createHash('sha256').update(verifier).digest('base64url');
  const a = Buffer.from(actual); const b = Buffer.from(String(challenge));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function exchangeCode(db, params) {
  const row = await get(db, 'SELECT * FROM oauth_authorization_codes WHERE code_hash = ?', [hash(params.code || '')]);
  if (!row || row.used || Date.parse(row.expires_at) <= Date.now()) throw Object.assign(new Error('Invalid or expired authorization code'), { oauth: 'invalid_grant' });
  if (row.client_id !== params.client_id || row.redirect_uri !== validateRedirectUri(params.redirect_uri)) {
    throw Object.assign(new Error('Authorization code binding mismatch'), { oauth: 'invalid_grant' });
  }
  if (!verifierMatches(params.code_verifier, row.code_challenge)) throw Object.assign(new Error('PKCE verification failed'), { oauth: 'invalid_grant' });
  const claimed = await run(db, 'UPDATE oauth_authorization_codes SET used = 1 WHERE code_hash = ? AND used = 0', [hash(params.code)]);
  if (claimed.changes !== 1) throw Object.assign(new Error('Authorization code already used'), { oauth: 'invalid_grant' });
  return issueTokenPair(db, { userId: row.user_id, clientId: row.client_id, scope: row.scope });
}

async function refresh(db, params) {
  const row = await get(db, 'SELECT * FROM oauth_tokens WHERE refresh_hash = ? AND revoked = 0', [hash(params.refresh_token || '')]);
  if (!row) throw Object.assign(new Error('Invalid refresh token'), { oauth: 'invalid_grant' });
  if (params.client_id && params.client_id !== row.client_id) throw Object.assign(new Error('Refresh token client mismatch'), { oauth: 'invalid_grant' });
  const requested = parseScopes(params.scope, row.scope.split(' '));
  const granted = new Set(row.scope.split(' '));
  if (requested.some(scope => !granted.has(scope))) throw Object.assign(new Error('Refresh cannot expand scope'), { oauth: 'invalid_scope' });
  const rotated = await run(db, 'UPDATE oauth_tokens SET revoked = 1 WHERE id = ? AND revoked = 0', [row.id]);
  if (rotated.changes !== 1) throw Object.assign(new Error('Refresh token already used'), { oauth: 'invalid_grant' });
  return issueTokenPair(db, { userId: row.user_id, clientId: row.client_id, scope: requested.join(' ') });
}

async function token(db, params) {
  if (params.grant_type === 'authorization_code') return exchangeCode(db, params);
  if (params.grant_type === 'refresh_token') return refresh(db, params);
  throw Object.assign(new Error('Unsupported grant_type'), { oauth: 'unsupported_grant_type' });
}

async function revoke(db, credential) {
  const value = String(credential || '');
  if (!value) return;
  await run(db, `UPDATE oauth_tokens SET revoked = 1
    WHERE access_hash = ? OR refresh_hash = ?`, [hash(value), hash(value)]);
}

async function authenticateAccessToken(db, bearer) {
  if (!String(bearer).startsWith(ACCESS_PREFIX)) return null;
  const row = await get(db, 'SELECT * FROM oauth_tokens WHERE access_hash = ? AND revoked = 0', [hash(bearer)]);
  if (!row || Date.parse(row.expires_at) <= Date.now()) return null;
  await run(db, 'UPDATE oauth_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE id = ?', [row.id]).catch(() => {});
  const scopes = row.scope.split(' ');
  return {
    userId: row.user_id,
    scope: scopes.includes('kinrows:write') ? 'write' : 'read',
    keyId: null,
    oauthTokenId: row.id,
    keyName: `OAuth client ${row.client_id.slice(0, 20)}`,
    clientId: row.client_id,
    scopes,
    expiresAt: Math.floor(Date.parse(row.expires_at) / 1000),
    authKind: 'oauth',
  };
}

function protectedResourceMetadata(req) {
  const origin = requestOrigin(req);
  return {
    resource: resourceUrl(req),
    authorization_servers: [origin],
    scopes_supported: [...ALLOWED_SCOPES],
    bearer_methods_supported: ['header'],
    resource_name: 'Kinrows household MCP',
  };
}

function authorizationServerMetadata(req) {
  const origin = requestOrigin(req);
  return {
    issuer: origin,
    authorization_endpoint: `${origin}/oauth/authorize`,
    token_endpoint: `${origin}/oauth/token`,
    registration_endpoint: `${origin}/oauth/register`,
    revocation_endpoint: `${origin}/oauth/revoke`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none'],
    scopes_supported: [...ALLOWED_SCOPES],
  };
}

module.exports = {
  ACCESS_PREFIX, REFRESH_PREFIX, requestOrigin, resourceUrl, parseScopes,
  registerClient, authorizationRequest, issueAuthorizationCode, token,
  revoke, authenticateAccessToken, protectedResourceMetadata, authorizationServerMetadata,
};
