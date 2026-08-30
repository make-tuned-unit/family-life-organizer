// Full Kinrows MCP server backed by the official Model Context Protocol SDK.
//
// The SDK serves both the 2026-07-28 protocol and stateless 2025-era clients
// from one registry. Authentication remains in dashboard.js; the validated,
// household-bound principal and request DB handle are passed through AuthInfo.

const { z } = require('zod');
const {
  McpServer,
  ResourceTemplate,
  createMcpHandler,
  fromJsonSchema,
} = require('@modelcontextprotocol/server');
const { toNodeHandler } = require('@modelcontextprotocol/node');
const conciergeTools = require('./conciergeTools');
const developerApi = require('./developerApi');
const { todayISO } = require('./conciergeContext');

const SERVER_NAME = 'kinrows';
const SERVER_VERSION = '2.0.0';
const SNAPSHOT_SECTIONS = [
  'counts', 'tasks', 'appointments', 'decisions', 'pantryExpiring', 'budget',
  'trips', 'choresToday',
];

function jsonText(value) {
  return JSON.stringify(value, null, 2);
}

function resourceResult(uri, value) {
  return {
    contents: [{ uri: uri.href, mimeType: 'application/json', text: jsonText(value) }],
  };
}

function requirePrincipal(authInfo) {
  const principal = authInfo?.extra?.kinrows;
  if (!principal?.auth || !principal?.db) {
    throw new Error('Authenticated Kinrows principal missing from MCP request');
  }
  return principal;
}

function schemaForMcp(definition) {
  const schema = JSON.parse(JSON.stringify(definition.input_schema));
  if (definition.annotations?.destructiveHint) {
    schema.properties ||= {};
    schema.properties.confirm = {
      type: 'boolean',
      description: 'Must be true for delete or cancel actions. Confirm with the user before setting it.',
    };
  }
  return fromJsonSchema(schema);
}

function promptMessage(text) {
  return { messages: [{ role: 'user', content: { type: 'text', text } }] };
}

function createServer(requestContext) {
  const { auth, db } = requirePrincipal(requestContext.authInfo);
  const server = new McpServer({ name: SERVER_NAME, version: SERVER_VERSION }, {
    instructions: [
      'Kinrows manages one household. All data is already restricted to the authenticated user and household.',
      'Read a relevant resource before planning broad changes.',
      'Prefer read actions before updates when an ID is unknown.',
      'Never invent IDs, dates, amounts, people, or completed actions.',
      'Delete and cancel actions require confirm=true after the user confirms.',
      `Today is ${todayISO()}.`,
    ].join(' '),
    cacheHints: {
      'tools/list': { ttlMs: 300000, cacheScope: 'private' },
      'prompts/list': { ttlMs: 300000, cacheScope: 'private' },
      'resources/list': { ttlMs: 300000, cacheScope: 'private' },
      'resources/templates/list': { ttlMs: 300000, cacheScope: 'private' },
      'resources/read': { ttlMs: 0, cacheScope: 'private' },
      'server/discover': { ttlMs: 300000, cacheScope: 'private' },
    },
  });

  for (const definition of conciergeTools.mcpDefinitions()) {
    server.registerTool(definition.name, {
      title: definition.name.replaceAll('_', ' ').replace(/\b\w/g, c => c.toUpperCase()),
      description: definition.description,
      inputSchema: schemaForMcp(definition),
      outputSchema: z.object({ result: z.unknown() }),
      annotations: definition.annotations,
      _meta: { 'kinrows/scope': auth.scope },
    }, async input => {
      const metadata = conciergeTools.operationMetadata(definition.name, input);
      if (metadata.destructive && input.confirm !== true) {
        await developerApi.recordToolAudit(db, auth, {
          transport: 'mcp', name: definition.name, input,
          status: 'confirmation_required', errorCode: 'confirmation_required',
        }).catch(() => {});
        const result = {
          error: `The ${definition.name} action "${input.action}" is destructive. Confirm with the user, then retry with confirm=true.`,
          confirmation_required: true,
        };
        return {
          content: [{ type: 'text', text: jsonText(result) }],
          structuredContent: { result },
          isError: true,
        };
      }

      // `confirm` is protocol-only metadata; underlying handlers never see it.
      const { confirm: _confirm, ...toolInput } = input;
      const out = await developerApi.callTool(db, auth, definition.name, toolInput, { transport: 'mcp' });
      const result = out?.result ?? out;
      const isError = !!(result && typeof result === 'object' && result.error);
      return {
        content: [{ type: 'text', text: typeof result === 'string' ? result : jsonText(result) }],
        structuredContent: { result },
        isError,
      };
    });
  }

  server.registerResource('account', 'kinrows://account/me', {
    title: 'Kinrows account and household identity',
    description: 'The authenticated user, household, API-key scope, tier, and local date/time.',
    mimeType: 'application/json',
    cacheHint: { ttlMs: 0, cacheScope: 'private' },
  }, async uri => resourceResult(uri, await developerApi.whoami(db, auth)));

  server.registerResource('household-snapshot', 'kinrows://household/snapshot', {
    title: 'Current household snapshot',
    description: 'Tasks, calendar, decisions, pantry, budget, trips, and chores used to ground household planning.',
    mimeType: 'application/json',
    cacheHint: { ttlMs: 0, cacheScope: 'private' },
  }, async uri => resourceResult(uri, await developerApi.snapshot(db, auth)));

  server.registerResource('developer-audit', 'kinrows://developer/audit', {
    title: 'Recent agent activity',
    description: 'The last 50 Developer API calls. Inputs and household payloads are never stored in this audit trail.',
    mimeType: 'application/json',
    cacheHint: { ttlMs: 0, cacheScope: 'private' },
  }, async uri => resourceResult(uri, { events: await developerApi.auditLog(db, auth, 50) }));

  server.registerResource('snapshot-section', new ResourceTemplate(
    'kinrows://household/snapshot/{section}',
    {
      list: undefined,
      complete: { section: value => SNAPSHOT_SECTIONS.filter(section => section.startsWith(value)) },
    },
  ), {
    title: 'Household snapshot section',
    description: `Read one snapshot section: ${SNAPSHOT_SECTIONS.join(', ')}.`,
    mimeType: 'application/json',
    cacheHint: { ttlMs: 0, cacheScope: 'private' },
  }, async (uri, variables) => {
    const section = String(variables.section || '');
    if (!SNAPSHOT_SECTIONS.includes(section)) throw new Error(`Unknown snapshot section: ${section}`);
    const snapshot = await developerApi.snapshot(db, auth);
    return resourceResult(uri, { section, value: snapshot[section] ?? null });
  });

  server.registerPrompt('morning-brief', {
    title: 'Morning household brief',
    description: 'Summarize today and highlight conflicts or urgent household work.',
    argsSchema: z.object({ focus: z.string().max(200).optional() }),
  }, ({ focus }) => promptMessage(
    `Read kinrows://household/snapshot. Create a concise morning brief with today's schedule, open tasks, expiring pantry items, active trips, and chores. Highlight conflicts and overdue items.${focus ? ` Give extra attention to: ${focus}.` : ''}`,
  ));

  server.registerPrompt('plan-week', {
    title: 'Plan the household week',
    description: 'Build a practical weekly plan from current Kinrows data.',
    argsSchema: z.object({ priorities: z.string().max(500).optional() }),
  }, ({ priorities }) => promptMessage(
    `Read kinrows://household/snapshot, then propose a seven-day household plan. Surface scheduling conflicts, distribute outstanding work, and leave buffer time.${priorities ? ` Priorities: ${priorities}.` : ''} Do not write changes until the user approves the proposed plan.`,
  ));

  server.registerPrompt('household-check-in', {
    title: 'Household check-in',
    description: 'Prepare a short agenda for a family coordination check-in.',
    argsSchema: z.object({ topic: z.string().max(300).optional() }),
  }, ({ topic }) => promptMessage(
    `Read the household snapshot and prepare a calm check-in agenda covering schedule, tasks, decisions, budget, and upcoming dates.${topic ? ` Center it on: ${topic}.` : ''}`,
  ));

  server.registerPrompt('trip-readiness', {
    title: 'Trip readiness review',
    description: 'Review trip plans, schedule, tasks, and packing lists.',
    argsSchema: z.object({ trip: z.string().max(200).optional() }),
  }, ({ trip }) => promptMessage(
    `Read the household snapshot, then use trip, itinerary, calendar, task, and list read actions to assess readiness${trip ? ` for ${trip}` : ''}. Report gaps before suggesting changes.`,
  ));

  server.registerPrompt('chores-review', {
    title: 'Kids chores review',
    description: 'Review completion, streaks, allowance, and age-appropriate next steps.',
    argsSchema: z.object({ child: z.string().max(100).optional() }),
  }, ({ child }) => promptMessage(
    `Read kinrows://household/snapshot/choresToday and use the routines tool action "chores" as needed${child ? ` for ${child}` : ''}. Summarize progress without shame, including allowance owed and one age-appropriate next step.`,
  ));

  return server;
}

const handler = createMcpHandler(createServer, {
  legacy: 'stateless',
  responseMode: 'auto',
  maxSubscriptions: 100,
  keepAliveMs: 15000,
  onerror: error => console.error('[mcp]', error?.message || error),
});
const nodeHandler = toNodeHandler(handler, {
  onerror: error => console.error('[mcp/node]', error?.message || error),
});
const legacyJsonNodeHandler = toNodeHandler({
  async fetch(request, options) {
    const response = await handler.fetch(request, options);
    if (!String(response.headers.get('content-type') || '').startsWith('text/event-stream')) {
      return response;
    }
    const events = (await response.text()).split(/\r?\n/)
      .filter(line => line.startsWith('data:'))
      .map(line => line.slice(5).trim())
      .filter(Boolean)
      .map(line => JSON.parse(line));
    const headers = new Headers(response.headers);
    headers.set('content-type', 'application/json; charset=utf-8');
    headers.delete('content-length');
    return new Response(JSON.stringify(events.length === 1 ? events[0] : events), {
      status: response.status,
      headers,
    });
  },
}, {
  onerror: error => console.error('[mcp/node-compat]', error?.message || error),
});

function authInfo(req) {
  const authorization = String(req.get('authorization') || '');
  const token = authorization.replace(/^Bearer\s+/i, '');
  const auth = req.apiKeyAuth;
  return {
    token,
    clientId: auth.clientId || `kinrows-api-key-${auth.keyId}`,
    scopes: auth.scopes || (auth.scope === 'write' ? ['kinrows:read', 'kinrows:write'] : ['kinrows:read']),
    ...(auth.expiresAt ? { expiresAt: auth.expiresAt } : {}),
    extra: { kinrows: { auth, db: req.devDb } },
  };
}

async function expressHandler(req, res) {
  // Older Kinrows examples and several lightweight MCP clients send `*/*`.
  // Normalize that legacy default to the Streamable HTTP accept set while the
  // SDK continues to reject genuinely incompatible explicit media types.
  const legacyJson = !req.headers.accept || req.headers.accept === '*/*';
  if (legacyJson) {
    req.headers.accept = 'application/json, text/event-stream';
  }
  req.auth = authInfo(req);
  return (legacyJson ? legacyJsonNodeHandler : nodeHandler)(req, res, req.body);
}

module.exports = { SERVER_NAME, SERVER_VERSION, SNAPSHOT_SECTIONS, createServer, expressHandler, handler };
