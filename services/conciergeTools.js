// Concierge tool registry.
// Each tool exposes an Anthropic tool schema plus a `run(ctx, input)` handler
// that calls existing FamilyDB methods. ctx = { db, userId, userName, groupId, push }.
//
// SAFETY BOUNDARY: tools provide full CRUD — read, add, edit, AND delete — across
// every domain so the butler can manage the app on the user's behalf. The DB
// delete/update methods are NOT all household-scoped, so every mutate/delete that
// targets a row by id FIRST verifies the row belongs to the caller's household
// (assertHousehold / assertListAccess). Notes are owner-scoped at the DB layer.
// This prevents the model from being talked into touching another household's data.

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function requireDate(value, field) {
  const s = String(value || '');
  if (!DATE_RE.test(s)) {
    throw new Error(`${field} must be in YYYY-MM-DD format`);
  }
  // Shape isn't enough — reject impossible calendar dates (e.g. 2026-13-45),
  // which would silently drop out of strftime('%Y-%m') budget rollups.
  const [y, m, d] = s.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
    throw new Error(`${field} is not a real calendar date`);
  }
  return value;
}

// Promise wrapper over the raw sqlite handle for ownership checks.
function dbGet(ctx, sql, params) {
  return new Promise((resolve, reject) => {
    ctx.db.db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
  });
}

// Guard for group_id-scoped tables (appointments, itineraries, trips, pantry,
// decisions, receipts, gift_people, gift_ideas, …). Throws unless the row exists
// and belongs to the caller's household. `table` is always an internal literal.
async function assertHousehold(ctx, table, id) {
  const row = await dbGet(ctx, `SELECT group_id FROM ${table} WHERE id = ?`, [id]);
  if (!row) throw new Error(`No ${table} #${id} found`);
  if (ctx.groupId == null || row.group_id !== ctx.groupId) {
    throw new Error(`#${id} is not in your household`);
  }
}

// Guard for lists (no group_id column — visible to creator + household members).
async function assertListAccess(ctx, listId) {
  const row = await dbGet(ctx,
    `SELECT 1 AS ok FROM lists l WHERE l.id = ? AND (
       l.created_by = ?
       OR EXISTS (SELECT 1 FROM group_members gm JOIN groups g ON g.id = gm.group_id
                  AND g.group_type = 'household'
                  WHERE gm.user_id = l.created_by AND gm.group_id IN (
                    SELECT group_id FROM group_members WHERE user_id = ?)))`,
    [listId, ctx.userId, ctx.userId]);
  if (!row) throw new Error(`No list #${listId} in your household`);
}

// Guard for contacts (owner-scoped by added_by, no group_id column).
async function assertContactOwner(ctx, id) {
  const row = await dbGet(ctx, 'SELECT added_by FROM contacts WHERE id = ?', [id]);
  if (!row) throw new Error(`No contact #${id} found`);
  if (row.added_by !== ctx.userId) throw new Error(`Contact #${id} is not yours`);
}

// Names that should be created as grocery-type (checklist) lists.
const GROCERY_LIST_NAMES = new Set(['groceries', 'grocery', 'costco', 'walmart', 'superstore', 'sobeys', 'loblaws', 'market']);
const TASKS_ALIASES = new Set(['task', 'tasks', 'to-do', 'todo', 'to do', 'todos']);

// Resolve a household list by NAME (case-insensitive). The reserved "Tasks" list
// is backed by the tasks table, so it returns { reserved: 'tasks' }. The iOS app
// shows the Lists feature (lists/list_items); the legacy `groceries` table is not
// surfaced, so everything routes through Lists here.
async function resolveListByName(ctx, name, { create = false } = {}) {
  const target = String(name || '').trim().toLowerCase();
  if (!target) return null;
  if (TASKS_ALIASES.has(target)) return { reserved: 'tasks', name: 'Tasks' };
  const lists = await ctx.db.getLists(ctx.userId);
  let list = lists.find(l => (l.name || '').trim().toLowerCase() === target)
    || lists.find(l => (l.name || '').trim().toLowerCase().includes(target))
    || null;
  if (!list && create) {
    const properName = String(name).trim();
    const list_type = GROCERY_LIST_NAMES.has(target) ? 'grocery' : 'standard';
    const { id } = await ctx.db.createList({
      name: properName, icon: list_type === 'grocery' ? 'cart' : 'list.bullet',
      list_type, created_by: ctx.userId,
    });
    list = { id, name: properName, list_type };
  }
  return list;
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
        with_person: { type: 'string', description: 'Who the event is with / invited / attending, e.g. "Sophie" (optional)' },
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
        created_by: ctx.userId,
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

  // ---- Lists (any named list: Groceries, Costco, shopping/to-do lists, …) ----
  {
    name: 'get_lists',
    description: 'List the household\'s lists by name (e.g. Groceries, Costco) so you can pick the right one before adding/reading items. The "Tasks" list is also available by name.',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const lists = await ctx.db.getLists(ctx.userId);
      const result = lists.map(l => ({ name: l.name, type: l.list_type || 'standard', items: l.active_count }));
      result.unshift({ name: 'Tasks', type: 'tasks' });
      return { result };
    },
  },
  {
    name: 'add_list_item',
    description: 'Add an item to a named list (Groceries, Costco, any shopping or to-do list). Identify the list by its name; it is created if it does not exist. Use the name "Tasks" to add a household task.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        list: { type: 'string', description: 'List name, e.g. "Groceries", "Costco", "Tasks"' },
        item: { type: 'string', description: 'The item or task to add' },
        quantity: { type: 'string', description: 'e.g. "2" or "1 dozen" (optional)' },
        category: { type: 'string' },
      },
      required: ['list', 'item'],
    },
    async run(ctx, input) {
      const list = await resolveListByName(ctx, input.list, { create: true });
      if (list && list.reserved === 'tasks') {
        await ctx.db.addTask({ title: input.item, category: input.category || 'general', status: 'active', group_id: ctx.groupId });
        const summary = `Added task "${input.item}"`;
        return { result: { ok: true, summary }, action: { tool: 'add_list_item', summary } };
      }
      if (!list) throw new Error(`Could not find or create a list named "${input.list}"`);
      const qty = input.quantity && String(input.quantity).trim() && String(input.quantity).trim() !== '1'
        ? ` (${String(input.quantity).trim()})` : '';
      await ctx.db.addListItem({ list_id: list.id, title: `${input.item}${qty}`, added_by: ctx.userName, category: input.category || null });
      const summary = `Added ${input.item} to ${list.name}`;
      return { result: { ok: true, summary }, action: { tool: 'add_list_item', summary } };
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
      const rows = await ctx.db.getBudgetSummary(month, ctx.groupId);
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
      const rows = await ctx.db.getPantry({}, ctx.groupId);
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

  // ---- Lists (read / check off) ----
  {
    name: 'get_list',
    description: 'Show items on a named list (Groceries, Costco, etc.). status "needed" (default, unchecked) or "purchased" (checked off). Use the name "Tasks" to read tasks.',
    write: false,
    input_schema: {
      type: 'object',
      properties: {
        list: { type: 'string', description: 'List name' },
        status: { type: 'string', enum: ['needed', 'purchased'] },
      },
      required: ['list'],
    },
    async run(ctx, input) {
      const list = await resolveListByName(ctx, input.list);
      const wantDone = (input.status || 'needed') === 'purchased';
      if (list && list.reserved === 'tasks') {
        const rows = await ctx.db.getTasks({ status: wantDone ? 'completed' : 'active' }, ctx.userId);
        return { result: rows.slice(0, 60).map(t => ({ id: t.id, item: t.title })) };
      }
      if (!list) return { result: [] };
      const items = await ctx.db.getListItems(list.id);
      return { result: items.filter(i => !!i.is_done === wantDone).slice(0, 60).map(i => ({ id: i.id, item: i.title, category: i.category })) };
    },
  },
  {
    name: 'check_off_item',
    description: 'Check off / complete an item on a named list. Use get_list first to get the id. Use the name "Tasks" to complete a task.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        list: { type: 'string', description: 'The list the item is on' },
        id: { type: 'integer', description: 'Item id from get_list' },
      },
      required: ['list', 'id'],
    },
    async run(ctx, input) {
      const list = await resolveListByName(ctx, input.list);
      if (list && list.reserved === 'tasks') {
        const r = await ctx.db.completeTask(input.id, ctx.groupId);
        if (!r.changed) return { result: { ok: false, error: `No task #${input.id} in this household` } };
        const summary = `Marked task #${input.id} complete`;
        return { result: { ok: true, summary }, action: { tool: 'check_off_item', summary } };
      }
      const item = await dbGet(ctx, 'SELECT id, list_id, is_done FROM list_items WHERE id = ?', [input.id]);
      if (!item) throw new Error(`No list item #${input.id} found`);
      await assertListAccess(ctx, item.list_id);
      if (!item.is_done) await ctx.db.toggleListItem(input.id);
      const summary = `Checked off item #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'check_off_item', summary } };
    },
  },

  // ---- Pantry (add) ----
  {
    name: 'add_pantry_item',
    description: 'Add an item to the pantry inventory.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        item: { type: 'string' },
        quantity: { type: 'string' },
        unit: { type: 'string' },
        category: { type: 'string' },
        location: { type: 'string', description: 'e.g. pantry, fridge, freezer' },
        expiry_date: { type: 'string', description: 'YYYY-MM-DD (optional)' },
      },
      required: ['item'],
    },
    async run(ctx, input) {
      if (input.expiry_date) requireDate(input.expiry_date, 'expiry_date');
      await ctx.db.addPantryItem({
        item: input.item, quantity: input.quantity || '1', unit: input.unit || null,
        category: input.category || null, location: input.location || 'pantry',
        expiry_date: input.expiry_date || null, added_by: ctx.userName,
        group_id: ctx.groupId,
      });
      const summary = `Added ${input.item} to the pantry`;
      return { result: { ok: true, summary }, action: { tool: 'add_pantry_item', summary } };
    },
  },

  // ---- Decisions (vote / comment) ----
  {
    name: 'vote_decision',
    description: "Cast or change your vote on a poll decision. Use list_decisions for the id and the exact option text.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Decision id' },
        choice: { type: 'string', description: 'Poll option to vote for (must match one of the decision options)' },
      },
      required: ['id', 'choice'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'decisions', input.id);
      await ctx.db.replaceDecisionReaction(input.id, ctx.userName, 'vote', input.choice);
      const summary = `Voted "${input.choice}" on decision #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'vote_decision', summary } };
    },
  },
  {
    name: 'comment_decision',
    description: 'Add a comment to a family decision/poll.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer' }, text: { type: 'string' } },
      required: ['id', 'text'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'decisions', input.id);
      await ctx.db.addDecisionComment(input.id, ctx.userName, input.text);
      const summary = `Commented on decision #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'comment_decision', summary } };
    },
  },

  // ---- Trips (live location / ETA shares) ----
  {
    name: 'get_trips',
    description: 'List trips (live location + ETA shares). status: "active" (default), "arrived", or "cancelled".',
    write: false,
    input_schema: {
      type: 'object',
      properties: {
        status: { type: 'string', enum: ['active', 'arrived', 'cancelled'] },
        traveler: { type: 'string' },
      },
    },
    async run(ctx, input) {
      const filters = {};
      if (input.status) filters.status = input.status;
      if (input.traveler) filters.traveler = input.traveler;
      const rows = await ctx.db.getTrips(filters, ctx.groupId);
      return { result: rows.slice(0, 30).map(t => ({
        id: t.id, traveler: t.traveler, origin: t.origin, destination: t.destination,
        purpose: t.purpose, status: t.status, eta_minutes: t.eta_minutes, arrived_at: t.arrived_at,
      })) };
    },
  },
  {
    name: 'add_trip',
    description: 'Start a trip for a household member (shares departure + ETA).',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        traveler: { type: 'string' },
        destination: { type: 'string' },
        origin: { type: 'string' },
        purpose: { type: 'string' },
        eta_minutes: { type: 'integer' },
      },
      required: ['traveler', 'destination'],
    },
    async run(ctx, input) {
      await ctx.db.createTrip({
        traveler: input.traveler, origin: input.origin || null, destination: input.destination,
        purpose: input.purpose || null, eta_minutes: input.eta_minutes || null,
        group_id: ctx.groupId,
      });
      const summary = `Started ${input.traveler}'s trip to ${input.destination}`;
      return { result: { ok: true, summary }, action: { tool: 'add_trip', summary } };
    },
  },
  {
    name: 'arrive_trip',
    description: 'Mark a trip as arrived. Use get_trips for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'trips', input.id);
      await ctx.db.arriveTrip(input.id);
      const summary = `Marked trip #${input.id} as arrived`;
      return { result: { ok: true, summary }, action: { tool: 'arrive_trip', summary } };
    },
  },
  {
    name: 'cancel_trip',
    description: 'Cancel an active trip. Use get_trips for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'trips', input.id);
      await ctx.db.cancelTrip(input.id);
      const summary = `Cancelled trip #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'cancel_trip', summary } };
    },
  },

  // ---- Itineraries (multi-day trips with stays) ----
  {
    name: 'get_itineraries',
    description: 'List the household\'s trips/itineraries (multi-day plans with stays and hosts).',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getItineraries(ctx.userId);
      return { result: rows.slice(0, 30).map(i => ({
        id: i.id, title: i.title, traveler: i.traveler_name, start_date: i.start_date,
        end_date: i.end_date, travelers: i.travelers, status: i.status, notes: i.notes,
      })) };
    },
  },
  {
    name: 'get_itinerary_stays',
    description: 'List the stays (accommodations) within an itinerary. Use get_itineraries for the id.',
    write: false,
    input_schema: {
      type: 'object',
      properties: { itinerary_id: { type: 'integer' } },
      required: ['itinerary_id'],
    },
    async run(ctx, input) {
      // Scope to the caller's household — the parent itinerary must belong to it
      // before its stays (host addresses, dates) can be read.
      await assertHousehold(ctx, 'itineraries', input.itinerary_id);
      const rows = await ctx.db.getItineraryStays(input.itinerary_id);
      return { result: rows.map(s => ({
        id: s.id, check_in: s.check_in, check_out: s.check_out, host: s.host_name,
        location: s.location_name, address: s.address, status: s.status, notes: s.notes,
      })) };
    },
  },
  {
    name: 'add_itinerary',
    description: 'Create a new trip/itinerary for the household.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        travelers: { type: 'string', description: 'Who is going (optional)' },
        notes: { type: 'string' },
      },
      required: ['title', 'start_date', 'end_date'],
    },
    async run(ctx, input) {
      requireDate(input.start_date, 'start_date');
      requireDate(input.end_date, 'end_date');
      const r = await ctx.db.createItinerary({
        title: input.title, traveler_id: ctx.userId, traveler_name: ctx.userName,
        start_date: input.start_date, end_date: input.end_date,
        travelers: input.travelers || null, notes: input.notes || null,
        status: 'planning', group_id: ctx.groupId,
      });
      const summary = `Created itinerary "${input.title}" (${input.start_date}–${input.end_date})`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_itinerary', summary } };
    },
  },
  {
    name: 'update_itinerary',
    description: 'Update an itinerary (title, dates, travelers, notes, status). Use get_itineraries for the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        title: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        travelers: { type: 'string' },
        notes: { type: 'string' },
        status: { type: 'string', enum: ['planning', 'booked', 'active', 'completed'] },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'itineraries', input.id);
      const updates = {};
      for (const k of ['title', 'start_date', 'end_date', 'travelers', 'notes', 'status']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.start_date) requireDate(updates.start_date, 'start_date');
      if (updates.end_date) requireDate(updates.end_date, 'end_date');
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateItinerary(input.id, updates);
      const summary = `Updated itinerary #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_itinerary', summary } };
    },
  },
  {
    name: 'add_itinerary_stay',
    description: 'Add a stay (accommodation) to an itinerary. Use get_itineraries for the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        itinerary_id: { type: 'integer' },
        check_in: { type: 'string', description: 'YYYY-MM-DD' },
        check_out: { type: 'string', description: 'YYYY-MM-DD' },
        host_name: { type: 'string' },
        location_name: { type: 'string' },
        address: { type: 'string' },
        notes: { type: 'string' },
      },
      required: ['itinerary_id', 'check_in', 'check_out'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'itineraries', input.itinerary_id);
      requireDate(input.check_in, 'check_in');
      requireDate(input.check_out, 'check_out');
      await ctx.db.addItineraryStay({
        itinerary_id: input.itinerary_id, check_in: input.check_in, check_out: input.check_out,
        host_name: input.host_name || null, location_name: input.location_name || null,
        address: input.address || null, notes: input.notes || null, status: 'planned',
      });
      const summary = `Added a stay to itinerary #${input.itinerary_id}`;
      return { result: { ok: true, summary }, action: { tool: 'add_itinerary_stay', summary } };
    },
  },

  // ---- Rivalries (competitions) ----
  {
    name: 'get_rivalries',
    description: 'List family rivalries/competitions with current scores. status: "active" (default) or "completed".',
    write: false,
    input_schema: {
      type: 'object',
      properties: { status: { type: 'string', enum: ['active', 'completed'] } },
    },
    async run(ctx, input) {
      const filters = {};
      if (input.status) filters.status = input.status;
      const rows = (await ctx.db.getRivalries(filters, ctx.userId)).slice(0, 20);
      // Batch-load all score totals in one query instead of one per rivalry (N+1).
      let totalsByRivalry = new Map();
      try {
        totalsByRivalry = await ctx.db.getRivalryEntryTotalsBatch(rows.map(r => r.id));
      } catch { /* ignore — totals are best-effort */ }
      const out = rows.map(r => ({
        id: r.id, title: r.title, type: r.challenge_type, status: r.status,
        start_date: r.start_date, end_date: r.end_date,
        totals: (totalsByRivalry.get(r.id) || []).map(t => ({ member: t.member_name, total: t.total })),
      }));
      return { result: out };
    },
  },
  {
    name: 'log_rivalry_score',
    description: 'Log a score/entry for a participant in a rivalry. Use get_rivalries for the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        rivalry_id: { type: 'integer' },
        member_name: { type: 'string', description: 'Participant name (defaults to you)' },
        value: { type: 'number' },
        note: { type: 'string' },
      },
      required: ['rivalry_id', 'value'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'rivalries', input.rivalry_id);
      const member = input.member_name || ctx.userName;
      await ctx.db.addRivalryEntry({
        rivalry_id: input.rivalry_id, member_name: member, value: input.value, note: input.note || null,
      });
      const summary = `Logged ${input.value} for ${member} in rivalry #${input.rivalry_id}`;
      return { result: { ok: true, summary }, action: { tool: 'log_rivalry_score', summary } };
    },
  },

  // ---- Gifts ----
  {
    name: 'get_gift_people',
    description: 'List people tracked for gifts, with birthdays/anniversaries.',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getGiftPeople(ctx.groupId);
      return { result: rows.map(p => ({
        id: p.id, name: p.name, relationship: p.relationship, birthday: p.birthday, anniversary: p.anniversary,
      })) };
    },
  },
  {
    name: 'add_gift_person',
    description: 'Track a new person for gift ideas.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        relationship: { type: 'string' },
        birthday: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        anniversary: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        notes: { type: 'string' },
      },
      required: ['name'],
    },
    async run(ctx, input) {
      if (input.birthday) requireDate(input.birthday, 'birthday');
      if (input.anniversary) requireDate(input.anniversary, 'anniversary');
      await ctx.db.addGiftPerson({
        name: input.name, relationship: input.relationship || null,
        birthday: input.birthday || null, anniversary: input.anniversary || null, notes: input.notes || null,
        group_id: ctx.groupId,
      });
      const summary = `Now tracking ${input.name} for gifts`;
      return { result: { ok: true, summary }, action: { tool: 'add_gift_person', summary } };
    },
  },
  {
    name: 'get_gift_ideas',
    description: 'List gift ideas, optionally for one person (use get_gift_people for person_id).',
    write: false,
    input_schema: {
      type: 'object',
      properties: { person_id: { type: 'integer' } },
    },
    async run(ctx, input) {
      const rows = await ctx.db.getGiftIdeas(input.person_id || null, ctx.groupId);
      return { result: rows.map(g => ({
        id: g.id, person_id: g.person_id, title: g.title, price: g.estimated_price,
        status: g.status, for_event: g.for_event, link: g.link_url,
      })) };
    },
  },
  {
    name: 'add_gift_idea',
    description: 'Add a gift idea for a tracked person. Use get_gift_people for person_id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        person_id: { type: 'integer' },
        title: { type: 'string' },
        notes: { type: 'string' },
        link_url: { type: 'string' },
        estimated_price: { type: 'number' },
        for_event: { type: 'string' },
      },
      required: ['person_id', 'title'],
    },
    async run(ctx, input) {
      await ctx.db.addGiftIdea({
        person_id: input.person_id, title: input.title, notes: input.notes || null,
        link_url: input.link_url || null, estimated_price: input.estimated_price || null,
        status: 'idea', for_event: input.for_event || null,
        group_id: ctx.groupId,
      });
      const summary = `Added gift idea "${input.title}"`;
      return { result: { ok: true, summary }, action: { tool: 'add_gift_idea', summary } };
    },
  },

  // ---- Coverage & Addresses (read) ----
  {
    name: 'get_coverage',
    description: 'List childcare/coverage requests where you are being asked to help (incoming).',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getIncomingCoverageRequests(ctx.userId);
      return { result: rows.map(c => ({
        id: c.id, reason: c.reason, note: c.note, from: c.requester_name, status: c.recipient_status,
      })) };
    },
  },
  {
    name: 'get_addresses',
    description: 'List saved family addresses/places (home, work, school, etc.).',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getFamilyAddresses(ctx.groupId);
      return { result: rows.map(a => ({ id: a.id, name: a.name, address: a.address })) };
    },
  },

  // ---- Memory ----
  {
    name: 'remember',
    description: "Save a durable fact about the household for future conversations (e.g. preferences, recurring responsibilities, allergies). Use only for genuinely lasting facts. This is NOT for taking notes — when the user asks to take/jot/write a note, use add_note.",
    write: true,
    input_schema: {
      type: 'object',
      properties: { fact: { type: 'string', description: 'The fact to remember, one sentence.' } },
      required: ['fact'],
    },
    async run(ctx, input) {
      // Cap length and strip control chars — stored notes are replayed into the
      // system prompt of every future session, so bound what can be persisted.
      const fact = String(input.fact || '').replace(/[\x00-\x1f]/g, ' ').trim().slice(0, 500);
      if (!fact) return { result: { ok: false, summary: 'Nothing to remember.' } };
      await ctx.db.addConciergeMemory(ctx.userId, ctx.groupId, fact);
      const summary = `Noted: ${fact}`;
      return { result: { ok: true, summary }, action: { tool: 'remember', summary } };
    },
  },

  // ---- Calendar (edit / delete) ----
  {
    name: 'update_appointment',
    description: 'Edit an existing calendar event. Use get_calendar first to get the id. Only pass the fields you want to change.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        title: { type: 'string' },
        appointment_date: { type: 'string', description: 'YYYY-MM-DD' },
        appointment_time: { type: 'string', description: 'HH:MM 24h' },
        location: { type: 'string' },
        with_person: { type: 'string', description: 'Who the event is with / invited / attending, e.g. "Sophie"' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'appointments', input.id);
      const updates = {};
      for (const k of ['title', 'appointment_date', 'appointment_time', 'location', 'with_person']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.appointment_date) requireDate(updates.appointment_date, 'appointment_date');
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateAppointment(input.id, updates);
      const summary = `Updated event #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_appointment', summary } };
    },
  },
  {
    name: 'delete_appointment',
    description: 'Delete a calendar event permanently. Use get_calendar first to confirm the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'appointments', input.id);
      await ctx.db.deleteAppointment(input.id);
      const summary = `Deleted event #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_appointment', summary } };
    },
  },

  // ---- Notes ----
  {
    name: 'list_notes',
    description: "List the user's notes (their own + notes shared with the household).",
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getNotes(ctx.userId);
      return { result: rows.slice(0, 50).map(n => ({
        id: n.id, title: n.title, preview: (n.body || '').slice(0, 100),
        shared: n.shared_scope && n.shared_scope !== 'private', author: n.author_name,
      })) };
    },
  },
  {
    name: 'add_note',
    description: 'Take/jot/save a note in the Notes feature — the default tool whenever the user says "take a note", "make a note", "jot down", or "write down". Private to the user by default; set shared=true to share it with the household. (Not for memory or the activity feed.)',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        body: { type: 'string' },
        shared: { type: 'boolean', description: 'Share with the household (default false)' },
      },
      required: ['body'],
    },
    async run(ctx, input) {
      const r = await ctx.db.addNote({
        title: input.title || null, body: input.body, user_id: ctx.userId,
        shared_scope: input.shared ? 'household' : 'private',
        group_id: input.shared ? ctx.groupId : null,
      });
      const summary = `Added note${input.title ? ` "${input.title}"` : ''}`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_note', summary } };
    },
  },
  {
    name: 'update_note',
    description: "Edit one of your own notes. Use list_notes for the id. Only pass fields to change.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        title: { type: 'string' },
        body: { type: 'string' },
        shared: { type: 'boolean', description: 'Share with household (true) or make private (false)' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      const updates = {};
      if (input.title != null) updates.title = input.title;
      if (input.body != null) updates.body = input.body;
      if (input.shared != null) {
        updates.shared_scope = input.shared ? 'household' : 'private';
        updates.group_id = input.shared ? ctx.groupId : null;
      }
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      const res = await ctx.db.updateNote(input.id, updates, ctx.userId);
      if (!res.changed) return { result: { ok: false, error: `No note #${input.id} you own` } };
      const summary = `Updated note #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_note', summary } };
    },
  },
  {
    name: 'delete_note',
    description: 'Delete one of your own notes permanently. Use list_notes for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      const res = await ctx.db.deleteNote(input.id, ctx.userId);
      if (!res.changed) return { result: { ok: false, error: `No note #${input.id} you own` } };
      const summary = `Deleted note #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_note', summary } };
    },
  },

  // (Legacy id-based list tools removed — superseded by the name-based
  // get_lists/add_list_item/get_list/check_off_item tools above. Their duplicate
  // add_list_item was causing an Anthropic 400 that broke all concierge chat.)

  // ---- Itineraries (delete + stay edit/delete; create/update already above) ----
  {
    name: 'delete_itinerary',
    description: 'Delete a trip/itinerary permanently. Use get_itineraries for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'itineraries', input.id);
      await ctx.db.deleteItinerary(input.id);
      const summary = `Deleted itinerary #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_itinerary', summary } };
    },
  },
  {
    name: 'update_itinerary_stay',
    description: 'Edit a stay within an itinerary. Use get_itinerary_stays for the stay id and pass its itinerary_id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Stay id' },
        itinerary_id: { type: 'integer' },
        check_in: { type: 'string', description: 'YYYY-MM-DD' },
        check_out: { type: 'string', description: 'YYYY-MM-DD' },
        host_name: { type: 'string' },
        location_name: { type: 'string' },
        address: { type: 'string' },
        notes: { type: 'string' },
      },
      required: ['id', 'itinerary_id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'itineraries', input.itinerary_id);
      const updates = {};
      for (const k of ['check_in', 'check_out', 'host_name', 'location_name', 'address', 'notes']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.check_in) requireDate(updates.check_in, 'check_in');
      if (updates.check_out) requireDate(updates.check_out, 'check_out');
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateItineraryStay(input.id, updates, input.itinerary_id);
      const summary = `Updated stay #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_itinerary_stay', summary } };
    },
  },
  {
    name: 'delete_itinerary_stay',
    description: 'Delete a stay from an itinerary. Use get_itinerary_stays for the stay id and pass its itinerary_id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer' }, itinerary_id: { type: 'integer' } },
      required: ['id', 'itinerary_id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'itineraries', input.itinerary_id);
      await ctx.db.deleteItineraryStay(input.id, input.itinerary_id);
      const summary = `Deleted stay #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_itinerary_stay', summary } };
    },
  },

  // ---- Trips (edit) ----
  {
    name: 'update_trip',
    description: 'Edit a trip (destination, origin, purpose, eta_minutes). Use get_trips for the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        destination: { type: 'string' },
        origin: { type: 'string' },
        purpose: { type: 'string' },
        eta_minutes: { type: 'integer' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'trips', input.id);
      const updates = {};
      for (const k of ['destination', 'origin', 'purpose', 'eta_minutes']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateTrip(input.id, updates);
      const summary = `Updated trip #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_trip', summary } };
    },
  },

  // ---- Pantry (edit / delete) ----
  {
    name: 'update_pantry_item',
    description: 'Edit a pantry item (quantity, unit, location, expiry_date). Use list_pantry for the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        quantity: { type: 'string' },
        unit: { type: 'string' },
        location: { type: 'string' },
        expiry_date: { type: 'string', description: 'YYYY-MM-DD' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'pantry', input.id);
      const updates = {};
      for (const k of ['quantity', 'unit', 'location', 'expiry_date']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.expiry_date) requireDate(updates.expiry_date, 'expiry_date');
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updatePantryItem(input.id, updates);
      const summary = `Updated pantry item #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_pantry_item', summary } };
    },
  },
  {
    name: 'delete_pantry_item',
    description: 'Remove an item from the pantry. Use list_pantry for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'pantry', input.id);
      await ctx.db.deletePantryItem(input.id);
      const summary = `Deleted pantry item #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_pantry_item', summary } };
    },
  },

  // ---- People & milestones ----
  {
    name: 'list_people',
    description: "The household's people — adults and dependents (kids). Includes each person's id for logging milestones.",
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      await ctx.db.ensureHouseholdUserPeople(ctx.groupId);
      const rows = await ctx.db.getPeople(ctx.groupId);
      const result = rows.map(p => ({
        id: p.id, name: p.name, relationship: p.relationship,
        dependent: !!p.is_dependent, birthday: p.birthday || undefined,
      }));
      return { result };
    },
  },
  {
    name: 'list_milestones',
    description: "A person's milestones (first steps, first goal, …), newest first. Use list_people for the person id; omit it for the whole household.",
    write: false,
    input_schema: {
      type: 'object',
      properties: { person_id: { type: 'integer', description: 'Optional — limit to one person' } },
    },
    async run(ctx, input) {
      if (input.person_id != null) await assertHousehold(ctx, 'gift_people', input.person_id);
      const rows = await ctx.db.getMilestones(ctx.groupId, input.person_id ?? null);
      const result = rows.slice(0, 30).map(m => ({
        id: m.id, person: m.person_name, title: m.title,
        date: m.milestone_date, category: m.category,
      }));
      return { result };
    },
  },
  {
    name: 'log_milestone',
    description: "Log a milestone for a family member — e.g. \"Rowan lost his first tooth today\". The household gets a feed post to cheer them on. Use list_people for the person id; date defaults to today.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        person_id: { type: 'integer' },
        title: { type: 'string', description: 'The moment, e.g. "First steps"' },
        description: { type: 'string', description: 'A little detail (optional)' },
        milestone_date: { type: 'string', description: 'YYYY-MM-DD (optional, defaults to today)' },
        category: { type: 'string', enum: ['first', 'school', 'sports', 'growth', 'moment'] },
      },
      required: ['person_id', 'title'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'gift_people', input.person_id);
      const person = await dbGet(ctx, 'SELECT name FROM gift_people WHERE id = ?', [input.person_id]);
      const date = input.milestone_date || new Date().toISOString().slice(0, 10);
      requireDate(date, 'milestone_date');
      const result = await ctx.db.addMilestone({
        person_id: input.person_id,
        title: input.title,
        description: input.description || null,
        milestone_date: date,
        category: input.category || 'moment',
        created_by: ctx.userId,
        creator_name: ctx.userName,
        group_id: ctx.groupId,
      });
      try {
        await ctx.db.addFeedPost({
          group_id: ctx.groupId, author_id: ctx.userId, post_type: 'milestone',
          title: `${person.name}: ${input.title}`, body: input.description || null,
          reference_type: 'milestone', reference_id: result.id,
        });
      } catch (e) { /* celebration is best-effort */ }
      if (ctx.push) {
        ctx.push.pushToGroup(ctx.db, ctx.groupId, ctx.userId, 'A new milestone',
          `${person.name} — ${input.title}. Cheer them on!`, { type: 'milestone', ref_id: result.id });
      }
      const summary = `Logged milestone "${input.title}" for ${person.name} (${date})`;
      return { result: { ok: true, summary }, action: { tool: 'log_milestone', summary } };
    },
  },

  // ---- People registry (add / edit / delete) ----
  {
    name: 'add_person',
    description: "Add a person to the household registry (a dependent kid, relative, or another adult). Use list_people to see who already exists.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        relationship: { type: 'string', enum: ['spouse', 'wife', 'husband', 'partner', 'son', 'daughter', 'parent', 'grandparent', 'household', 'other'] },
        birthday: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        avatar_color: { type: 'string', description: 'Hex colour, e.g. "#E07A5F" (optional)' },
        is_dependent: { type: 'boolean', description: 'True for a kid/relative without their own account' },
      },
      required: ['name'],
    },
    async run(ctx, input) {
      if (!ctx.groupId) return { result: { ok: false, error: 'Join a household first' } };
      if (input.birthday) requireDate(input.birthday, 'birthday');
      const r = await ctx.db.addPerson({
        name: input.name, relationship: input.relationship || 'other',
        birthday: input.birthday || null, avatar_color: input.avatar_color || null,
        is_dependent: !!input.is_dependent, user_id: null, group_id: ctx.groupId,
      });
      const summary = `Added ${input.name} to the household`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_person', summary } };
    },
  },
  {
    name: 'update_person',
    description: 'Edit a person in the household registry (name, relationship, birthday, avatar_color). Use list_people for the id. Only pass fields to change.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        name: { type: 'string' },
        relationship: { type: 'string', enum: ['spouse', 'wife', 'husband', 'partner', 'son', 'daughter', 'parent', 'grandparent', 'household', 'other'] },
        birthday: { type: 'string', description: 'YYYY-MM-DD' },
        avatar_color: { type: 'string', description: 'Hex colour' },
        is_dependent: { type: 'boolean' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'gift_people', input.id);
      const updates = {};
      for (const k of ['name', 'relationship', 'birthday', 'avatar_color', 'is_dependent']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.birthday) requireDate(updates.birthday, 'birthday');
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updatePerson(input.id, updates);
      const summary = `Updated person #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_person', summary } };
    },
  },
  {
    name: 'delete_person',
    description: 'Remove a person from the household registry permanently. Use list_people for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'gift_people', input.id);
      await ctx.db.deletePerson(input.id);
      const summary = `Deleted person #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_person', summary } };
    },
  },

  // ---- Contacts (address book — owner-scoped) ----
  {
    name: 'get_contacts',
    description: "List your saved contacts (care team, family, friends).",
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getContactsByUser(ctx.userId);
      return { result: rows.map(c => ({
        id: c.id, name: c.name, relationship: c.relationship, phone: c.phone, email: c.email, birthday: c.birthday,
      })) };
    },
  },
  {
    name: 'add_contact',
    description: 'Add a contact to your address book.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        relationship: { type: 'string' },
        phone: { type: 'string' },
        email: { type: 'string' },
        birthday: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        notes: { type: 'string' },
      },
      required: ['name'],
    },
    async run(ctx, input) {
      if (input.birthday) requireDate(input.birthday, 'birthday');
      const r = await ctx.db.addContact({
        added_by: ctx.userId, name: input.name, relationship: input.relationship || null,
        phone: input.phone || null, email: input.email || null,
        birthday: input.birthday || null, notes: input.notes || null,
      });
      const summary = `Added contact ${input.name}`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_contact', summary } };
    },
  },
  {
    name: 'update_contact',
    description: 'Edit one of your contacts. Use get_contacts for the id. Only pass fields to change.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        name: { type: 'string' },
        relationship: { type: 'string' },
        phone: { type: 'string' },
        email: { type: 'string' },
        birthday: { type: 'string', description: 'YYYY-MM-DD' },
        notes: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertContactOwner(ctx, input.id);
      const updates = {};
      for (const k of ['name', 'relationship', 'phone', 'email', 'birthday', 'notes']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.birthday) requireDate(updates.birthday, 'birthday');
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateContact(input.id, updates);
      const summary = `Updated contact #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_contact', summary } };
    },
  },
  {
    name: 'delete_contact',
    description: 'Delete one of your contacts. Use get_contacts for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertContactOwner(ctx, input.id);
      await ctx.db.deleteContact(input.id);
      const summary = `Deleted contact #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_contact', summary } };
    },
  },

  // ---- Budget categories ----
  {
    name: 'add_budget_category',
    description: 'Create a budget category with an optional monthly spending limit.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        monthly_limit: { type: 'number' },
        color: { type: 'string', description: 'Hex colour (optional)' },
      },
      required: ['name'],
    },
    async run(ctx, input) {
      const r = await ctx.db.addBudgetCategory(input.name, input.monthly_limit ?? null, input.color || null, ctx.groupId);
      const summary = `Added budget category "${input.name}"`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_budget_category', summary } };
    },
  },
  {
    name: 'update_budget_category',
    description: 'Edit a budget category (name, monthly_limit, color). Use get_budget for the category name; pass the id. Only pass fields to change.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        name: { type: 'string' },
        monthly_limit: { type: 'number' },
        color: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'budget_categories', input.id);
      const updates = {};
      for (const k of ['name', 'monthly_limit', 'color']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateBudgetCategory(input.id, updates);
      const summary = `Updated budget category #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_budget_category', summary } };
    },
  },
  {
    name: 'delete_budget_category',
    description: 'Delete a budget category. Pass its id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'budget_categories', input.id);
      await ctx.db.deleteBudgetCategory(input.id);
      const summary = `Deleted budget category #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_budget_category', summary } };
    },
  },

  // ---- Recurring payments (rent, subscriptions, …) ----
  {
    name: 'get_recurring_payments',
    description: 'List the household\'s tracked recurring payments (rent, mortgage, subscriptions).',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getRecurringPayments(ctx.groupId);
      return { result: rows.map(p => ({
        id: p.id, name: p.name, amount: p.amount, category: p.category,
        frequency: p.frequency, due_day: p.due_day, autopay: !!p.autopay,
      })) };
    },
  },
  {
    name: 'add_recurring_payment',
    description: 'Track a recurring payment (rent, mortgage, subscription, …).',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        amount: { type: 'number' },
        category: { type: 'string' },
        frequency: { type: 'string', enum: ['weekly', 'monthly', 'yearly'] },
        due_day: { type: 'integer', description: 'Day of month it is due (1-31, optional)' },
        autopay: { type: 'boolean' },
        notes: { type: 'string' },
      },
      required: ['name', 'amount'],
    },
    async run(ctx, input) {
      if (!ctx.groupId) return { result: { ok: false, error: 'Join a household first' } };
      const r = await ctx.db.addRecurringPayment({
        name: input.name, amount: input.amount, category: input.category || null,
        frequency: input.frequency || 'monthly', due_day: input.due_day || null,
        autopay: !!input.autopay, notes: input.notes || null,
        created_by: ctx.userName, group_id: ctx.groupId,
      });
      const summary = `Added recurring payment "${input.name}"`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_recurring_payment', summary } };
    },
  },
  {
    name: 'update_recurring_payment',
    description: 'Edit a recurring payment. Use get_recurring_payments for the id. Only pass fields to change.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        name: { type: 'string' },
        amount: { type: 'number' },
        category: { type: 'string' },
        frequency: { type: 'string', enum: ['weekly', 'monthly', 'yearly'] },
        due_day: { type: 'integer' },
        autopay: { type: 'boolean' },
        notes: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'recurring_payments', input.id);
      const updates = {};
      for (const k of ['name', 'amount', 'category', 'frequency', 'due_day', 'autopay', 'notes']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateRecurringPayment(input.id, updates);
      const summary = `Updated recurring payment #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_recurring_payment', summary } };
    },
  },
  {
    name: 'delete_recurring_payment',
    description: 'Stop tracking a recurring payment. Use get_recurring_payments for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'recurring_payments', input.id);
      await ctx.db.deleteRecurringPayment(input.id);
      const summary = `Deleted recurring payment #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_recurring_payment', summary } };
    },
  },

  // ---- Projects (budgeted projects with expenses) ----
  {
    name: 'get_projects',
    description: 'List the household\'s budgeted projects with spend totals.',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getProjects(ctx.groupId);
      return { result: rows.map(p => ({
        id: p.id, name: p.name, budget: p.budget, spent: p.total_spent, expenses: p.expense_count,
      })) };
    },
  },
  {
    name: 'add_project',
    description: 'Create a budgeted project (e.g. a renovation or trip fund).',
    write: true,
    input_schema: {
      type: 'object',
      properties: { name: { type: 'string' }, budget: { type: 'number' } },
      required: ['name'],
    },
    async run(ctx, input) {
      const r = await ctx.db.addProject({ name: input.name, budget: input.budget || 0, created_by: ctx.userName, group_id: ctx.groupId });
      const summary = `Created project "${input.name}"`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_project', summary } };
    },
  },
  {
    name: 'delete_project',
    description: 'Delete a budgeted project. Use get_projects for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'budget_projects', input.id);
      await ctx.db.deleteProject(input.id);
      const summary = `Deleted project #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_project', summary } };
    },
  },
  {
    name: 'add_project_expense',
    description: 'Add an expense to a budgeted project. Use get_projects for the project_id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        project_id: { type: 'integer' },
        description: { type: 'string' },
        amount: { type: 'number' },
        category: { type: 'string' },
        notes: { type: 'string' },
      },
      required: ['project_id', 'description', 'amount'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'budget_projects', input.project_id);
      const r = await ctx.db.addProjectExpense(input.project_id, {
        description: input.description, amount: input.amount,
        category: input.category || 'General', notes: input.notes || null,
      }, ctx.groupId);
      const summary = `Added expense "${input.description}" to project #${input.project_id}`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_project_expense', summary } };
    },
  },
  {
    name: 'delete_project_expense',
    description: 'Delete an expense from a budgeted project. Pass the expense id and its project_id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer' }, project_id: { type: 'integer' } },
      required: ['id', 'project_id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'budget_projects', input.project_id);
      await ctx.db.deleteProjectExpense(input.id, input.project_id);
      const summary = `Deleted project expense #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_project_expense', summary } };
    },
  },

  // ---- Coverage (childcare / help requests) ----
  {
    name: 'create_coverage_request',
    description: "Ask your care team for childcare/help coverage. Provide one or more time windows and optionally the contact_ids (from get_contacts) to invite.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        reason: { type: 'string' },
        note: { type: 'string' },
        windows: {
          type: 'array',
          description: 'Time windows that need covering',
          items: {
            type: 'object',
            properties: {
              window_date: { type: 'string', description: 'YYYY-MM-DD' },
              start_time: { type: 'string', description: 'HH:MM' },
              end_time: { type: 'string', description: 'HH:MM' },
              description: { type: 'string' },
            },
            required: ['window_date', 'start_time', 'end_time'],
          },
        },
        contact_ids: { type: 'array', items: { type: 'integer' }, description: 'Contact ids to invite (from get_contacts)' },
      },
      required: ['reason'],
    },
    async run(ctx, input) {
      const request = await ctx.db.createCoverageRequest({ requester_id: ctx.userId, reason: input.reason, note: input.note || null });
      for (const w of (input.windows || [])) {
        requireDate(w.window_date, 'window_date');
        await ctx.db.addCoverageWindow({
          request_id: request.id, window_date: w.window_date,
          start_time: w.start_time, end_time: w.end_time, description: w.description || null,
        });
      }
      const recipients = [];
      for (const contactId of (input.contact_ids || [])) {
        await assertContactOwner(ctx, contactId);
        const rec = await ctx.db.addCoverageRecipient({ request_id: request.id, contact_id: contactId });
        recipients.push(rec);
        if (ctx.push) {
          const helperId = await ctx.db.getUserIdByContactId(contactId);
          if (helperId) {
            ctx.push.pushToUser(ctx.db, helperId, `${ctx.userName} needs your help`, input.reason, { type: 'coverage', ref_id: request.id });
          }
        }
      }
      const summary = `Created a coverage request: ${input.reason}`;
      return { result: { ok: true, id: request.id, summary }, action: { tool: 'create_coverage_request', summary } };
    },
  },
  {
    name: 'cancel_coverage_request',
    description: 'Cancel one of your coverage requests. Use get_coverage or the id you just created.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      const req = await dbGet(ctx, 'SELECT requester_id FROM coverage_requests WHERE id = ?', [input.id]);
      if (!req) throw new Error(`No coverage request #${input.id} found`);
      if (req.requester_id !== ctx.userId) throw new Error(`Coverage request #${input.id} is not yours`);
      await ctx.db.cancelCoverageRequest(input.id);
      const summary = `Cancelled coverage request #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'cancel_coverage_request', summary } };
    },
  },

  // ---- Feed (household activity feed) ----
  {
    name: 'add_feed_post',
    description: "Post an update or shout-out to the shared household activity feed that everyone sees. For a private note or memo, use add_note instead.",
    write: true,
    input_schema: {
      type: 'object',
      properties: { title: { type: 'string' }, body: { type: 'string' } },
      required: ['body'],
    },
    async run(ctx, input) {
      if (!ctx.groupId) return { result: { ok: false, error: 'Join a household first' } };
      const r = await ctx.db.addFeedPost({
        group_id: ctx.groupId, author_id: ctx.userId, post_type: 'text',
        title: input.title || null, body: input.body,
      });
      if (ctx.push) {
        ctx.push.pushToGroup(ctx.db, ctx.groupId, ctx.userId, `New from ${ctx.userName}`, input.title || input.body, { type: 'group_message', ref_id: ctx.groupId });
      }
      const summary = `Posted to the household feed`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_feed_post', summary } };
    },
  },
  {
    name: 'add_feed_reaction',
    description: 'React to a household feed post (e.g. like). Pass the post id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        post_id: { type: 'integer' },
        reaction_type: { type: 'string', description: 'e.g. "like", "love", "celebrate" (default like)' },
      },
      required: ['post_id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'feed_posts', input.post_id);
      await ctx.db.addFeedReaction(input.post_id, ctx.userId, input.reaction_type || 'like');
      const summary = `Reacted to feed post #${input.post_id}`;
      return { result: { ok: true, summary }, action: { tool: 'add_feed_reaction', summary } };
    },
  },
  {
    name: 'add_feed_comment',
    description: 'Comment on a household feed post. Pass the post id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { post_id: { type: 'integer' }, text: { type: 'string' } },
      required: ['post_id', 'text'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'feed_posts', input.post_id);
      await ctx.db.addFeedComment(input.post_id, ctx.userId, input.text);
      const summary = `Commented on feed post #${input.post_id}`;
      return { result: { ok: true, summary }, action: { tool: 'add_feed_comment', summary } };
    },
  },

  // ---- Rivalries (create) ----
  {
    name: 'create_rivalry',
    description: "Start a family rivalry/competition. participants are the member names taking part (defaults to include you). Log scores afterwards with log_rivalry_score.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        challenge_type: { type: 'string', description: 'e.g. "steps", "chores", "reading"' },
        participants: { type: 'array', items: { type: 'string' }, description: 'Member names competing' },
        start_date: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        end_date: { type: 'string', description: 'YYYY-MM-DD (optional)' },
        point_value: { type: 'integer', description: 'Points for the winner (optional)' },
      },
      required: ['title'],
    },
    async run(ctx, input) {
      if (!ctx.groupId) return { result: { ok: false, error: 'Join a household first' } };
      if (input.start_date) requireDate(input.start_date, 'start_date');
      if (input.end_date) requireDate(input.end_date, 'end_date');
      let participants = Array.isArray(input.participants) ? input.participants.filter(Boolean) : [];
      if (!participants.includes(ctx.userName)) participants = [ctx.userName, ...participants];
      const r = await ctx.db.addRivalry({
        title: input.title, challenge_type: input.challenge_type || 'challenge',
        initiator_name: ctx.userName, opponent_name: participants.find(p => p !== ctx.userName) || null,
        start_date: input.start_date || null, end_date: input.end_date || null,
        status: 'active', point_value: input.point_value || 100,
        participants, rivalry_type: 'individual', group_id: ctx.groupId,
      });
      const summary = `Started rivalry "${input.title}"`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'create_rivalry', summary } };
    },
  },

  // ---- Special events / key dates ----
  {
    name: 'get_special_events',
    description: "List the household's key dates / special events (birthdays, anniversaries, custom occasions).",
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getSpecialEvents(ctx.groupId);
      return { result: rows.map(e => ({
        id: e.id, title: e.title, date: e.date, type: e.event_type,
        recurring: !!e.is_recurring, person_id: e.person_id, notes: e.notes,
      })) };
    },
  },
  {
    name: 'add_special_event',
    description: 'Add a key date / special event. Optionally tie it to a person (use list_people for person_id).',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        date: { type: 'string', description: 'YYYY-MM-DD' },
        person_id: { type: 'integer', description: 'Optional person this date is about' },
        event_type: { type: 'string', description: 'e.g. "birthday", "anniversary", "custom"' },
        is_recurring: { type: 'boolean', description: 'Repeats every year (default true)' },
        notes: { type: 'string' },
      },
      required: ['title', 'date'],
    },
    async run(ctx, input) {
      requireDate(input.date, 'date');
      if (input.person_id != null) await assertHousehold(ctx, 'gift_people', input.person_id);
      const r = await ctx.db.addSpecialEvent({
        title: input.title, date: input.date, person_id: input.person_id || null,
        event_type: input.event_type || 'custom', is_recurring: input.is_recurring !== false,
        notes: input.notes || null, group_id: ctx.groupId,
      });
      const summary = `Added key date "${input.title}" (${input.date})`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_special_event', summary } };
    },
  },
  {
    name: 'update_special_event',
    description: 'Edit a key date / special event. Use get_special_events for the id. Only pass fields to change.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer' },
        title: { type: 'string' },
        date: { type: 'string', description: 'YYYY-MM-DD' },
        person_id: { type: 'integer' },
        event_type: { type: 'string' },
        is_recurring: { type: 'boolean' },
        notes: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'special_events', input.id);
      const updates = {};
      for (const k of ['title', 'date', 'person_id', 'event_type', 'is_recurring', 'notes']) {
        if (input[k] != null) updates[k] = input[k];
      }
      if (updates.date) requireDate(updates.date, 'date');
      if (updates.person_id != null) await assertHousehold(ctx, 'gift_people', updates.person_id);
      if (Object.keys(updates).length === 0) return { result: { ok: false, error: 'no fields to update' } };
      await ctx.db.updateSpecialEvent(input.id, updates);
      const summary = `Updated key date #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_special_event', summary } };
    },
  },
  {
    name: 'delete_special_event',
    description: 'Delete a key date / special event. Use get_special_events for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await assertHousehold(ctx, 'special_events', input.id);
      await ctx.db.deleteSpecialEvent(input.id);
      const summary = `Deleted key date #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_special_event', summary } };
    },
  },

  // ---- Itinerary expenses ----
  {
    name: 'add_itinerary_expense',
    description: 'Log an expense against a trip/itinerary. Use get_itineraries for the itinerary_id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        itinerary_id: { type: 'integer' },
        merchant: { type: 'string' },
        amount: { type: 'number' },
        date: { type: 'string', description: 'YYYY-MM-DD (optional, defaults to today)' },
        category: { type: 'string' },
        notes: { type: 'string' },
      },
      required: ['itinerary_id', 'amount'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'itineraries', input.itinerary_id);
      const date = input.date || ctx.today;
      requireDate(date, 'date');
      const r = await ctx.db.addReceipt({
        amount: input.amount, merchant: input.merchant || 'Trip expense', date,
        category: input.category || 'Travel', notes: input.notes || null,
        added_by: ctx.userName, itinerary_id: input.itinerary_id, group_id: ctx.groupId,
      });
      const summary = `Logged a ${input.amount} expense on itinerary #${input.itinerary_id}`;
      return { result: { ok: true, id: r.id, summary }, action: { tool: 'add_itinerary_expense', summary } };
    },
  },

  // ---- User profile ----
  {
    name: 'update_task',
    description: 'Edit a task: retitle, reschedule (move to another day), reprioritize, or reassign. Use list_tasks first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Task id from list_tasks' },
        title: { type: 'string' },
        due_date: { type: 'string', description: 'YYYY-MM-DD; new date to move the task to' },
        due_time: { type: 'string', description: 'HH:MM (optional)' },
        priority: { type: 'string', enum: ['low', 'medium', 'high'] },
        assigned_to: { type: 'string', description: 'Name of who it is for' },
        category: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      if (input.due_date) requireDate(input.due_date, 'due_date');
      const { id, ...updates } = input;
      const r = await ctx.db.updateTask(id, updates, ctx.groupId);
      if (!r.changed) return { result: { ok: false, error: `No task #${id} in this household (or nothing to change)` } };
      const summary = `Updated task #${id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_task', summary } };
    },
  },
  {
    name: 'delete_task',
    description: 'Delete a task entirely (not just complete it). Use list_tasks first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Task id from list_tasks' } },
      required: ['id'],
    },
    async run(ctx, input) {
      const r = await ctx.db.deleteTask(input.id, ctx.groupId);
      if (!r.changed) return { result: { ok: false, error: `No task #${input.id} in this household` } };
      const summary = `Deleted task #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_task', summary } };
    },
  },

  // ---- Lists (create / rename / delete / item edit / move) ----
  {
    name: 'create_list',
    description: 'Create a new named list (shopping list, packing list, to-do list).',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        type: { type: 'string', enum: ['standard', 'grocery'], description: 'grocery lists get check-off shopping behavior' },
      },
      required: ['name'],
    },
    async run(ctx, input) {
      const name = String(input.name || '').trim();
      if (!name) return { result: { ok: false, error: 'List name is required' } };
      const existing = await resolveListByName(ctx, name);
      if (existing && !existing.reserved) {
        return { result: { ok: false, error: `A list named "${existing.name}" already exists` } };
      }
      const type = input.type || (GROCERY_LIST_NAMES.has(name.toLowerCase()) ? 'grocery' : 'standard');
      await ctx.db.createList({ name, list_type: type, created_by: ctx.userId });
      const summary = `Created the "${name}" list`;
      return { result: { ok: true, summary }, action: { tool: 'create_list', summary } };
    },
  },
  {
    name: 'rename_list',
    description: 'Rename a list. Identify it by its current name.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        list: { type: 'string', description: 'Current list name' },
        new_name: { type: 'string' },
      },
      required: ['list', 'new_name'],
    },
    async run(ctx, input) {
      const list = await resolveListByName(ctx, input.list);
      if (!list || list.reserved) return { result: { ok: false, error: `No list named "${input.list}"` } };
      const newName = String(input.new_name || '').trim();
      if (!newName) return { result: { ok: false, error: 'New name is required' } };
      await ctx.db.updateList(list.id, { name: newName });
      const summary = `Renamed "${list.name}" to "${newName}"`;
      return { result: { ok: true, summary }, action: { tool: 'rename_list', summary } };
    },
  },
  {
    name: 'delete_list',
    description: 'Delete an entire list and its items. Identify it by name.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { list: { type: 'string', description: 'List name' } },
      required: ['list'],
    },
    async run(ctx, input) {
      const list = await resolveListByName(ctx, input.list);
      if (!list || list.reserved) return { result: { ok: false, error: `No list named "${input.list}"` } };
      await ctx.db.deleteList(list.id);
      const summary = `Deleted the "${list.name}" list`;
      return { result: { ok: true, summary }, action: { tool: 'delete_list', summary } };
    },
  },
  {
    name: 'update_list_item',
    description: 'Rename or recategorize an item on a list. Use get_list first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Item id from get_list' },
        title: { type: 'string', description: 'New text for the item' },
        category: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      const item = await dbGet(ctx, 'SELECT id, list_id FROM list_items WHERE id = ?', [input.id]);
      if (!item) return { result: { ok: false, error: `No list item #${input.id} found` } };
      await assertListAccess(ctx, item.list_id);
      const updates = {};
      if (input.title) updates.title = input.title;
      if (input.category) updates.category = input.category;
      if (!Object.keys(updates).length) return { result: { ok: false, error: 'Nothing to change' } };
      await ctx.db.updateListItem(input.id, updates);
      const summary = `Updated item #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_list_item', summary } };
    },
  },
  {
    name: 'delete_list_item',
    description: 'Remove an item from a list entirely (not check it off). Use get_list first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Item id from get_list' } },
      required: ['id'],
    },
    async run(ctx, input) {
      const item = await dbGet(ctx, 'SELECT id, list_id, title FROM list_items WHERE id = ?', [input.id]);
      if (!item) return { result: { ok: false, error: `No list item #${input.id} found` } };
      await assertListAccess(ctx, item.list_id);
      await ctx.db.deleteListItem(input.id);
      const summary = `Removed "${item.title}" from the list`;
      return { result: { ok: true, summary }, action: { tool: 'delete_list_item', summary } };
    },
  },
  {
    name: 'move_list_item',
    description: 'Move an item from one list to another (e.g. from Groceries to Costco). Use get_list first to get the item id. The target list is created if it does not exist.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Item id from get_list' },
        to_list: { type: 'string', description: 'Target list name' },
      },
      required: ['id', 'to_list'],
    },
    async run(ctx, input) {
      const item = await dbGet(ctx, 'SELECT id, list_id, title, category FROM list_items WHERE id = ?', [input.id]);
      if (!item) return { result: { ok: false, error: `No list item #${input.id} found` } };
      await assertListAccess(ctx, item.list_id);
      const target = await resolveListByName(ctx, input.to_list, { create: true });
      if (!target || target.reserved) return { result: { ok: false, error: `Could not find or create a list named "${input.to_list}"` } };
      if (target.id === item.list_id) return { result: { ok: false, error: `That item is already on "${target.name}"` } };
      await ctx.db.addListItem({ list_id: target.id, title: item.title, added_by: ctx.userName, category: item.category || null });
      await ctx.db.deleteListItem(item.id);
      const summary = `Moved "${item.title}" to ${target.name}`;
      return { result: { ok: true, summary }, action: { tool: 'move_list_item', summary } };
    },
  },

  // ---- Expenses / receipts ----
  {
    name: 'list_receipts',
    description: 'List recent expenses/receipts, optionally for one month.',
    write: false,
    input_schema: {
      type: 'object',
      properties: { month: { type: 'string', description: 'YYYY-MM (optional, defaults to recent)' } },
    },
    async run(ctx, input) {
      const rows = await ctx.db.getReceipts(input.month ? { month: input.month } : {}, ctx.groupId);
      const result = rows.slice(0, 40).map(r => ({
        id: r.id, merchant: r.merchant, amount: r.amount, date: r.date, category: r.category,
      }));
      return { result };
    },
  },
  {
    name: 'add_expense',
    description: 'Log an expense/receipt against the budget (e.g. "I spent $40 at Costco"). The category is created if new.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        amount: { type: 'number', description: 'Dollar amount' },
        merchant: { type: 'string', description: 'Where the money was spent' },
        category: { type: 'string', description: 'Budget category, e.g. Groceries, Gas, Dining' },
        date: { type: 'string', description: 'YYYY-MM-DD (optional, defaults to today)' },
        notes: { type: 'string' },
      },
      required: ['amount', 'merchant'],
    },
    async run(ctx, input) {
      const amount = Number(String(input.amount).replace(/[$,\s]/g, ''));
      if (!Number.isFinite(amount) || amount < 0) return { result: { ok: false, error: 'Invalid amount' } };
      if (input.date) requireDate(input.date, 'date');
      const category = input.category || 'Other';
      await ctx.db.ensureBudgetCategory(category, ctx.groupId);
      await ctx.db.addReceipt({
        amount, merchant: input.merchant, date: input.date || ctx.today,
        category, notes: input.notes || null, processed_by: 'concierge',
        added_by: ctx.userName, group_id: ctx.groupId,
      });
      const summary = `Logged $${amount.toFixed(2)} at ${input.merchant} (${category})`;
      return { result: { ok: true, summary }, action: { tool: 'add_expense', summary } };
    },
  },
  {
    name: 'delete_receipt',
    description: 'Delete an expense/receipt. Use list_receipts first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Receipt id from list_receipts' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'receipts', input.id);
      await ctx.db.deleteReceipt(input.id);
      const summary = `Deleted receipt #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_receipt', summary } };
    },
  },

  // ---- Decisions (create / delete) ----
  {
    name: 'add_decision',
    description: 'Create a new family decision or poll for the household to vote on.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string', description: 'The question to decide' },
        options: { type: 'array', items: { type: 'string' }, description: 'Poll choices (2+; omit for an open discussion)' },
        body: { type: 'string', description: 'Extra context (optional)' },
        expires_at: { type: 'string', description: 'YYYY-MM-DD when voting closes (optional)' },
      },
      required: ['title'],
    },
    async run(ctx, input) {
      if (input.expires_at) requireDate(input.expires_at, 'expires_at');
      const options = Array.isArray(input.options) ? input.options.filter(o => String(o).trim()) : [];
      await ctx.db.addDecision({
        title: input.title,
        decision_type: options.length ? 'poll' : 'discussion',
        body: input.body || null,
        poll_options: options,
        creator_name: ctx.userName,
        status: 'active',
        expires_at: input.expires_at || null,
        group_id: ctx.groupId,
      });
      const summary = `Created decision "${input.title}"${options.length ? ` with ${options.length} options` : ''}`;
      return { result: { ok: true, summary }, action: { tool: 'add_decision', summary } };
    },
  },
  {
    name: 'delete_decision',
    description: 'Delete a decision/poll and its votes and comments. Use list_decisions first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Decision id from list_decisions' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'decisions', input.id);
      const run = (sql, params) => new Promise((resolve, reject) =>
        ctx.db.db.run(sql, params, (err) => err ? reject(err) : resolve()));
      await run('DELETE FROM decision_reactions WHERE decision_id = ?', [input.id]);
      await run('DELETE FROM decision_comments WHERE decision_id = ?', [input.id]);
      await run('DELETE FROM decisions WHERE id = ?', [input.id]);
      const summary = `Deleted decision #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_decision', summary } };
    },
  },

  // ---- Trips (delete) ----
  {
    name: 'delete_trip',
    description: 'Delete a trip record entirely. Use get_trips first to get the id. (Prefer cancel_trip for an in-progress trip.)',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Trip id from get_trips' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'trips', input.id);
      await ctx.db.deleteTrip(input.id);
      const summary = `Deleted trip #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_trip', summary } };
    },
  },

  // ---- Rivalries (complete / delete) ----
  {
    name: 'complete_rivalry',
    description: 'End a rivalry now and declare the winner from current totals. Use get_rivalries first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Rivalry id from get_rivalries' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'rivalries', input.id);
      const outcome = await ctx.db.completeRivalryWithTotals(input.id);
      if (outcome.already_completed) {
        return { result: { ok: false, error: `Rivalry #${input.id} was already completed (winner: ${outcome.winner_name || 'tie'})` } };
      }
      const summary = outcome.winner_name
        ? `Completed the rivalry — ${outcome.winner_name} wins!`
        : 'Completed the rivalry — it ended in a tie';
      return { result: { ok: true, summary, winner: outcome.winner_name || null }, action: { tool: 'complete_rivalry', summary } };
    },
  },
  {
    name: 'delete_rivalry',
    description: 'Delete a rivalry and its logged scores. Use get_rivalries first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Rivalry id from get_rivalries' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'rivalries', input.id);
      await ctx.db.deleteRivalry(input.id);
      const summary = `Deleted rivalry #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_rivalry', summary } };
    },
  },

  // ---- Gift ideas (update / delete) ----
  {
    name: 'update_gift_idea',
    description: 'Update a gift idea — mark it purchased/wrapped/given, or edit its title, price, or notes. Use get_gift_ideas first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Gift idea id from get_gift_ideas' },
        status: { type: 'string', enum: ['idea', 'purchased', 'wrapped', 'given'] },
        title: { type: 'string' },
        estimated_price: { type: 'number' },
        notes: { type: 'string' },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'gift_ideas', input.id);
      const { id, ...updates } = input;
      if (!Object.keys(updates).length) return { result: { ok: false, error: 'Nothing to change' } };
      await ctx.db.updateGiftIdea(id, updates);
      const summary = updates.status ? `Marked gift idea #${id} as ${updates.status}` : `Updated gift idea #${id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_gift_idea', summary } };
    },
  },
  {
    name: 'delete_gift_idea',
    description: 'Delete a gift idea. Use get_gift_ideas first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Gift idea id from get_gift_ideas' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'gift_ideas', input.id);
      await ctx.db.deleteGiftIdea(input.id);
      const summary = `Deleted gift idea #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_gift_idea', summary } };
    },
  },

  // ---- Milestones (update / delete) ----
  {
    name: 'update_milestone',
    description: "Edit a logged milestone's title, date, description, or category. Use list_milestones first to get the id.",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'integer', description: 'Milestone id from list_milestones' },
        title: { type: 'string' },
        milestone_date: { type: 'string', description: 'YYYY-MM-DD' },
        description: { type: 'string' },
        category: { type: 'string', enum: ['first', 'school', 'sports', 'growth', 'moment'] },
      },
      required: ['id'],
    },
    async run(ctx, input) {
      if (input.milestone_date) requireDate(input.milestone_date, 'milestone_date');
      await assertHousehold(ctx, 'milestones', input.id);
      const { id, ...updates } = input;
      if (!Object.keys(updates).length) return { result: { ok: false, error: 'Nothing to change' } };
      await ctx.db.updateMilestone(id, updates);
      const summary = `Updated milestone #${id}`;
      return { result: { ok: true, summary }, action: { tool: 'update_milestone', summary } };
    },
  },
  {
    name: 'delete_milestone',
    description: 'Delete a logged milestone. Use list_milestones first to get the id.',
    write: true,
    input_schema: {
      type: 'object',
      properties: { id: { type: 'integer', description: 'Milestone id from list_milestones' } },
      required: ['id'],
    },
    async run(ctx, input) {
      await assertHousehold(ctx, 'milestones', input.id);
      await ctx.db.deleteMilestone(input.id);
      const summary = `Deleted milestone #${input.id}`;
      return { result: { ok: true, summary }, action: { tool: 'delete_milestone', summary } };
    },
  },

  // ---- Coverage (incoming / approve) ----
  {
    name: 'get_incoming_coverage',
    description: 'List coverage/help requests OTHER people have sent to you, with their proposed time windows.',
    write: false,
    input_schema: { type: 'object', properties: {} },
    async run(ctx) {
      const rows = await ctx.db.getIncomingCoverageRequests(ctx.userId);
      const result = [];
      for (const r of rows.slice(0, 10)) {
        const windows = await ctx.db.getCoverageWindows(r.id);
        result.push({
          request_id: r.id, from: r.requester_name, reason: r.reason, note: r.note,
          status: r.recipient_status,
          windows: windows.map(w => ({ window_id: w.id, date: w.window_date, start: w.start_time, end: w.end_time })),
        });
      }
      return { result };
    },
  },
  {
    name: 'approve_incoming_coverage',
    description: "Confirm you can help with an incoming coverage request for one of its time windows. Use get_incoming_coverage first for the request_id and window_id (window_id may be omitted when there's exactly one window).",
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        request_id: { type: 'integer' },
        window_id: { type: 'integer', description: 'Which proposed window works (optional if only one)' },
        note: { type: 'string', description: 'Optional note to the requester' },
      },
      required: ['request_id'],
    },
    async run(ctx, input) {
      const recipient = await ctx.db.getRecipientByUserId(input.request_id, ctx.userId);
      if (!recipient) return { result: { ok: false, error: `No incoming request #${input.request_id} for you` } };
      if (recipient.status === 'approved') return { result: { ok: false, error: 'You already approved this request' } };
      const windows = await ctx.db.getCoverageWindows(input.request_id);
      const window = input.window_id
        ? windows.find(w => w.id === input.window_id)
        : (windows.length === 1 ? windows[0] : null);
      if (!window) {
        return { result: { ok: false, error: `Pick one of the proposed windows: ${windows.map(w => `#${w.id} ${w.window_date} ${w.start_time}-${w.end_time}`).join(', ')}` } };
      }
      await ctx.db.approveCoverage({
        request_id: input.request_id, recipient_id: recipient.id, window_id: window.id,
        approved_date: window.window_date, approved_start: window.start_time,
        approved_end: window.end_time, helper_note: input.note || null,
      });
      const request = await ctx.db.getCoverageRequestById(input.request_id);
      if (request && ctx.push) {
        ctx.push.pushToUser(ctx.db, request.requester_id, 'Coverage Confirmed',
          `${ctx.userName} approved ${window.start_time}–${window.end_time}`,
          { type: 'coverage', ref_id: input.request_id });
      }
      const summary = `Confirmed you can help ${request?.requester_name || 'them'} on ${window.window_date} ${window.start_time}–${window.end_time}`;
      return { result: { ok: true, summary }, action: { tool: 'approve_incoming_coverage', summary } };
    },
  },

  // ---- Messages ----
  {
    name: 'send_message',
    description: 'Send a direct message from you to another household/group member (e.g. "tell Melissa I\'ll be late"). Resolves the person by first name.',
    write: true,
    input_schema: {
      type: 'object',
      properties: {
        to: { type: 'string', description: 'Recipient name (first name is fine)' },
        text: { type: 'string', description: 'The message to send' },
      },
      required: ['to', 'text'],
    },
    async run(ctx, input) {
      const name = String(input.to || '').trim();
      const text = String(input.text || '').trim();
      if (!name || !text) return { result: { ok: false, error: 'Both recipient and message are required' } };
      // Escape LIKE metacharacters so a crafted name ("%") can't fan out to
      // arbitrary group members — the LLM-supplied `to` is untrusted input.
      const likePrefix = name.replace(/[\\%_]/g, '\\$&').toLowerCase() + ' %';
      // Only people you share a group with — same rule as the messages API.
      const recipient = await dbGet(ctx, `
        SELECT u.id, u.name FROM users u
        JOIN group_members gm ON gm.user_id = u.id
        WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
          AND u.id != ?
          AND (LOWER(u.name) = LOWER(?) OR LOWER(u.name) LIKE ? ESCAPE '\\' OR LOWER(u.username) = LOWER(?))
        ORDER BY (LOWER(u.name) = LOWER(?)) DESC, u.id ASC
        LIMIT 1`, [ctx.userId, ctx.userId, name, likePrefix, name, name]);
      if (!recipient) return { result: { ok: false, error: `No one named "${name}" in your groups` } };
      await ctx.db.sendMessage({ sender_id: ctx.userId, recipient_id: recipient.id, text });
      if (ctx.push) {
        ctx.push.pushToUser(ctx.db, recipient.id, `Message from ${ctx.userName}`, text,
          { type: 'message', ref_id: ctx.userId, name: ctx.userName });
      }
      const summary = `Sent "${text.length > 40 ? text.slice(0, 40) + '…' : text}" to ${recipient.name}`;
      return { result: { ok: true, summary }, action: { tool: 'send_message', summary } };
    },
  },
  {
    name: 'update_my_name',
    description: "Change your own display name shown across the household.",
    write: true,
    input_schema: {
      type: 'object',
      properties: { name: { type: 'string' } },
      required: ['name'],
    },
    async run(ctx, input) {
      const name = String(input.name || '').trim().slice(0, 60);
      if (!name) return { result: { ok: false, error: 'Name is required' } };
      await new Promise((resolve, reject) => {
        ctx.db.db.run('UPDATE users SET name = ? WHERE id = ?', [name, ctx.userId], (err) => err ? reject(err) : resolve());
      });
      const summary = `Updated your name to ${name}`;
      return { result: { ok: true, summary }, action: { tool: 'update_my_name', summary } };
    },
  },
];

// Fail fast on duplicate tool names — Anthropic 400-rejects a tools array with
// duplicates, which would break every concierge chat turn (silent until runtime).
{
  const seen = new Set();
  const dupes = TOOLS.map(t => t.name).filter(n => seen.size === seen.add(n).size);
  if (dupes.length) throw new Error(`Duplicate concierge tool name(s): ${[...new Set(dupes)].join(', ')}`);
}

const BY_NAME = new Map(TOOLS.map(t => [t.name, t]));

// ---------------------------------------------------------------------------
// Tool consolidation (the model-facing surface).
//
// The 79 fine-grained handlers above are the IMPLEMENTATION. We do not expose
// all 79 to the model: a flat list that long hurts tool-selection accuracy on a
// small model (Haiku) and bloats every request. Instead we present ~20 domain
// tools, each with an `action` selector that routes to one of the handlers. The
// model makes an easier two-level choice (domain → action) and the underlying
// DB logic is reused verbatim. definitions() are cached, so this is one call.
// ---------------------------------------------------------------------------

// domain -> { desc, actions: { actionName: underlyingToolName } }. Every tool
// above appears exactly once here or in STANDALONE below (asserted at load).
const GROUPS = {
  calendar: { desc: 'Household calendar events.', actions: {
    list: 'get_calendar', add: 'add_appointment', update: 'update_appointment', delete: 'delete_appointment' } },
  tasks: { desc: 'To-do tasks for the household.', actions: {
    list: 'list_tasks', add: 'add_task', complete: 'complete_task', update: 'update_task', delete: 'delete_task' } },
  lists: { desc: 'Named lists (Groceries, Costco, any shopping/to-do list; use "Tasks" for tasks).', actions: {
    list_all: 'get_lists', get: 'get_list', add: 'add_list_item', check_off: 'check_off_item',
    create: 'create_list', rename: 'rename_list', delete: 'delete_list',
    update_item: 'update_list_item', delete_item: 'delete_list_item', move_item: 'move_list_item' } },
  budget: { desc: 'Budget spending, expense logging, and categories.', actions: {
    get: 'get_budget', list_expenses: 'list_receipts', log_expense: 'add_expense', delete_expense: 'delete_receipt',
    add_category: 'add_budget_category', update_category: 'update_budget_category', delete_category: 'delete_budget_category' } },
  pantry: { desc: 'Pantry / fridge inventory.', actions: {
    list: 'list_pantry', add: 'add_pantry_item', update: 'update_pantry_item', delete: 'delete_pantry_item' } },
  decisions: { desc: 'Family decisions / polls.', actions: {
    list: 'list_decisions', create: 'add_decision', vote: 'vote_decision', comment: 'comment_decision', delete: 'delete_decision' } },
  trips: { desc: 'Live location / ETA trip shares.', actions: {
    list: 'get_trips', add: 'add_trip', update: 'update_trip', arrive: 'arrive_trip', cancel: 'cancel_trip', delete: 'delete_trip' } },
  itineraries: { desc: 'Multi-day trips/itineraries, their stays and expenses.', actions: {
    list: 'get_itineraries', add: 'add_itinerary', update: 'update_itinerary', delete: 'delete_itinerary',
    list_stays: 'get_itinerary_stays', add_stay: 'add_itinerary_stay', update_stay: 'update_itinerary_stay',
    delete_stay: 'delete_itinerary_stay', add_expense: 'add_itinerary_expense' } },
  rivalries: { desc: 'Family competitions and their scores.', actions: {
    list: 'get_rivalries', create: 'create_rivalry', log_score: 'log_rivalry_score', complete: 'complete_rivalry', delete: 'delete_rivalry' } },
  gifts: { desc: 'People tracked for gifts and their gift ideas.', actions: {
    list_people: 'get_gift_people', add_person: 'add_gift_person', list_ideas: 'get_gift_ideas', add_idea: 'add_gift_idea',
    update_idea: 'update_gift_idea', delete_idea: 'delete_gift_idea' } },
  coverage: { desc: 'Childcare / help coverage requests (yours and ones sent to you).', actions: {
    list: 'get_coverage', create: 'create_coverage_request', cancel: 'cancel_coverage_request',
    incoming: 'get_incoming_coverage', approve: 'approve_incoming_coverage' } },
  notes: { desc: 'Private/household notes (take/jot/write a note).', actions: {
    list: 'list_notes', add: 'add_note', update: 'update_note', delete: 'delete_note' } },
  people: { desc: 'Household people (adults, kids) and their milestones.', actions: {
    list: 'list_people', add: 'add_person', update: 'update_person', delete: 'delete_person',
    list_milestones: 'list_milestones', log_milestone: 'log_milestone',
    update_milestone: 'update_milestone', delete_milestone: 'delete_milestone' } },
  contacts: { desc: 'Your personal address book.', actions: {
    list: 'get_contacts', add: 'add_contact', update: 'update_contact', delete: 'delete_contact' } },
  recurring_payments: { desc: 'Tracked recurring payments (rent, subscriptions).', actions: {
    list: 'get_recurring_payments', add: 'add_recurring_payment', update: 'update_recurring_payment', delete: 'delete_recurring_payment' } },
  projects: { desc: 'Budgeted projects and their expenses.', actions: {
    list: 'get_projects', add: 'add_project', delete: 'delete_project', add_expense: 'add_project_expense', delete_expense: 'delete_project_expense' } },
  feed: { desc: 'Shared household activity feed everyone sees.', actions: {
    post: 'add_feed_post', react: 'add_feed_reaction', comment: 'add_feed_comment' } },
  special_events: { desc: 'Key dates (birthdays, anniversaries, custom occasions).', actions: {
    list: 'get_special_events', add: 'add_special_event', update: 'update_special_event', delete: 'delete_special_event' } },
};

// Distinct enough to stay on their own rather than wrap in a one-action domain.
const STANDALONE = ['get_addresses', 'remember', 'update_my_name', 'send_message'];

// Reverse index: underlying handler name -> where it now lives in the model
// surface. Used to rewrite "Use get_calendar first…" style references (which
// point at bare tools the model no longer sees) into the new action form.
const REVERSE = new Map();
for (const [groupName, group] of Object.entries(GROUPS)) {
  for (const [action, toolName] of Object.entries(group.actions)) REVERSE.set(toolName, { group: groupName, action });
}
// Longest names first so "get_lists" wins over "get_list", and a single regex
// pass so text we insert (which may itself contain a tool name) isn't re-matched.
const REVERSE_RE = new RegExp(
  [...REVERSE.keys()].sort((a, b) => b.length - a.length).map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'),
  'g');

function humanizeRefs(text, currentGroup) {
  return text.replace(REVERSE_RE, (match) => {
    const loc = REVERSE.get(match);
    return loc.group === currentGroup
      ? `action "${loc.action}"`
      : `the ${loc.group} tool (action "${loc.action}")`;
  });
}

// Build one model-facing tool per domain: an `action` enum plus the union of its
// handlers' input properties. Per-action required fields are validated at run
// time (the merged schema can't express "required only for action X").
function buildGroupTool(name, group) {
  const actions = Object.entries(group.actions);
  const properties = { action: { type: 'string', enum: actions.map(([a]) => a), description: 'Which operation to perform.' } };
  const requiredByAction = {};
  const actionLines = [];
  let write = false;
  for (const [action, toolName] of actions) {
    const impl = BY_NAME.get(toolName);
    if (!impl) throw new Error(`Concierge group "${name}" references unknown tool "${toolName}"`);
    if (impl.write) write = true;
    const req = impl.input_schema.required || [];
    requiredByAction[action] = req;
    for (const [key, schema] of Object.entries(impl.input_schema.properties || {})) {
      if (key === 'action') continue;
      if (!properties[key]) {
        properties[key] = schema;
      } else if (JSON.stringify(properties[key]) !== JSON.stringify(schema)) {
        // Same field name means different things across actions — relax to a
        // plain type so neither action is over-constrained (enums are only hints;
        // handlers read the raw value themselves).
        properties[key] = { type: schema.type || properties[key].type || 'string' };
      }
    }
    actionLines.push(`${action}${req.length ? ` (needs ${req.join(', ')})` : ''}: ${humanizeRefs(impl.description, name)}`);
  }
  const description = `${group.desc} Choose action: ${actions.map(([a]) => a).join(' | ')}.\n${actionLines.join('\n')}`;
  return {
    name,
    description,
    write,
    input_schema: { type: 'object', properties, required: ['action'] },
    _actions: group.actions,
    _requiredByAction: requiredByAction,
  };
}

const GROUP_TOOLS = new Map(Object.entries(GROUPS).map(([n, g]) => [n, buildGroupTool(n, g)]));

// Assert full, non-overlapping coverage: every handler is routed exactly once.
{
  const routed = new Set();
  for (const g of Object.values(GROUPS)) {
    for (const toolName of Object.values(g.actions)) {
      if (routed.has(toolName)) throw new Error(`Concierge tool "${toolName}" routed by more than one group`);
      routed.add(toolName);
    }
  }
  for (const n of STANDALONE) routed.add(n);
  const missing = TOOLS.map(t => t.name).filter(n => !routed.has(n));
  if (missing.length) throw new Error(`Concierge tools not exposed to the model: ${missing.join(', ')}`);
}

// Anthropic tool definitions (schema only) — the consolidated surface.
function definitions() {
  const groupDefs = [...GROUP_TOOLS.values()].map(({ name, description, input_schema }) => ({ name, description, input_schema }));
  const standaloneDefs = STANDALONE.map(n => {
    const { name, description, input_schema } = BY_NAME.get(n);
    return { name, description: humanizeRefs(description, null), input_schema };
  });
  return [...groupDefs, ...standaloneDefs];
}

// Run a tool by name; never throws — errors become a result the model can
// recover from. Accepts a domain tool ({action, ...}) or a bare handler name
// (kept for backward compatibility / internal callers).
async function run(name, ctx, input) {
  input = input || {};
  const group = GROUP_TOOLS.get(name);
  if (group) {
    const action = input.action;
    const toolName = action && group._actions[action];
    if (!toolName) {
      return { result: { error: `Unknown action "${action}" for ${name}. Valid actions: ${Object.keys(group._actions).join(', ')}` } };
    }
    const missing = (group._requiredByAction[action] || []).filter(k => {
      const v = input[k];
      return v === undefined || v === null || v === '';
    });
    if (missing.length) {
      return { result: { error: `Missing required field(s) for ${name} "${action}": ${missing.join(', ')}` } };
    }
    const { action: _drop, ...rest } = input;
    try {
      return await BY_NAME.get(toolName).run(ctx, rest);
    } catch (err) {
      return { result: { error: err.message } };
    }
  }
  const tool = BY_NAME.get(name);
  if (!tool) return { result: { error: `Unknown tool: ${name}` } };
  try {
    return await tool.run(ctx, input);
  } catch (err) {
    return { result: { error: err.message } };
  }
}

module.exports = { definitions, run, TOOLS };
