// Concierge chat orchestration.
// Runs a capped tool-use loop with Claude over the concierge tool registry,
// persists the user-visible turns, and returns { conversation_id, reply, actions }.

const ai = require('./anthropic');
const tools = require('./conciergeTools');
const push = require('../push');
const { todayISO } = require('./conciergeContext');

const MAX_TURNS = 6;          // safety cap on tool-use round-trips
const HISTORY_LIMIT = 20;     // prior turns replayed for context

function buildSystem(userName, today, memories) {
  const memoryBlock = memories.length
    ? `\n\nThings you remember about this household:\n${memories.map(m => `- ${m.content}`).join('\n')}`
    : '';
  return `You are a warm, capable family life concierge — a personal butler for ${userName || 'the user'} and their household. Today is ${today}.

You help manage the household's calendar, tasks, groceries, budget, pantry, and decisions. Use the provided tools to read real data and take actions on the user's behalf. When the user asks you to add or change something, do it with the tools rather than just describing it.

Guidelines:
- All dates you pass to tools must be YYYY-MM-DD. Resolve relative dates ("tomorrow", "next Tuesday") against today's date above.
- Before completing a task, look it up with list_tasks to get its id.
- Be concise and friendly. Confirm what you did in one short sentence. Don't dump raw data or JSON.
- If a request is ambiguous, ask a brief clarifying question instead of guessing.
- Only use 'remember' for genuinely durable facts, not one-off details.${memoryBlock}`;
}

async function handleChat(db, { userId, userName, message, conversationId }) {
  const today = todayISO();
  const groupId = await db.getUserHouseholdId(userId);

  // Resolve or create the conversation. A supplied id must belong to this user;
  // otherwise reject rather than silently starting a fresh conversation.
  if (conversationId) {
    const convo = await db.getConciergeConversation(conversationId);
    if (!convo || convo.user_id !== userId) {
      const err = new Error('Conversation not found');
      err.status = 404;
      throw err;
    }
  } else {
    const created = await db.createConciergeConversation(userId, groupId);
    conversationId = created.id;
  }

  // Graceful degradation when AI is unavailable.
  if (!ai.isAIEnabled()) {
    const reply = "I need AI to be enabled to chat. Your daily brief still works without it.";
    await db.addConciergeMessage(conversationId, 'user', message);
    await db.addConciergeMessage(conversationId, 'assistant', reply);
    return { conversation_id: conversationId, reply, actions: [] };
  }

  // Replay prior user-visible turns, then the new message.
  const history = await db.getConciergeMessages(conversationId, HISTORY_LIMIT);
  const messages = history.map(m => ({ role: m.role, content: m.content }));
  messages.push({ role: 'user', content: message });
  await db.addConciergeMessage(conversationId, 'user', message);

  const memories = await db.getConciergeMemory(groupId);
  const system = buildSystem(userName, today, memories);
  const ctx = { db, userId, userName, groupId, push, today };
  const toolDefs = tools.definitions();

  const actions = [];
  let reply = '';

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const resp = await ai.callClaudeRaw({ system, messages, tools: toolDefs, maxTokens: 1500 });
    messages.push({ role: 'assistant', content: resp.content });

    if (resp.stop_reason !== 'tool_use') {
      const textBlock = resp.content.find(b => b.type === 'text');
      reply = textBlock ? textBlock.text.trim() : '';
      break;
    }

    // Execute every tool call in this turn, feed results back.
    const toolResults = [];
    for (const block of resp.content) {
      if (block.type !== 'tool_use') continue;
      const out = await tools.run(block.name, ctx, block.input);
      if (out.action) actions.push(out.action);
      toolResults.push({
        type: 'tool_result',
        tool_use_id: block.id,
        content: JSON.stringify(out.result ?? out),
      });
    }
    messages.push({ role: 'user', content: toolResults });
  }

  if (!reply) reply = "Done — let me know if there's anything else.";

  await db.addConciergeMessage(conversationId, 'assistant', reply);
  await db.touchConciergeConversation(conversationId);

  return { conversation_id: conversationId, reply, actions };
}

module.exports = { handleChat };
