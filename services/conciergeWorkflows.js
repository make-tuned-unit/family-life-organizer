// Additional non-Settings operations. Each operation is exposed through the
// existing domain registry, uses FamilyDB, and checks visibility before reads
// as well as writes. No model-supplied owner/group ids are trusted.
const sleepStats = require('./sleepStats');
const id = { type: 'integer', minimum: 1 };
const str = { type: 'string' };
const text = { type: 'string', minLength: 1, maxLength: 10000 };
const page = { limit: { type: 'integer', minimum: 1, maximum: 100 }, before_id: id, after_id: id };
const sqlGet = (c, sql, p = []) => new Promise((r, j) => c.db.db.get(sql, p, (e, x) => e ? j(e) : r(x)));
const sqlRun = (c, sql, p = []) => new Promise((r, j) => c.db.db.run(sql, p, function(e) { e ? j(e) : r({ changed: this.changes }); }));
async function groupRow(c, table, rowId) {
  const row = await sqlGet(c, `SELECT * FROM ${table} WHERE id = ?`, [rowId]);
  if (!row || !row.group_id || !await c.db.isGroupMember(row.group_id, c.userId)) throw new Error('Not found');
  if (table === 'feed_posts' && await c.db.isUserBlocked(c.userId, row.author_id)) throw new Error('Not found');
  return row;
}
async function partner(c, partnerId) {
  if (await c.db.isUserBlocked(c.userId, partnerId)) throw new Error('No accessible conversation');
  const row = await sqlGet(c, `SELECT 1 FROM group_members a JOIN group_members b ON a.group_id = b.group_id WHERE a.user_id = ? AND b.user_id = ? LIMIT 1`, [c.userId, partnerId]);
  if (!row || partnerId === c.userId) throw new Error('No accessible conversation');
}
function createTools({ assertHousehold, assertListAccess, assertRoutineAccess, requireDate }) {
  const out = [];
  const add = (name, description, properties, required, work, write = false) => out.push({
    name, description, write, input_schema: { type: 'object', properties, required },
    async run(c, input) {
      const result = await work(c, input);
      if (!write) return { result };
      const summary = name.replace(/_/g, ' ');
      return { result: { ok: true, ...result, summary }, action: { tool: name, summary } };
    },
  });
  const house = c => { if (!c.groupId) throw new Error('Join a household first'); };
  const ownerRoutine = async (c, rid) => {
    await assertRoutineAccess(c, rid);
    const r = await c.db.getRoutineById(rid);
    if (r.created_by !== c.userId) throw new Error('Only the creator can do this');
    return r;
  };
  add('get_event_attachments', 'Read attachments for a calendar event.', { appointment_id: id }, ['appointment_id'], async (c, i) => {
    await assertHousehold(c, 'appointments', i.appointment_id);
    return c.db.getEventAttachments(i.appointment_id, c.userId);
  });
  add('add_event_attachment', 'Attach an existing item to a shared calendar event. Ask before sharing a private note.', { appointment_id: id, attachment_id: id, attachment_type: { type: 'string', enum: ['list', 'note', 'decision', 'receipt', 'trip', 'itinerary', 'task'] } }, ['appointment_id', 'attachment_id', 'attachment_type'], async (c, i) => {
    await assertHousehold(c, 'appointments', i.appointment_id);
    if (i.attachment_type === 'list') await assertListAccess(c, i.attachment_id);
    else if (i.attachment_type === 'note') {
      // A private note must first be shared through its native workflow; merely
      // knowing its id must not leak its contents through a shared event.
      const note = await groupRow(c, 'notes', i.attachment_id);
      if (note.shared_scope === 'private' || note.group_id !== c.groupId) throw new Error('Share the note with this household first');
    } else {
      const tables = { decision: 'decisions', receipt: 'receipts', trip: 'trips', itinerary: 'itineraries', task: 'tasks' };
      await assertHousehold(c, tables[i.attachment_type], i.attachment_id);
    }
    return c.db.addEventAttachment({ ...i, group_id: c.groupId, added_by: c.userId });
  }, true);
  add('delete_event_attachment', 'Detach an item without deleting the source item.', { appointment_id: id, attachment_id: id }, ['appointment_id', 'attachment_id'], async (c, i) => {
    await assertHousehold(c, 'appointments', i.appointment_id);
    return c.db.deleteEventAttachment(i.attachment_id, i.appointment_id);
  }, true);
  for (const pinned of [true, false]) add(pinned ? 'pin_list' : 'unpin_list', 'Set the household pinned list.', { list_id: id }, ['list_id'], async (c, i) => {
    await assertListAccess(c, i.list_id);
    if (pinned) await sqlRun(c, `UPDATE lists SET pinned = 0 WHERE pinned = 1 AND (created_by = ? OR created_by IN (SELECT gm.user_id FROM group_members gm JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household' WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)))`, [c.userId, c.userId]);
    return c.db.updateList(i.list_id, { pinned: pinned ? 1 : 0 });
  }, true);
  add('reorder_list_items', 'Reorder items within a list by their ids.', { list_id: id, ordered_ids: { type: 'array', items: id, uniqueItems: true, maxItems: 500 } }, ['list_id', 'ordered_ids'], async (c, i) => {
    await assertListAccess(c, i.list_id);
    for (const itemId of i.ordered_ids) {
      const item = await sqlGet(c, 'SELECT list_id FROM list_items WHERE id = ?', [itemId]);
      if (!item || item.list_id !== i.list_id) throw new Error('Item is not in this list');
    }
    return c.db.reorderListItems(i.list_id, i.ordered_ids);
  }, true);
  add('get_project_expenses', 'Read expenses on a budget project.', { project_id: id }, ['project_id'], async (c, i) => {
    await assertHousehold(c, 'budget_projects', i.project_id);
    return c.db.getProjectExpenses(i.project_id, c.groupId);
  });
  add('update_decision', 'Edit a decision or poll.', { id, title: text, body: str, status: { type: 'string', enum: ['active', 'resolved', 'expired'] }, poll_options: { type: 'array', items: str, maxItems: 30 }, link_url: str, expires_at: str, person_id: { type: ['integer', 'null'], minimum: 1 } }, ['id'], async (c, i) => {
    await groupRow(c, 'decisions', i.id);
    if (i.person_id) await assertHousehold(c, 'gift_people', i.person_id);
    return c.db.updateDecision(i.id, i);
  }, true);
  for (const [name, method] of [['get_decision_reactions', 'getDecisionReactions'], ['get_decision_comments', 'getDecisionComments']]) add(name, 'Read a decision discussion or votes.', { id }, ['id'], async (c, i) => {
    await groupRow(c, 'decisions', i.id); return c.db[method](i.id);
  });
  const address = { name: text, address: str, lat: { type: ['number', 'null'], minimum: -90, maximum: 90 }, lng: { type: ['number', 'null'], minimum: -180, maximum: 180 } };
  add('add_address', 'Save a named household address.', address, ['name', 'address'], async (c, i) => { house(c); return c.db.addFamilyAddress({ ...i, group_id: c.groupId }); }, true);
  add('update_address', 'Edit a saved household address.', { id, ...address }, ['id'], async (c, i) => {
    await assertHousehold(c, 'family_addresses', i.id);
    const keys = Object.keys(address).filter(k => i[k] !== undefined);
    if (!keys.length) throw new Error('Nothing to update');
    return sqlRun(c, `UPDATE family_addresses SET ${keys.map(k => `${k} = ?`).join(', ')} WHERE id = ?`, [...keys.map(k => i[k]), i.id]);
  }, true);
  add('delete_address', 'Delete a saved household address.', { id }, ['id'], async (c, i) => { await assertHousehold(c, 'family_addresses', i.id); return c.db.deleteFamilyAddress(i.id); }, true);
  add('get_pending_stay_requests', 'Read hosting requests awaiting your response.', {}, [], c => c.db.getPendingStayRequests(c.userId));
  add('get_itinerary_expenses', 'Read expenses for an itinerary.', { itinerary_id: id }, ['itinerary_id'], async (c, i) => { await groupRow(c, 'itineraries', i.itinerary_id); const expenses = await c.db.getItineraryExpenses(i.itinerary_id); return { expenses, total: expenses.reduce((sum, e) => sum + (Number(e.amount) || 0), 0), count: expenses.length }; });
  add('update_rivalry', 'Edit a competition configuration. Use complete to declare a winner.', { id, title: text, challenge_type: str, start_date: str, end_date: str, point_value: { type: 'integer', minimum: 0 }, participants: { type: 'array', items: str }, rivalry_type: { type: 'string', enum: ['individual', 'team'] }, team_a: { type: 'array', items: str }, team_b: { type: 'array', items: str } }, ['id'], async (c, i) => {
    const old = await groupRow(c, 'rivalries', i.id);
    for (const k of ['start_date', 'end_date']) if (i[k]) requireDate(i[k], k);
    if ((i.end_date || old.end_date) < (i.start_date || old.start_date)) throw new Error('End date precedes start');
    const fields = { ...i };
    for (const k of ['participants', 'team_a', 'team_b']) if (fields[k]) fields[k] = JSON.stringify(fields[k]);
    return c.db.updateRivalry(i.id, fields);
  }, true);
  add('get_rivalry_entries', 'Read a competition score history.', { id }, ['id'], async (c, i) => { await groupRow(c, 'rivalries', i.id); return c.db.getRivalryEntries(i.id); });
  add('get_rivalry_leaderboard', 'Read the leaderboard across your groups.', {}, [], c => c.db.getRivalryLeaderboard(c.userId));
  add('get_coverage_blocks', 'Read your approved care calendar blocks.', { date_from: str, date_to: str }, [], async (c, i) => {
    for (const k of ['date_from', 'date_to']) if (i[k]) requireDate(i[k], k);
    return c.db.getCoverageBlocks(c.userId, i.date_from, i.date_to);
  });
  add('get_coverage_detail', 'Read a coverage request you made or received. Invite tokens are excluded.', { id }, ['id'], async (c, i) => {
    const row = await c.db.getCoverageRequestById(i.id);
    if (!row || (row.requester_id !== c.userId && !await c.db.getRecipientByUserId(i.id, c.userId))) throw new Error('Not found');
    const recipients = (await c.db.getCoverageRecipients(i.id)).map(({ invite_token, ...r }) => r);
    return { ...row, recipients, windows: await c.db.getCoverageWindows(i.id), approvals: await c.db.getCoverageApprovals(i.id) };
  });
  const routine = { name: text, subject_name: str, subject_birthdate: { type: ['string', 'null'] }, config: { type: 'object', additionalProperties: true }, color: str, icon: str, start_date: str };
  const validateRoutine = i => { for (const k of ['subject_birthdate', 'start_date']) if (i[k]) requireDate(i[k], k); };
  add('create_routine', 'Create a private routine. Sharing requires the separate share action with explicit confirmation.', { ...routine, routine_type: { type: 'string', enum: ['period', 'baby_sleep', 'sleep_training', 'activity', 'chores', 'custom'] } }, ['name', 'routine_type'], async (c, i) => {
    house(c); validateRoutine(i); return c.db.createRoutine({ ...i, group_id: c.groupId, created_by: c.userId, shared_scope: 'private', start_date: i.start_date || c.today });
  }, true);
  add('update_routine', 'Edit a routine you can access. Does not change privacy or archive status.', { id, ...routine }, ['id'], async (c, i) => { await assertRoutineAccess(c, i.id); validateRoutine(i); return c.db.updateRoutine(i.id, i); }, true);
  add('delete_routine', 'Delete your routine and its history. Confirm first.', { id }, ['id'], async (c, i) => {
    await ownerRoutine(c, i.id); await c.db.deleteRoutine(i.id); await c.db.deleteFeedPostsByReference('routine', i.id);
  }, true);
  add('set_routine_shared', 'Change your routine privacy. Ask for explicit confirmation before sharing health or private history.', { id, shared: { type: 'boolean' } }, ['id', 'shared'], async (c, i) => {
    const row = await ownerRoutine(c, i.id);
    const scope = i.shared ? 'household' : 'private';
    const result = await c.db.setRoutineScope(i.id, c.userId, scope);
    if (!i.shared) await c.db.deleteFeedPostsByReference('routine', i.id);
    else if (row.shared_scope !== scope && result.changed) await c.db.addFeedPost({ group_id: row.group_id, author_id: c.userId, post_type: 'routine', title: `Shared a routine: ${row.name}`, body: row.subject_name ? `For ${row.subject_name}` : null, reference_type: 'routine', reference_id: i.id });
    return result;
  }, true);
  add('update_routine_entry', 'Correct an entry, including sleep start/end times. Sleep duration is recomputed.', { routine_id: id, entry_id: id, entry_date: str, entry_time: str, notes: str, start_time: str, end_time: str, wake_count: { type: 'integer', minimum: 0 } }, ['routine_id', 'entry_id'], async (c, i) => {
    await assertRoutineAccess(c, i.routine_id);
    const entry = await c.db.getRoutineEntryById(i.entry_id);
    if (!entry || entry.routine_id !== i.routine_id) throw new Error('Not found');
    const updates = {};
    if (i.entry_date) updates.entry_date = requireDate(i.entry_date, 'entry_date');
    if (i.notes !== undefined) updates.notes = i.notes || null;
    if (i.start_time || i.end_time) {
      const span = sleepStats.span(updates.entry_date || entry.entry_date, i.start_time, i.end_time);
      if (!span) throw new Error('Both sleep times must be HH:MM');
      updates.value = { sleep_start: span.start, sleep_end: span.end, duration_minutes: span.minutes, ...(i.wake_count == null ? {} : { wake_count: i.wake_count }) };
      updates.entry_time = span.startTime;
    } else if (i.entry_time) {
      if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(i.entry_time)) throw new Error('entry_time must be HH:MM');
      updates.entry_time = i.entry_time;
    }
    return c.db.updateRoutineEntry(i.entry_id, i.routine_id, updates);
  }, true);
  add('delete_routine_entry', 'Delete a routine entry.', { routine_id: id, entry_id: id }, ['routine_id', 'entry_id'], async (c, i) => {
    await assertRoutineAccess(c, i.routine_id);
    const entry = await c.db.getRoutineEntryById(i.entry_id);
    if (!entry || entry.routine_id !== i.routine_id) throw new Error('Not found');
    return c.db.deleteRoutineEntry(i.entry_id, i.routine_id);
  }, true);
  add('get_feed', 'Read household or clan feed with pagination.', { group_id: id, ...page }, [], async (c, i) => {
    const gid = i.group_id || c.groupId;
    if (!gid || !await c.db.isGroupMember(gid, c.userId)) throw new Error('Not found');
    return c.db.getFeedPosts(gid, { ...i, userId: c.userId });
  });
  add('delete_feed_post', 'Delete a post you authored.', { post_id: id }, ['post_id'], async (c, i) => {
    const post = await groupRow(c, 'feed_posts', i.post_id);
    if (post.author_id !== c.userId) throw new Error('Only the author can delete a post');
    return c.db.deleteFeedPost(i.post_id);
  }, true);
  for (const [name, method] of [['get_feed_reactions', 'getFeedReactions'], ['get_feed_comments', 'getFeedComments']]) add(name, 'Read reactions or comments on an accessible feed post.', { post_id: id }, ['post_id'], async (c, i) => { await groupRow(c, 'feed_posts', i.post_id); return c.db[method](i.post_id, c.userId); });
  add('remove_feed_reaction', 'Remove your reaction from a feed post.', { post_id: id }, ['post_id'], async (c, i) => { await groupRow(c, 'feed_posts', i.post_id); return c.db.removeFeedReaction(i.post_id, c.userId); }, true);
  add('get_conversations', 'Read your direct message conversation list.', {}, [], async c => {
    const visible = [];
    for (const row of await c.db.getConversations(c.userId)) { try { await partner(c, row.partner_id); visible.push(row); } catch {} }
    return visible;
  });
  add('get_messages', 'Read your messages with a group member. Does not mark them read.', { partner_id: id, ...page }, ['partner_id'], async (c, i) => { await partner(c, i.partner_id); return c.db.getMessages(c.userId, i.partner_id, i); });
  add('mark_messages_read', 'Mark messages from a group member as read.', { partner_id: id }, ['partner_id'], async (c, i) => { await partner(c, i.partner_id); return c.db.markRead(c.userId, i.partner_id); }, true);
  add('get_memory', 'Review remembered household facts, including ids for selective deletion.', {}, [], async c => { house(c); return c.db.getConciergeMemory(c.groupId); });
  add('delete_memory', 'Forget one household fact by id. Confirm which fact first.', { id }, ['id'], async (c, i) => { await assertHousehold(c, 'concierge_memory', i.id); return sqlRun(c, 'DELETE FROM concierge_memory WHERE id = ? AND group_id = ?', [i.id, c.groupId]); }, true);
  add('get_budget_stats', 'Read budget history and spending insights.', { months: { type: 'integer', minimum: 1, maximum: 24 } }, [], async (c, i) => { house(c); return require('./budgetStats').getBudgetStats(c.db, c.groupId, i.months || 6); });
  add('get_routine_occurrences', 'Read calendar occurrences and attendance for a routine.', { id }, ['id'], async (c, i) => { await assertRoutineAccess(c, i.id); return require('./routineOccurrences').getRoutineOccurrences(c.db, i.id, c.userId); });
  add('request_stay', 'Send a hosting request for your itinerary stay. Confirm host and dates before sending.', { stay_id: id }, ['stay_id'], (c, i) => require('./stayWorkflow').requestStay(c, i.stay_id), true);
  add('respond_to_stay', 'As the host, approve or decline a requested stay; approval adds both calendar events. Confirm first.', { stay_id: id, approved: { type: 'boolean' } }, ['stay_id', 'approved'], (c, i) => require('./stayWorkflow').respondToStay(c, i.stay_id, i.approved), true);
  add('get_blocked_users', 'Review members you have blocked.', {}, [], c => c.db.getBlockedUsers(c.userId));
  add('block_user', 'Block a group member from messaging you and hide their posts. Confirm which person first.', { user_id: id }, ['user_id'], async (c, i) => {
    if (i.user_id === c.userId) throw new Error('Cannot block yourself');
    const shared = await sqlGet(c, 'SELECT 1 FROM group_members a JOIN group_members b ON a.group_id = b.group_id WHERE a.user_id = ? AND b.user_id = ?', [c.userId, i.user_id]);
    if (!shared) throw new Error('Member not found');
    return c.db.setUserBlocked(c.userId, i.user_id, true);
  }, true);
  add('unblock_user', 'Remove your block on a member. Their own block, if any, remains effective.', { user_id: id }, ['user_id'], (c, i) => c.db.setUserBlocked(c.userId, i.user_id, false), true);
  return out;
}
module.exports = { createTools };
