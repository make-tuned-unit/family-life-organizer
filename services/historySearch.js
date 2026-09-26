// Search retained records, with the same household/owner/group boundaries as
// their normal screens. Never search photos, raw tokens or another user's DMs.
const { visibleAuthor } = require('./socialSafety');
const FamilyDB = require('../database');
const SOURCES = ['calendar', 'receipts', 'lists', 'tasks', 'notes', 'routines', 'itineraries', 'milestones', 'decisions', 'special_events', 'messages', 'contacts', 'trips', 'pantry', 'gifts', 'project_expenses'];
const all = (db, sql, params) => new Promise((resolve, reject) => db.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows)));
async function searchHistory(ctx, input) {
  if (!ctx.userId || !ctx.groupId) throw new Error('A household is required');
  const h = ctx.groupId, u = ctx.userId;
  const giftVis = FamilyDB.giftIdeaVisibleSql('g', u);   // surprise rule
  const sources = {
    messages: [`SELECT d.id, 'Message: ' || sender.name || ' to ' || recipient.name AS title, d.created_at AS date, d.text AS detail, 'Your direct-message history' AS evidence FROM direct_messages d JOIN users sender ON sender.id = d.sender_id JOIN users recipient ON recipient.id = d.recipient_id WHERE (d.sender_id = ? OR d.recipient_id = ?) AND ${visibleAuthor('d.sender_id', u)} AND ${visibleAuthor('d.recipient_id', u)}`, [u, u]],
    contacts: ["SELECT id, name AS title, created_at AS date, COALESCE(relationship,'') || ' ' || COALESCE(notes,'') AS detail, 'Your saved contact' AS evidence FROM contacts WHERE added_by = ?", [u]],
    trips: ["SELECT id, traveler || ': ' || destination AS title, started_at AS date, COALESCE(origin,'') || ' ' || COALESCE(purpose,'') || ' Status: ' || status AS detail, 'Household trip record' AS evidence FROM trips WHERE group_id = ?", [h]],
    pantry: ["SELECT id, item AS title, created_at AS date, COALESCE(quantity,'') || ' ' || COALESCE(location,'') AS detail, 'Current pantry record, not purchase proof' AS evidence FROM pantry WHERE group_id = ?", [h]],
    gifts: [`SELECT g.id, g.title, g.created_at AS date, COALESCE(g.notes,'') || ' Status: ' || g.status AS detail, 'Gift idea record' AS evidence FROM gift_ideas g WHERE g.group_id = ? AND ${giftVis[0]}`, [h, ...giftVis[1]]],
    project_expenses: ["SELECT e.id, p.name || ': ' || e.description AS title, e.created_at AS date, 'Amount: ' || e.amount || ' ' || COALESCE(e.notes,'') AS detail, 'Project expense' AS evidence FROM project_expenses e JOIN budget_projects p ON p.id = e.project_id WHERE p.group_id = ?", [h]],
    calendar: ["SELECT id, title, appointment_date AS date, COALESCE(location,'') || ' ' || COALESCE(description,'') || ' ' || COALESCE(with_person,'') AS detail, 'Calendar event' AS evidence FROM appointments WHERE group_id = ?", [h]],
    receipts: ["SELECT id, merchant AS title, date, 'Total: ' || amount || '; ' || COALESCE(category,'') || '; ' || COALESCE(notes,'') AS detail, 'Saved receipt; item details only where recorded in notes' AS evidence FROM receipts WHERE group_id = ?", [h]],
    lists: [`SELECT i.id, l.name || ': ' || i.title AS title, COALESCE(i.completed_at, i.created_at) AS date,
      CASE WHEN i.is_done = 1 THEN 'Checked off list' ELSE 'Unchecked list item' END AS detail,
      'List status, not proof of a store purchase' AS evidence FROM list_items i JOIN lists l ON l.id = i.list_id
      WHERE l.created_by = ? OR l.created_by IN (SELECT user_id FROM group_members WHERE group_id = ?)`, [u, h]],
    tasks: ["SELECT id, title, COALESCE(completed_at, due_date, created_at) AS date, COALESCE(description,'') || ' Status: ' || status AS detail, 'Task record' AS evidence FROM tasks WHERE group_id = ?", [h]],
    notes: [`SELECT id, COALESCE(title,'Note') AS title, created_at AS date, body AS detail, 'Saved note' AS evidence FROM notes
      WHERE user_id = ? OR (shared_scope IN ('household','group') AND group_id IN (SELECT group_id FROM group_members WHERE user_id = ?))`, [u, u]],
    routines: [`SELECT e.id, r.name || COALESCE(' · ' || r.subject_name,'') AS title, e.entry_date AS date,
      COALESCE(e.entry_type,'') || ' ' || COALESCE(e.value,'') || ' ' || COALESCE(e.notes,'') AS detail,
      CASE WHEN r.active = 0 THEN 'Archived routine entry' ELSE 'Routine entry' END AS evidence
      FROM routine_entries e JOIN routines r ON r.id = e.routine_id
      WHERE r.group_id = ? AND (r.created_by = ? OR r.shared_scope = 'household')`, [h, u]],
    itineraries: [`SELECT id, title, start_date AS date, end_date || ' ' || COALESCE(travelers,'') || ' ' || COALESCE(notes,'') AS detail, 'Shared itinerary' AS evidence FROM itineraries
      WHERE traveler_id = ? OR group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)`, [u, u]],
    milestones: ["SELECT id, title, milestone_date AS date, description AS detail, 'Milestone' AS evidence FROM milestones WHERE group_id = ? AND (COALESCE(shared_scope,'household') != 'private' OR created_by = ?)", [h, u]],
    decisions: ["SELECT id, title, created_at AS date, COALESCE(body,'') || ' Status: ' || status AS detail, 'Decision record' AS evidence FROM decisions WHERE group_id = ?", [h]],
    special_events: ["SELECT id, title, date, notes AS detail, 'Key date' AS evidence FROM special_events WHERE group_id = ? AND (COALESCE(shared_scope,'household') != 'private' OR created_by = ?)", [h, u]],
  };
  const selected = input.source && input.source !== 'all' ? [input.source] : SOURCES;
  const params = [];
  const union = selected.map(source => {
    const [sql, bindings] = sources[source]; params.push(...bindings);
    return `SELECT '${source}' AS source, record.* FROM (${sql}) record`;
  }).join(' UNION ALL ');
  let where = ' WHERE 1=1';
  if (input.date_from) { where += ' AND substr(date,1,10) >= ?'; params.push(input.date_from); }
  if (input.date_to) { where += ' AND substr(date,1,10) <= ?'; params.push(input.date_to); }
  // Literal substring matching: '%' and '_' are not wildcard backdoors.
  for (const term of [input.query, input.merchant].filter(Boolean)) {
    where += " AND instr(lower(COALESCE(title,'') || ' ' || COALESCE(detail,'')), lower(?)) > 0";
    params.push(term.trim());
  }
  const limit = input.limit || 30, offset = input.offset || 0;
  const rows = await all(ctx.db, `SELECT * FROM (${union})${where} ORDER BY date DESC, source, id DESC LIMIT ? OFFSET ?`, [...params, limit + 1, offset]);
  return { records: rows.slice(0, limit), next_offset: rows.length > limit ? offset + limit : null,
    scope: 'Retained records you can access. Deleted records and unrecorded purchases cannot be recovered. Calendar rows are saved series origins; use calendar list for recurring occurrences.',
    purchase_guidance: 'Receipt notes may include scanned line items. A checked list item is weaker evidence than a receipt. No matching record is not proof that an item was not purchased.' };
}
module.exports = { searchHistory, SOURCES };
