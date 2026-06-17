// Shared Anthropic (Claude) client.
// Single place that knows how to talk to the API so every AI feature
// (cook, receipts, concierge) shares one code path and one model default.

const API_URL = 'https://api.anthropic.com/v1/messages';
const DEFAULT_MODEL = 'claude-sonnet-4-20250514';

function isAIEnabled() {
  return !!process.env.ANTHROPIC_API_KEY;
}

// Calls Claude and returns the full response message ({ content, stop_reason, ... }).
// Use this for tool-use loops where the caller inspects content blocks.
// `messages` is the standard Anthropic messages array; `tools` is optional.
async function callClaudeRaw({ messages, system, tools, maxTokens = 2000, model = DEFAULT_MODEL }) {
  if (!isAIEnabled()) throw new Error('ANTHROPIC_API_KEY not set');

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
      ...(system ? { system } : {}),
      ...(tools ? { tools } : {}),
      messages
    })
  });

  const data = await response.json();
  if (!response.ok || !Array.isArray(data.content)) {
    throw new Error(data?.error?.message || `Claude API error (${response.status})`);
  }
  return data;
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

module.exports = { callClaude, callClaudeRaw, extractJSON, isAIEnabled, DEFAULT_MODEL };
