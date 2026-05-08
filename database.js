#!/usr/bin/env node
/**
 * Family Life Organizer - Database Module
 * Simple SQLite wrapper for household management
 */

const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

// Use Render disk path if available, otherwise use local path
const DB_DIR = process.env.RENDER_DISK_PATH 
  ? '/opt/render/project/src/vault/family-life'
  : path.join(process.env.HOME || '/tmp', '.openclaw/workspace/vault/family-life');
const DB_PATH = path.join(DB_DIR, 'family.db');

// Ensure directory exists
if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

class FamilyDB {
  constructor() {
    this.db = new sqlite3.Database(DB_PATH);
    this.init();
  }

  parseJSONList(value) {
    if (!value) return [];
    try {
      return JSON.parse(value);
    } catch {
      return [];
    }
  }

  init() {
    const schema = fs.readFileSync(
      path.join(__dirname, 'schema.sql'), 
      'utf8'
    );
    
    // Split and execute each statement
    const statements = schema.split(';').filter(s => s.trim());
    for (const stmt of statements) {
      try {
        this.db.exec(stmt + ';');
      } catch (err) {
        // Ignore "already exists" errors - tables/columns already created
        if (!err.message.includes('already exists') && !err.message.includes('duplicate')) {
          console.error('Schema error:', err.message);
        }
      }
    }
  }

  // Task operations
  addTask(task) {
    return new Promise((resolve, reject) => {
      const stmt = this.db.prepare(`
        INSERT INTO tasks (category, title, description, priority, due_date, due_time, assigned_to, recurrence_pattern, tags)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      
      stmt.run([
        task.category,
        task.title,
        task.description || null,
        task.priority || 'medium',
        task.due_date || null,
        task.due_time || null,
        task.assigned_to || null,
        task.recurrence || null,
        task.tags ? task.tags.join(',') : null
      ], function(err) {
        stmt.finalize();
        if (err) reject(err);
        else resolve({ id: this.lastID, ...task });
      });
    });
  }

  getTasks(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM tasks WHERE 1=1';
      const params = [];

      if (filters.category) {
        sql += ' AND category = ?';
        params.push(filters.category);
      }
      if (filters.status) {
        sql += ' AND status = ?';
        params.push(filters.status);
      }
      if (filters.assigned_to) {
        sql += ' AND assigned_to = ?';
        params.push(filters.assigned_to);
      }

      sql += ' ORDER BY created_at DESC';

      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  completeTask(id) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE tasks SET status = "completed", completed_at = CURRENT_TIMESTAMP WHERE id = ?',
        [id],
        (err) => {
          if (err) reject(err);
          else resolve({ id, status: 'completed' });
        }
      );
    });
  }

  // Grocery operations
  addGrocery(item, category = null, quantity = '1') {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO groceries (item, category, quantity) VALUES (?, ?, ?)',
        [item, category, quantity],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, item, category, quantity });
        }
      );
    });
  }

  getGroceries(status = 'needed') {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM groceries WHERE status = ? ORDER BY category, item',
        [status],
        (err, rows) => {
          if (err) reject(err);
          else resolve(rows);
        }
      );
    });
  }

  purchaseGrocery(id) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE groceries SET status = "purchased", purchased_at = CURRENT_TIMESTAMP WHERE id = ?',
        [id],
        (err) => {
          if (err) reject(err);
          else resolve({ id, status: 'purchased' });
        }
      );
    });
  }

  // Appointment operations
  addAppointment(appointment) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO appointments (title, description, appointment_date, appointment_time, location, with_person, category, person_tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          appointment.title,
          appointment.description || null,
          appointment.appointment_date,
          appointment.appointment_time || null,
          appointment.location || null,
          appointment.with_person || null,
          appointment.category || 'appointments',
          appointment.person_tags ? appointment.person_tags.join(',') : null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...appointment });
        }
      );
    });
  }

  getAppointments(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM appointments WHERE 1=1';
      const params = [];

      if (filters.date_from) {
        sql += ' AND appointment_date >= ?';
        params.push(filters.date_from);
      }
      if (filters.date_to) {
        sql += ' AND appointment_date <= ?';
        params.push(filters.date_to);
      }
      if (filters.person) {
        sql += ' AND person_tags LIKE ?';
        params.push('%' + filters.person + '%');
      }

      sql += ' ORDER BY appointment_date, appointment_time';

      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  getAppointmentsByMonth(year, month) {
    return new Promise((resolve, reject) => {
      const startDate = `${year}-${String(month).padStart(2, '0')}-01`;
      const endDate = month === 12 
        ? `${year + 1}-01-01` 
        : `${year}-${String(month + 1).padStart(2, '0')}-01`;
      
      this.db.all(
        'SELECT * FROM appointments WHERE appointment_date >= ? AND appointment_date < ? ORDER BY appointment_date, appointment_time',
        [startDate, endDate],
        (err, rows) => {
          if (err) reject(err);
          else resolve(rows);
        }
      );
    });
  }

  deleteAppointment(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM appointments WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  updateAppointment(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      params.push(id);
      this.db.run(`UPDATE appointments SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  // Receipt operations
  addReceipt(receipt) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO receipts (amount, merchant, date, category, payment_method, image_path, notes, processed_by, email_id, added_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          receipt.amount,
          receipt.merchant,
          receipt.date,
          receipt.category || 'Other',
          receipt.payment_method || null,
          receipt.image_path || null,
          receipt.notes || null,
          receipt.processed_by || 'manual',
          receipt.email_id || null,
          receipt.added_by || 'jesse'
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...receipt });
        }
      );
    });
  }

  getReceipts(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM receipts WHERE 1=1';
      const params = [];

      if (filters.month) {
        sql += ' AND strftime("%Y-%m", date) = ?';
        params.push(filters.month);
      }
      if (filters.category) {
        sql += ' AND category = ?';
        params.push(filters.category);
      }

      sql += ' ORDER BY date DESC, created_at DESC';

      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  deleteReceipt(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM receipts WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  getBudgetSummary(month) {
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT 
          c.name as category,
          c.monthly_limit,
          c.color,
          COALESCE(SUM(r.amount), 0) as spent
        FROM budget_categories c
        LEFT JOIN receipts r ON c.name = r.category AND strftime('%Y-%m', r.date) = ?
        GROUP BY c.name
        ORDER BY c.name
      `;
      this.db.all(sql, [month], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  // Pantry operations
  addPantryItem(item) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO pantry (item, category, location, quantity, unit, expiry_date, receipt_id, added_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [item.item, item.category || null, item.location || 'pantry', item.quantity || '1', item.unit || null, item.expiry_date || null, item.receipt_id || null, item.added_by || 'jesse'],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...item });
        }
      );
    });
  }

  getPantry(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM pantry WHERE 1=1';
      const params = [];
      if (filters.location) { sql += ' AND location = ?'; params.push(filters.location); }
      if (filters.category) { sql += ' AND category = ?'; params.push(filters.category); }
      sql += ' ORDER BY category, item';
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  updatePantryItem(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      fields.push('updated_at = CURRENT_TIMESTAMP');
      params.push(id);
      this.db.run(`UPDATE pantry SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  deletePantryItem(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM pantry WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  // Trip operations
  createTrip(trip) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO trips (traveler, origin, origin_lat, origin_lng, destination, destination_lat, destination_lng, purpose, status, eta_minutes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [trip.traveler, trip.origin || null, trip.origin_lat || null, trip.origin_lng || null, trip.destination, trip.destination_lat || null, trip.destination_lng || null, trip.purpose || null, 'active', trip.eta_minutes || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...trip });
        }
      );
    });
  }

  getTrips(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM trips WHERE 1=1';
      const params = [];
      if (filters.status) { sql += ' AND status = ?'; params.push(filters.status); }
      if (filters.traveler) { sql += ' AND traveler = ?'; params.push(filters.traveler); }
      sql += ' ORDER BY created_at DESC';
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  updateTrip(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      params.push(id);
      this.db.run(`UPDATE trips SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  arriveTrip(id) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE trips SET status = "arrived", arrived_at = CURRENT_TIMESTAMP WHERE id = ?',
        [id], (err) => {
          if (err) reject(err);
          else resolve({ id, status: 'arrived' });
        }
      );
    });
  }

  cancelTrip(id) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE trips SET status = "cancelled" WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, status: 'cancelled' });
      });
    });
  }

  // Family address operations
  addFamilyAddress(addr) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO family_addresses (name, address, lat, lng, radius_meters, created_by) VALUES (?, ?, ?, ?, ?, ?)',
        [addr.name, addr.address || null, addr.lat, addr.lng, addr.radius_meters || 500, addr.created_by || 'jesse'],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...addr });
        }
      );
    });
  }

  getFamilyAddresses() {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT * FROM family_addresses ORDER BY name', (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  deleteFamilyAddress(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM family_addresses WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  // Decision operations
  addDecision(decision) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO decisions (title, decision_type, body, link_url, photo_data, poll_options, creator_name, status, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          decision.title,
          decision.decision_type,
          decision.body || null,
          decision.link_url || null,
          decision.photo_data || null,
          JSON.stringify(decision.poll_options || []),
          decision.creator_name || 'Jesse',
          decision.status || 'active',
          decision.expires_at || null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...decision });
        }
      );
    });
  }

  getDecisions(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM decisions WHERE 1=1';
      const params = [];
      if (filters.status) { sql += ' AND status = ?'; params.push(filters.status); }
      sql += ' ORDER BY datetime(created_at) DESC';
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows.map(row => ({ ...row, poll_options: this.parseJSONList(row.poll_options) })));
      });
    });
  }

  updateDecision(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(key === 'poll_options' ? JSON.stringify(value || []) : value);
      }
      params.push(id);
      this.db.run(`UPDATE decisions SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  getDecisionReactions(decisionId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM decision_reactions WHERE decision_id = ? ORDER BY datetime(created_at) ASC',
        [decisionId],
        (err, rows) => err ? reject(err) : resolve(rows)
      );
    });
  }

  replaceDecisionReaction(decisionId, memberName, reactionType, pollChoice = null) {
    return new Promise((resolve, reject) => {
      this.db.serialize(() => {
        const deleteSql = reactionType === 'vote'
          ? 'DELETE FROM decision_reactions WHERE decision_id = ? AND member_name = ? AND reaction_type = "vote"'
          : 'DELETE FROM decision_reactions WHERE decision_id = ? AND member_name = ? AND reaction_type != "vote"';

        this.db.run(deleteSql, [decisionId, memberName], (deleteErr) => {
          if (deleteErr) return reject(deleteErr);

          this.db.run(
            'INSERT INTO decision_reactions (decision_id, member_name, reaction_type, poll_choice) VALUES (?, ?, ?, ?)',
            [decisionId, memberName, reactionType, pollChoice],
            function(insertErr) {
              if (insertErr) reject(insertErr);
              else resolve({ id: this.lastID, decision_id: decisionId, member_name: memberName, reaction_type: reactionType, poll_choice: pollChoice });
            }
          );
        });
      });
    });
  }

  getDecisionComments(decisionId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM decision_comments WHERE decision_id = ? ORDER BY datetime(created_at) ASC',
        [decisionId],
        (err, rows) => err ? reject(err) : resolve(rows)
      );
    });
  }

  addDecisionComment(decisionId, memberName, text) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO decision_comments (decision_id, member_name, text) VALUES (?, ?, ?)',
        [decisionId, memberName, text],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, decision_id: decisionId, member_name: memberName, text });
        }
      );
    });
  }

  // Rivalry operations
  addRivalry(rivalry) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO rivalries (title, challenge_type, initiator_name, opponent_name, start_date, end_date, status, point_value, winner_name)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          rivalry.title,
          rivalry.challenge_type,
          rivalry.initiator_name,
          rivalry.opponent_name,
          rivalry.start_date,
          rivalry.end_date,
          rivalry.status || 'active',
          rivalry.point_value || 100,
          rivalry.winner_name || null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...rivalry });
        }
      );
    });
  }

  getRivalries(filters = {}) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM rivalries WHERE 1=1';
      const params = [];
      if (filters.status) { sql += ' AND status = ?'; params.push(filters.status); }
      sql += ' ORDER BY datetime(created_at) DESC';
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  updateRivalry(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      params.push(id);
      this.db.run(`UPDATE rivalries SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  getRivalryEntries(rivalryId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM rivalry_entries WHERE rivalry_id = ? ORDER BY datetime(logged_at) DESC',
        [rivalryId],
        (err, rows) => err ? reject(err) : resolve(rows)
      );
    });
  }

  addRivalryEntry(entry) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO rivalry_entries (rivalry_id, member_name, value, note, is_verified)
         VALUES (?, ?, ?, ?, ?)`,
        [entry.rivalry_id, entry.member_name, entry.value, entry.note || null, entry.is_verified ? 1 : 0],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...entry });
        }
      );
    });
  }

  getRivalryLeaderboard() {
    return new Promise((resolve, reject) => {
      const sql = `
        WITH participants AS (
          SELECT initiator_name AS member_name FROM rivalries
          UNION ALL
          SELECT opponent_name AS member_name FROM rivalries
        ),
        completions AS (
          SELECT initiator_name AS member_name, COUNT(*) AS completed_count
          FROM rivalries
          WHERE status = 'completed'
          GROUP BY initiator_name
          UNION ALL
          SELECT opponent_name AS member_name, COUNT(*) AS completed_count
          FROM rivalries
          WHERE status = 'completed'
          GROUP BY opponent_name
        ),
        wins AS (
          SELECT winner_name AS member_name, COUNT(*) AS wins_count, COALESCE(SUM(point_value), 0) AS points
          FROM rivalries
          WHERE status = 'completed' AND winner_name IS NOT NULL
          GROUP BY winner_name
        )
        SELECT
          p.member_name,
          COALESCE(SUM(c.completed_count), 0) AS rivalries_completed,
          COALESCE(SUM(w.wins_count), 0) AS rivalries_won,
          COALESCE(SUM(w.points), 0) AS total_points
        FROM participants p
        LEFT JOIN completions c ON c.member_name = p.member_name
        LEFT JOIN wins w ON w.member_name = p.member_name
        GROUP BY p.member_name
        ORDER BY total_points DESC, rivalries_won DESC, member_name ASC
      `;
      this.db.all(sql, [], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  // Gift operations
  addGiftPerson(person) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO gift_people (name, relationship, birthday, anniversary, notes) VALUES (?, ?, ?, ?, ?)',
        [person.name, person.relationship || 'other', person.birthday || null, person.anniversary || null, person.notes || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...person });
        }
      );
    });
  }

  getGiftPeople() {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT * FROM gift_people ORDER BY name', (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  addGiftIdea(idea) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO gift_ideas (person_id, title, notes, link_url, estimated_price, status, for_event)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [idea.person_id, idea.title, idea.notes || null, idea.link_url || null, idea.estimated_price || null, idea.status || 'idea', idea.for_event || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...idea });
        }
      );
    });
  }

  getGiftIdeas(personId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM gift_ideas';
      const params = [];
      if (personId != null) {
        sql += ' WHERE person_id = ?';
        params.push(personId);
      }
      sql += ' ORDER BY datetime(created_at) DESC';
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  updateGiftIdea(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      params.push(id);
      this.db.run(`UPDATE gift_ideas SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  deleteGiftIdea(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM gift_ideas WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  addSpecialEvent(event) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO special_events (person_id, title, date, is_recurring, event_type, notes)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [event.person_id || null, event.title, event.date, event.is_recurring ? 1 : 0, event.event_type || 'custom', event.notes || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...event });
        }
      );
    });
  }

  getSpecialEvents() {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT * FROM special_events ORDER BY date', (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  deleteSpecialEvent(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM special_events WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  // Memory operations
  addMemory(type, key, value, expires_at = null) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO memory (type, key, value, expires_at) VALUES (?, ?, ?, ?)',
        [type, key, value, expires_at],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, type, key, value });
        }
      );
    });
  }

  getMemory(type, key = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM memory WHERE type = ?';
      const params = [type];
      
      if (key) {
        sql += ' AND key = ?';
        params.push(key);
      }
      
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  // Health operations
  addHealthMetric(date, metric_type, value, unit = null, source = 'manual') {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO health (date, metric_type, value, unit, source) VALUES (?, ?, ?, ?, ?)',
        [date, metric_type, value, unit, source],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, date, metric_type, value });
        }
      );
    });
  }

  getHealthMetrics(metric_type, days = 30) {
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT * FROM health 
        WHERE metric_type = ? 
        AND date >= date('now', '-${days} days')
        ORDER BY date DESC
      `;
      this.db.all(sql, [metric_type], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  // Log parsed message
  logMessage(raw, category, action, task_id = null) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO message_log (raw_message, parsed_category, parsed_action, task_id) VALUES (?, ?, ?, ?)',
        [raw, category, action, task_id],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  // Get daily summary
  getDailySummary() {
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT 
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' AND date(due_date) = date('now')) as tasks_today,
          (SELECT COUNT(*) FROM appointments WHERE date(appointment_date) = date('now')) as appointments_today,
          (SELECT COUNT(*) FROM groceries WHERE status = 'needed') as groceries_needed,
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' AND due_date < date('now')) as overdue_tasks
      `;
      this.db.get(sql, [], (err, row) => {
        if (err) reject(err);
        else resolve(row);
      });
    });
  }

  close() {
    this.db.close();
  }
}

module.exports = FamilyDB;

// CLI usage
if (require.main === module) {
  const db = new FamilyDB();
  
  // Test the connection
  db.getDailySummary().then(summary => {
    console.log('Family Life Organizer DB initialized');
    console.log('Daily summary:', summary);
    db.close();
  }).catch(err => {
    console.error('DB Error:', err);
    db.close();
  });
}
