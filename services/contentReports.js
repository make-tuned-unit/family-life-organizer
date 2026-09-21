const get = (db, sql, params = []) => new Promise((resolve, reject) => db.db.get(sql, params, (error, row) => error ? reject(error) : resolve(row)));
const all = (db, sql, params = []) => new Promise((resolve, reject) => db.db.all(sql, params, (error, rows) => error ? reject(error) : resolve(rows)));
const run = (db, sql, params = []) => new Promise((resolve, reject) => db.db.run(sql, params, function(error) { error ? reject(error) : resolve({ id: this.lastID, changed: this.changes }); }));

// The receipt and notification job commit together. Jobs carry only a report
// id; delivery rereads the row so erased/resolved reports cannot be re-sent.
async function create(db, { reporterId, type, refId, reason }) {
  return db.transaction(async tx => {
    const report = await run(tx, 'INSERT INTO content_reports (reporter_id, content_type, ref_id, reason) VALUES (?, ?, ?, ?)', [reporterId, type, refId, reason]);
    await tx.enqueueJob({ kind: 'content_report', payload: { reportId: report.id }, maxAttempts: 8 });
    return report;
  });
}

async function listOpen(db) {
  return all(db, `SELECT r.*, CAST((julianday('now') - julianday(r.created_at)) * 24 AS INTEGER) AS age_hours
    FROM content_reports r LEFT JOIN content_report_reviews v ON v.report_id = r.id
    WHERE v.report_id IS NULL ORDER BY r.created_at, r.id LIMIT 500`);
}

async function status(db) {
  return get(db, `SELECT COUNT(*) AS open,
    COALESCE(SUM(r.created_at <= datetime('now', '-24 hours')), 0) AS overdue,
    COALESCE(SUM(EXISTS (SELECT 1 FROM jobs j WHERE j.kind = 'content_report' AND j.status = 'failed'
      AND json_valid(j.payload) AND json_extract(j.payload, '$.reportId') = r.id)), 0) AS delivery_failed
    FROM content_reports r LEFT JOIN content_report_reviews v ON v.report_id = r.id WHERE v.report_id IS NULL`);
}

// Operator-only CLI; no public moderation endpoint or model tool can call this.
async function resolve(db, reportId, { decision, operator }) {
  if (!['remove', 'dismiss'].includes(decision) || !operator?.trim()) throw new Error('An explicit decision and operator are required');
  return db.transaction(async tx => {
    const report = await get(tx, 'SELECT * FROM content_reports WHERE id = ?', [reportId]);
    if (!report) throw new Error('Report not found');
    if (await get(tx, 'SELECT 1 FROM content_report_reviews WHERE report_id = ?', [reportId])) throw new Error('Report already resolved');
    if (decision === 'remove') {
      if (report.content_type === 'message') {
        const message = await get(tx, 'SELECT sender_id, recipient_id FROM direct_messages WHERE id = ?', [report.ref_id]);
        if (message) await run(tx, `DELETE FROM jobs WHERE kind = 'push_user' AND json_valid(payload)
          AND json_extract(payload, '$.data.type') = 'message'
          AND CAST(json_extract(payload, '$.userId') AS INTEGER) = ?
          AND CAST(json_extract(payload, '$.data.ref_id') AS INTEGER) = ?`, [message.recipient_id, message.sender_id]);
        await run(tx, 'DELETE FROM direct_messages WHERE id = ?', [report.ref_id]);
      }
      else if (report.content_type === 'feed') {
        const post = await get(tx, 'SELECT author_id, group_id FROM feed_posts WHERE id = ?', [report.ref_id]);
        if (post) await run(tx, `DELETE FROM jobs WHERE kind = 'push_group' AND json_valid(payload)
          AND CAST(json_extract(payload, '$.groupId') AS INTEGER) = ?
          AND CAST(json_extract(payload, '$.excludeUserId') AS INTEGER) = ?`, [post.group_id, post.author_id]);
        await run(tx, 'DELETE FROM feed_comments WHERE post_id = ?', [report.ref_id]);
        await run(tx, 'DELETE FROM feed_reactions WHERE post_id = ?', [report.ref_id]);
        await run(tx, 'DELETE FROM feed_posts WHERE id = ?', [report.ref_id]);
      } else throw new Error('Unsupported report type');
    }
    await run(tx, 'INSERT INTO content_report_reviews (report_id, decision, operator) VALUES (?, ?, ?)', [reportId, decision, operator.trim().slice(0, 100)]);
    return { reportId, decision };
  });
}
module.exports = { create, listOpen, resolve, status, get };
