// Concierge tool registry.
// Each tool exposes an Anthropic tool schema plus a `run(ctx, input)` handler
// that calls existing FamilyDB methods. ctx = { db, userId, userName, groupId, push }.
//
// SAFETY BOUNDARY: tools read, add, edit, and change status across every
// domain — but never DELETE. The butler can manage the whole app without ever
// losing data (the worst case is an edit, which is recoverable).

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

  // ---- Groceries (list / purchase) ----
  {
    name: 'list_groceries',
    description: 'List items on the shared grocery list. status "needed" (default) or "purchased".',
    write: false,
    input_schema: {
      type: 'object',
      properties: { status: { type: 'string', enum: ['needed', 'purchased'] } },
    },
    async run(ctx, input) {
      const rows = await ctx.db.getGroceries(input.status || 'needed', ctx.userId);
      return { result: rows.slice(0, 60).map(g => ({ id: g.id, item: g.item, quantity: g.quantity, category: g.category })) };
    },
  },
  {
    name: 'purchase_grocery',
    description: 'Mark a grocery item as purchased. Use list_groceries first for the id.',
    write: true,
    input_schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    async run(ctx, input) {
      await ctx.db.purchaseGrocery(input.id);
      const summary = `Marked grocery #${input.id} as purchased`;
      return { result: { ok: true, summary }, action: { tool: 'purchase_grocery', summary } };
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
      const rows = await ctx.db.getTrips(filters);
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
      const rows = await ctx.db.getRivalries(filters, ctx.userId);
      const out = [];
      for (const r of rows.slice(0, 20)) {
        let totals = [];
        try { totals = await ctx.db.getRivalryEntryTotals(r.id); } catch { /* ignore */ }
        out.push({
          id: r.id, title: r.title, type: r.challenge_type, status: r.status,
          start_date: r.start_date, end_date: r.end_date,
          totals: totals.map(t => ({ member: t.member_name, total: t.total })),
        });
      }
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
      const rows = await ctx.db.getGiftPeople();
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
      const rows = await ctx.db.getGiftIdeas(input.person_id || null);
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
      const rows = await ctx.db.getFamilyAddresses();
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
