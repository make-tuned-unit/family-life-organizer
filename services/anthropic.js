// Shared Anthropic (Claude) client.
// Single place that knows how to talk to the API so every AI feature
// (cook, receipts, concierge) shares one code path and one model default.

const API_URL = 'https://api.anthropic.com/v1/messages';
// Haiku is the only model we run. It is 3x cheaper than Sonnet and ample for
// every feature here (concierge chat, brief, receipts, cook). Do not reintroduce
// Sonnet/Opus — cost is the binding constraint for the $9.99/mo Concierge tier.
const DEFAULT_MODEL = 'claude-haiku-4-5';

function isAIEnabled() {
  return !!process.env.ANTHROPIC_API_KEY;
}

// Marks the stable prefix (tools, then system) with an ephemeral cache breakpoint.
// Render order is tools -> system -> messages, so a breakpoint on the last system
// block caches tools+system together; the per-call volatile part (messages) sits
// after it. Cuts input cost ~90% on the cached prefix across a conversation's turns.
// Verify via usage.cache_read_input_tokens.
function withCacheControl(system, tools) {
  let outTools = tools;
  if (Array.isArray(tools) && tools.length) {
    outTools = tools.map((t, i) =>
      i === tools.length - 1 ? { ...t, cache_control: { type: 'ephemeral' } } : t
    );
  }
  let outSystem = system;
  if (typeof system === 'string' && system.length) {
    outSystem = [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }];
  }
  return { system: outSystem, tools: outTools };
}

// Calls Claude and returns the full response message ({ content, stop_reason, ... }).
// Use this for tool-use loops where the caller inspects content blocks.
// `messages` is the standard Anthropic messages array; `tools` is optional.
async function callClaudeRaw({ messages, system, tools, maxTokens = 2000, model = DEFAULT_MODEL }) {
  if (!isAIEnabled()) throw new Error('ANTHROPIC_API_KEY not set');

  const cached = withCacheControl(system, tools);

  const response = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      ...(cached.system ? { system: cached.system } : {}),
      ...(cached.tools ? { tools: cached.tools } : {}),
      messages
    })
  });

  const data = await response.json();
  if (!response.ok || !Array.isArray(data.content)) {
    throw new Error(data?.error?.message || `Claude API error (${response.status})`);
  }
  return data;
}

// Streaming variant of callClaudeRaw. Forwards text deltas to onText(token) as
// they arrive and returns the fully-reconstructed message ({ content, stop_reason })
// so a tool-use loop can still inspect tool_use blocks. Parses Anthropic's SSE
// event stream (content_block_start/delta/stop, message_delta).
async function streamClaudeRaw({ messages, system, tools, maxTokens = 2000, model = DEFAULT_MODEL, onText }) {
  if (!isAIEnabled()) throw new Error('ANTHROPIC_API_KEY not set');

  const cached = withCacheControl(system, tools);
  const response = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      stream: true,
      ...(cached.system ? { system: cached.system } : {}),
      ...(cached.tools ? { tools: cached.tools } : {}),
      messages
    })
  });

  if (!response.ok || !response.body) {
    let msg = `Claude API error (${response.status})`;
    try { const e = await response.json(); msg = e?.error?.message || msg; } catch { /* keep default */ }
    throw new Error(msg);
  }

  const blocks = [];            // content blocks, by index
  let stopReason = null;
  const decoder = new TextDecoder();
  let buffer = '';

  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let nl;
    while ((nl = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line.startsWith('data:')) continue;     // ignore `event:` lines; data carries its own type
      const payload = line.slice(5).trim();
      if (!payload || payload === '[DONE]') continue;
      let evt;
      try { evt = JSON.parse(payload); } catch { continue; }

      switch (evt.type) {
        case 'content_block_start':
          blocks[evt.index] = evt.content_block.type === 'tool_use'
            ? { type: 'tool_use', id: evt.content_block.id, name: evt.content_block.name, input: {}, _json: '' }
            : { type: 'text', text: '' };
          break;
        case 'content_block_delta': {
          const b = blocks[evt.index];
          if (!b) break;
          if (evt.delta.type === 'text_delta') {
            b.text += evt.delta.text;
            if (onText && evt.delta.text) onText(evt.delta.text);
          } else if (evt.delta.type === 'input_json_delta') {
            b._json += evt.delta.partial_json || '';
          }
          break;
        }
        case 'content_block_stop': {
          const b = blocks[evt.index];
          if (b && b.type === 'tool_use') {
            try { b.input = b._json ? JSON.parse(b._json) : {}; } catch { b.input = {}; }
            delete b._json;
          }
          break;
        }
        case 'message_delta':
          if (evt.delta && evt.delta.stop_reason) stopReason = evt.delta.stop_reason;
          break;
        case 'error':
          // A mid-stream error (e.g. overloaded_error) must not be swallowed —
          // otherwise the caller treats the partial content as a complete turn
          // and reports success. Surface it so the request fails honestly.
          throw new Error(`stream error: ${evt.error?.type || 'unknown'}${evt.error?.message ? ` — ${evt.error.message}` : ''}`);
        default:
          break;
      }
    }
  }

  return { content: blocks.filter(Boolean), stop_reason: stopReason };
}

// Convenience: calls Claude and returns just the assistant's text.
async function callClaude(opts) {
  const data = await callClaudeRaw(opts);
  const textBlock = data.content.find(b => b.type === 'text');
  if (!textBlock) throw new Error('Empty Claude response');
  return textBlock.text;
}

// Pulls the first JSON object out of a model response (models often wrap it in prose).
function extractJSON(text) {
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error('No JSON found in Claude response');
  try {
    return JSON.parse(match[0]);
  } catch {
    throw new Error('Claude response contained invalid JSON');
  }
}

module.exports = { callClaude, callClaudeRaw, streamClaudeRaw, extractJSON, isAIEnabled, DEFAULT_MODEL };
