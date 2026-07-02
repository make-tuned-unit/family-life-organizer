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
  if (!DATE_RE.test(String(value || ''))) {
    throw new Error(`${field} must be in YYYY-MM-DD format`);
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
    description: "Save a durable fact about the household for future conversations (e.g. preferences, recurring responsibilities, allergies). Use only for genuinely lasting facts.",
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
        with_person: { type: 'string' },
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
    description: 'Create a note. Private by default; set shared=true to share it with the household.',
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
];

// Fail fast on duplicate tool names — Anthropic 400-rejects a tools array with
// duplicates, which would break every concierge chat turn (silent until runtime).
{
  const seen = new Set();
  const dupes = TOOLS.map(t => t.name).filter(n => seen.size === seen.add(n).size);
  if (dupes.length) throw new Error(`Duplicate concierge tool name(s): ${[...new Set(dupes)].join(', ')}`);
}

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
