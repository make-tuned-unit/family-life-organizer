// Concierge tool registry.
// Each tool exposes an Anthropic tool schema plus a `run(ctx, input)` handler
// that calls existing FamilyDB methods. ctx = { db, userId, userName, groupId, push }.
//
// SAFETY BOUNDARY: tools are read-only or *additive* writes (add / complete /
// remember). No deletes or destructive edits — the butler can't lose data.

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function requireDate(value, field) {
  if (!DATE_RE.test(String(value || ''))) {
    throw new Error(`${field} must be in YYYY-MM-DD format`);
  }
  return value;
}

const TOOLS = [
  // ---- Calendar ----
  {
    name: 'get_calendar',
    description: "List the household's upcoming appointments. Optionally filter by date range (YYYY-MM-DD).",
    write: false,
    input_schema: {
      type: 'object',
      properties: {
        date_from: { type: 'string', description: 'Start date YYYY-MM-DD (optional)' },
        date_to: { type: 'string', description: 'End date YYYY-MM-DD (optional)' },
      },
    },
    async run(ctx, input) {
      const filters = {};
      if (input.date_from) filters.date_from = input.date_from;
      if (input.date_to) filters.date_to = input.date_to;
      const rows = await ctx.db.getAppointments(filters, ctx.userId);
      const result = rows.slice(0, 30).map(a => ({
        id: a.id, title: a.title, date: a.appointment_date,
        time: a.appointment_time, location: a.location, with: a.with_person,
      }));
      return { result };
    },
  },
  {
    name: 'add_appointment',
    description: 'Add an appointment/event to the household calendar. Notifies other household members.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        appointment_date: { type: 'string', description: 'YYYY-MM-DD' },
        appointment_time: { type: 'string', description: 'HH:MM 24h (optional)' },
        location: { type: 'string' },
        with_person: { type: 'string', description: 'Who the appointment is with/for (optional)' },
      },
      required: ['title', 'appointment_date'],
    },
    async run(ctx, input) {
      requireDate(input.appointment_date, 'appointment_date');
      const data = {
        title: input.title,
        appointment_date: input.appointment_date,
        appointment_time: input.appointment_time || null,
        location: input.location || null,
        with_person: input.with_person || null,
        group_id: ctx.groupId,
      };
      await ctx.db.addAppointment(data);
      if (ctx.groupId && ctx.push) {
        const body = `${data.title} on ${data.appointment_date} has been added to your calendar.`;
        ctx.push.pushToGroup(ctx.db, ctx.groupId, ctx.userId, `${ctx.userName} added an event`, body, { type: 'event' });
      }
      const summary = `Added "${data.title}" on ${data.appointment_date}${data.appointment_time ? ' at ' + data.appointment_time : ''}`;
      return { result: { ok: true, summary }, action: { tool: 'add_appointment', summary } };
    },
  },

  // ---- Tasks ----
  {
    name: 'list_tasks',
    description: 'List tasks. status can be "active" (default) or "completed".',
    write: false,
    input_schema: {
      type: 'object',
      properties: { status: { type: 'string', enum: ['active', 'completed'] } },
    },
    async run(ctx, input) {
      const rows = await ctx.db.getTasks({ status: input.status || 'active' }, ctx.userId);
      const result = rows.slice(0, 40).map(t => ({
        id: t.id, title: t.title, due_date: t.due_date, priority: t.priority, assigned_to: t.assigned_to,
      }));
      return { result };
    },
  },
  {
    name: 'add_task',
    description: 'Add a to-do task for the household.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        due_date: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        priority: { type: 'string', enum: ['low', 'medium', 'high'] },
        assigned_to: { type: 'string', description: 'Name of who it is for (optional)' },
        category: { type: 'string' },
      },
      required: ['title'],
    },
    async run(ctx, input) {
      if (input.due_date) requireDate(input.due_date, 'due_date');
      await ctx.db.addTask({
        title: input.title,
        due_date: input.due_date || null,
        priority: input.priority || null,
        assigned_to: input.assigned_to || null,
        category: input.category || 'general',
        status: 'active',
        group_id: ctx.groupId,
      });
      const summary = `Added task "${input.title}"${input.due_date ? ' due ' + input.due_date : ''}`;
      return { result: { ok: true, summary }, action: { tool: 'add_task', summary } };
    },
  },
  {
    name: 'complete_task',
    description: 'Mark a task as completed. Use list_tasks first to get the task id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Task id from list_tasks' } },
      required: ['id'],
    },
    async run(ctx, input) {
      const res = await ctx.db.completeTask(input.id, ctx.groupId);
      if (!res.changed) {
        return { result: { ok: false, error: `No task #${input.id} in this household` } };
      }
      const summary = `Marked task #${input.id} complete`;
      return { result: { ok: true, summary }, action: { tool: 'complete_task', summary } };
    },
  },

  // ---- Groceries ----
  {
    name: 'add_grocery',
    description: 'Add an item to the shared grocery list.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        item: { type: 'string' },
        quantity: { type: 'string', description: 'e.g. "2" or "1 dozen" (optional)' },
        category: { type: 'string' },
      },
      required: ['item'],
    },
    async run(ctx, input) {
      await ctx.db.addGrocery(input.item, input.category || null, input.quantity || '1', ctx.userName, ctx.groupId);
      const summary = `Added ${input.item} to the grocery list`;
      return { result: { ok: true, summary }, action: { tool: 'add_grocery', summary } };
    },
  },

  // ---- Budget & Pantry (read) ----
  {
    name: 'get_budget',
    description: 'Get spending vs. limit by category for a month. month is YYYY-MM (defaults to current month).',
    write: false,
    input_schema: {
      type: 'object',
      properties: { month: { type: 'string', description: 'YYYY-MM (optional)' } },
    },
    async run(ctx, input) {
      const month = input.month || ctx.today.slice(0, 7);
      const rows = await ctx.db.getBudgetSummary(month);
      const result = rows.map(b => ({
        category: b.category, spent: b.spent, limit: b.monthly_limit,
        pct: b.monthly_limit > 0 ? Math.round((b.spent / b.monthly_limit) * 100) : null,
      }));
      return { result: { month, categories: result } };
    },
  },
  {
    name: 'list_pantry',
    description: 'List pantry inventory items, including expiry dates.',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getPantry();
      const result = rows.slice(0, 60).map(p => ({
        id: p.id, item: p.item, quantity: p.quantity, unit: p.unit, expiry: p.expiry_date,
      }));
      return { result };
    },
  },

  // ---- Decisions (read) ----
  {
    name: 'list_decisions',
    description: 'List family decisions/polls. status can be "active" (default) or "closed".',
    write: false,
    input_schema: {
      type: 'object',
      properties: { status: { type: 'string', enum: ['active', 'closed'] } },
    },
    async run(ctx, input) {
      const rows = await ctx.db.getDecisions({ status: input.status || 'active' }, ctx.userId);
      const result = rows.slice(0, 20).map(d => ({
        id: d.id, title: d.title, creator: d.creator_name, options: d.poll_options,
      }));
      return { result };
    },
  },

  // ---- Memory ----
  {
    name: 'remember',
    description: "Save a durable fact about the household for future conversations (e.g. preferences, recurring responsibilities, allergies). Use only for genuinely lasting facts.",
    write: true,
    input_schema: {
      type: 'object',
      properties: { fact: { type: 'string', description: 'The fact to remember, one sentence.' } },
      required: ['fact'],
    },
    async run(ctx, input) {
      await ctx.db.addConciergeMemory(ctx.userId, ctx.groupId, input.fact);
      const summary = `Noted: ${input.fact}`;
      return { result: { ok: true, summary }, action: { tool: 'remember', summary } };
    },
  },
];

const BY_NAME = new Map(TOOLS.map(t => [t.name, t]));

// Anthropic tool definitions (schema only).
function definitions() {
  return TOOLS.map(({ name, description, input_schema }) => ({ name, description, input_schema }));
}

// Run a tool by name; never throws — errors become a result the model can recover from.
async function run(name, ctx, input) {
  const tool = BY_NAME.get(name);
  if (!tool) return { result: { error: `Unknown tool: ${name}` } };
  try {
    return await tool.run(ctx, input || {});
  } catch (err) {
    return { result: { error: err.message } };
  }
}

module.exports = { definitions, run, TOOLS };
