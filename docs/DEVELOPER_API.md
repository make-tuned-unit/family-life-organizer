# Kinrows Developer API — bring your own agent

The Developer API lets a paid household plug **its own AI agent** into Kinrows. Whatever you run — Claude, ChatGPT, a Cursor/Claude Code session, a cron'd script, a home-grown bot — can read and manage the household exactly the way the built-in Concierge does: add tasks, edit lists, log expenses, move appointments, start polls, send family messages, log baby sleep, and so on (100+ actions across ~22 domain tools).

The public, user-facing version of this page is at **https://kinrows.com/developers.html**. This file is the engineering reference.

---

## 1. Concepts

| Term | Meaning |
|---|---|
| **API key** | `kr_live_` + 64 hex chars. Minted in the app (Settings → Account → Developer API). Shown **once**; only its SHA-256 hash is stored. |
| **Scope** | `write` (default) — everything the Concierge can do. `read` — only `get_*`/`list_*`/`analyze_*` handlers; any mutating call is refused. |
| **Household binding** | A key belongs to one user. Every call runs with that user's `userId`/`groupId`, so the same per-handler guards (`assertHousehold`, `assertListAccess`, …) apply. There is no way to address another household. |
| **Entitlement** | Minting a key and every `/v1` request require an active Concierge subscription (Lite or Premium) on the household. Lapse → `402` immediately. Revocation → `401` immediately. |
| **Limits** | 10 active keys per user. 120 requests / minute / key. |

## 2. Managing keys (app session auth)

These use the normal cookie session (what the iPhone app uses). They are how the Settings screen works; you will not normally call them by hand.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/developer/keys` | `{ keys: [{ id, name, key_prefix, scope, last_used_at, created_at }] }` — never includes the plaintext. Premium required. |
| `POST` | `/api/developer/keys` | Body `{ name?, scope?: "read" \| "write" }` → `201 { key, id, name, key_prefix, scope }`. Premium required. `409` at the 10-key cap. |
| `DELETE` | `/api/developer/keys/:id` | Revoke. **Not** premium-gated so a lapsed subscriber can still clean up. `404` if not yours / already revoked. |

## 3. Using a key — the `/v1` surface

Authenticate every request with

```
Authorization: Bearer kr_live_…
```

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/me` | Who the key is: `{ user, household, key: {id,name,scope}, tier, today, now_time }`. Good first call / health check. |
| `GET` | `/v1/snapshot` | The household digest the Concierge daily brief is built from (today's tasks, appointments, open polls, pantry expiring, budget, trips, …). Feed it to your agent as context. |
| `GET` | `/v1/tools` | Tool catalog. Default is Anthropic shape (`name`, `description`, `input_schema`). `?format=openai` returns `{type:"function", function:{name, description, parameters}}`. Pass straight into your model's `tools` parameter. |
| `POST` | `/v1/tools/:name` | Call a tool. Body is the tool's input, e.g. `{"action":"add","title":"Book dentist"}`. `200 {result}` · `400 {error}` (bad action / missing fields / handler error) · `403` (read-only key attempting a write). |
| `POST` | `/v1/mcp` | **MCP server** (Streamable HTTP, stateless JSON-RPC 2.0). Supports `initialize`, `ping`, `tools/list`, `tools/call`; notifications get `202`; batches supported. `GET` → `405`, `DELETE` → `204`. |

Error statuses across `/v1`: `401` missing/invalid/revoked key · `402` no active subscription · `429` rate limited · `404` unknown route.

### 3.1 Tool catalog shape

Tools are grouped by domain, each with an `action` enum — `calendar`, `tasks`, `lists`, `budget`, `pantry`, `decisions`, `trips`, `itineraries`, `rivalries`, `gifts`, `coverage`, `notes`, `routines`, `people`, `contacts`, `recurring_payments`, `projects`, `feed`, `special_events` — plus four standalone tools: `get_addresses`, `remember`, `update_my_name`, `send_message`. The catalog is generated from `services/conciergeTools.js`, so it is always identical to what the in-app Concierge sees. Read-only classification (`isReadOnly`) is by handler name prefix: `get_`, `list_`, `analyze_`.

### 3.2 Examples

```bash
# Who am I?
curl -s https://family-life-organizer-production.up.railway.app/v1/me -H "Authorization: Bearer $KINROWS_KEY"

# Add a task
curl -s https://family-life-organizer-production.up.railway.app/v1/tools/tasks \
  -H "Authorization: Bearer $KINROWS_KEY" -H "Content-Type: application/json" \
  -d '{"action":"add","title":"Book dentist","due_date":"2026-09-02"}'

# Log an expense
curl -s https://family-life-organizer-production.up.railway.app/v1/tools/budget \
  -H "Authorization: Bearer $KINROWS_KEY" -H "Content-Type: application/json" \
  -d '{"action":"log_expense","amount":42.10,"merchant":"Costco","category":"Groceries"}'
```

> Base URL is the prod API host from `FamilyLife/App/AppConfig.swift` (`http://localhost:3456` in dev). If the API is ever fronted by a kinrows.com hostname, update this doc and `website/developers.html` together.

**Claude / Claude Code / Cursor (MCP):**

```json
{
  "mcpServers": {
    "kinrows": {
      "url": "https://family-life-organizer-production.up.railway.app/v1/mcp",
      "headers": { "Authorization": "Bearer kr_live_…" }
    }
  }
}
```

**Anthropic Messages API, hand-rolled loop:**

```js
const KEY = process.env.KINROWS_KEY;
const H = { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };
const { tools } = await (await fetch('https://family-life-organizer-production.up.railway.app/v1/tools', { headers: H })).json();
const snapshot = await (await fetch('https://family-life-organizer-production.up.railway.app/v1/snapshot', { headers: H })).json();

let messages = [{ role: 'user', content: `Household snapshot: ${JSON.stringify(snapshot)}\n\nMove the dentist task to Friday and add milk to Groceries.` }];
for (;;) {
  const r = await anthropic.messages.create({ model: 'claude-sonnet-5', max_tokens: 1024, tools, messages });
  messages.push({ role: 'assistant', content: r.content });
  if (r.stop_reason !== 'tool_use') break;
  const results = [];
  for (const b of r.content.filter(c => c.type === 'tool_use')) {
    const out = await (await fetch(`https://family-life-organizer-production.up.railway.app/v1/tools/${b.name}`, { method: 'POST', headers: H, body: JSON.stringify(b.input) })).json();
    results.push({ type: 'tool_result', tool_use_id: b.id, content: JSON.stringify(out) });
  }
  messages.push({ role: 'user', content: results });
}
```

## 4. Security notes (keep `docs/SECURITY_AUDIT.md` in sync)

- Keys are opaque 256-bit random values, hashed (SHA-256) at rest in `api_keys.key_hash`; only `key_prefix` (first 16 chars) is displayed afterwards.
- The bearer middleware (`requireApiKey` in `dashboard.js`) re-checks the household's subscription on **every** request and stamps `last_used_at`.
- The rate limiter buckets on a hash of the bearer, never the raw key, so a guessed/bad key cannot collide with a real key's bucket.
- `/v1` never touches the cookie session; a key cannot be used to log in, change the password/email, or delete the account — those routes live only under `/api` with session auth.
- Deleting the account cascades `api_keys` (FK `ON DELETE CASCADE`).
- Tool calls run with `ctx.source = 'developer_api'` should any handler ever need to distinguish agent traffic.

## 5. Code map

- `schema.sql` — `api_keys` table.
- `services/developerApi.js` — key mint/list/revoke, bearer auth, scope check, catalog formats, MCP JSON-RPC.
- `services/conciergeTools.js` — `isReadOnly(name, input)` export.
- `dashboard.js` — `/api/developer/keys*`, `app.use('/v1', developerLimiter, requireApiKey)`, `/v1/*` routes, `/developers` website route.
- `FamilyLife/Views/Home/DeveloperAPIView.swift` + `APIService.fetch/create/revokeDeveloperKey` — Settings → Account → Developer API.
- `test/developer-api.test.js` — 7 tests (port 3988).
- `website/developers.html` — public docs.
