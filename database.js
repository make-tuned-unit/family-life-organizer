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

// Shared connection for concurrent access
let _sharedDb = null;

function getSharedDb() {
  if (!_sharedDb) {
    _sharedDb = new sqlite3.Database(DB_PATH);
    _sharedDb.configure('busyTimeout', 10000);
    _sharedDb.run('PRAGMA journal_mode = WAL');
    _sharedDb.run('PRAGMA synchronous = NORMAL');
  }
  return _sharedDb;
}

class FamilyDB {
  constructor() {
    this.db = getSharedDb();
    this._ownsConnection = false;
  }

  parseJSONList(value) {
    if (!value) return [];
    try {
      return JSON.parse(value);
    } catch {
      return [];
    }
  }

  // Run full schema — called once at app startup with proper async handling
  initSchema() {
    return new Promise((resolve, reject) => {
      const schema = fs.readFileSync(
        path.join(__dirname, 'schema.sql'),
        'utf8'
      );
      this.db.serialize(() => {
        this.db.exec(schema, (err) => {
          if (err) console.error('Schema init error:', err.message);
        });
        // One-time dedup then add unique index
        this.db.run(`
          DELETE FROM budget_categories WHERE id NOT IN (
            SELECT MIN(id) FROM budget_categories GROUP BY name
          )
        `, (err) => {
          if (err) console.error('Dedup error:', err.message);
        });
        this.db.run('CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_cat_name ON budget_categories(name)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_feed_reactions_post ON feed_reactions(post_id)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_feed_comments_post ON feed_comments(post_id)');
        // Recurring events columns
        this.db.run('ALTER TABLE appointments ADD COLUMN recurrence_rule TEXT', () => {});
        this.db.run('ALTER TABLE appointments ADD COLUMN recurrence_end TEXT', () => {});
        // Profile image column
        this.db.run('ALTER TABLE users ADD COLUMN profile_image TEXT', () => {});
        // DM image support
        this.db.run('ALTER TABLE direct_messages ADD COLUMN image_data TEXT', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_feed_posts_group ON feed_posts(group_id, id DESC)', () => {});
        // Data isolation: add group_id to household-scoped tables
        this.db.run('ALTER TABLE appointments ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE decisions ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE rivalries ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_appointments_group ON appointments(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_decisions_group ON decisions(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_rivalries_group ON rivalries(group_id)', (err) => {
          if (err) console.error('Index error:', err.message);
          resolve();
        });
      });
    });
  }

  // Merge legacy separate households and backfill group_id on unscoped records
  runHouseholdMigrations() {
    return new Promise((resolve, reject) => {
      // Step 1: Merge Jesse & Sophie into one household if they're in separate ones
      this.db.all(`
        SELECT u.id as user_id, u.username, g.id as group_id, g.name as group_name
        FROM users u
        JOIN group_members gm ON gm.user_id = u.id
        JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
        WHERE u.username IN ('jesse', 'sophie')
        ORDER BY g.id ASC
      `, (err, rows) => {
        if (err || !rows || rows.length < 2) return this._backfillGroupIds().then(resolve, reject);

        const households = [...new Set(rows.map(r => r.group_id))];
        if (households.length <= 1) return this._backfillGroupIds().then(resolve, reject);

        // They're in separate households — merge into the first one
        const keepId = households[0];
        const usersToMove = rows.filter(r => r.group_id !== keepId);

        let pending = usersToMove.length;
        if (pending === 0) return this._backfillGroupIds().then(resolve, reject);

        for (const row of usersToMove) {
          this.db.get('SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [keepId, row.user_id], (err2, existing) => {
              if (!err2 && !existing) {
                this.db.run('INSERT INTO group_members (group_id, user_id, role, added_by) VALUES (?, ?, ?, ?)',
                  [keepId, row.user_id, 'admin', row.user_id]);
              }
              // Remove from old household
              this.db.run('DELETE FROM group_members WHERE group_id = ? AND user_id = ?',
                [row.group_id, row.user_id]);
              pending--;
              if (pending === 0) {
                // Rename to Fairbanks
                this.db.run("UPDATE groups SET name = 'Fairbanks' WHERE id = ? AND name LIKE '%''s Home'",
                  [keepId], () => {
                    this._backfillGroupIds().then(resolve, reject);
                  });
              }
            });
        }
      });
    });
  }

  // Backfill group_id on records that don't have one
  _backfillGroupIds() {
    return new Promise((resolve, reject) => {
      this.db.serialize(() => {
        // Appointments: match person_tags to household members
        this.db.run(`
          UPDATE appointments SET group_id = (
            SELECT gm.group_id FROM users u
            JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE appointments.person_tags LIKE '%' || u.name || '%'
            LIMIT 1
          ) WHERE group_id IS NULL AND person_tags IS NOT NULL
        `);
        // Appointments without person_tags: assign to first household
        this.db.run(`
          UPDATE appointments SET group_id = (
            SELECT g.id FROM groups g WHERE g.group_type = 'household' ORDER BY g.id LIMIT 1
          ) WHERE group_id IS NULL
        `);
        // Decisions: match creator_name
        this.db.run(`
          UPDATE decisions SET group_id = (
            SELECT gm.group_id FROM users u
            JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE u.name = decisions.creator_name
            LIMIT 1
          ) WHERE group_id IS NULL
        `);
        // Rivalries: match initiator_name
        this.db.run(`
          UPDATE rivalries SET group_id = (
            SELECT gm.group_id FROM users u
            JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE u.name = rivalries.initiator_name
            LIMIT 1
          ) WHERE group_id IS NULL
        `, (err) => {
          if (err) console.error('Backfill error:', err.message);
          resolve();
        });
      });
    });
  }

  // Get the user's household group ID
  getUserHouseholdId(userId) {
    return new Promise((resolve, reject) => {
      this.db.get(`
        SELECT g.id FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        WHERE gm.user_id = ? AND g.group_type = 'household'
        LIMIT 1
      `, [userId], (err, row) => {
        if (err) reject(err);
        else resolve(row?.id || null);
      });
    });
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
        sql += ' AND LOWER(category) = LOWER(?)';
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
        'INSERT INTO appointments (title, description, appointment_date, appointment_time, location, with_person, category, person_tags, recurrence_rule, recurrence_end, group_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          appointment.title,
          appointment.description || null,
          appointment.appointment_date,
          appointment.appointment_time || null,
          appointment.location || null,
          appointment.with_person || null,
          appointment.category || 'appointments',
          appointment.person_tags ? appointment.person_tags.join(',') : null,
          appointment.recurrence_rule || null,
          appointment.recurrence_end || null,
          appointment.group_id || null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...appointment });
        }
      );
    });
  }

  getAppointments(filters = {}, userId = null) {
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

      if (userId) {
        const uid = parseInt(userId);
        sql += ` AND (group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          OR (group_id IS NULL AND EXISTS (
            SELECT 1 FROM users u JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
            AND (appointments.person_tags LIKE '%' || u.name || '%' OR appointments.person_tags IS NULL)
          )))`;
      }

      sql += ' ORDER BY appointment_date, appointment_time';

      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  getAppointmentsByMonth(year, month, userId = null) {
    return new Promise((resolve, reject) => {
      const startDate = `${year}-${String(month).padStart(2, '0')}-01`;
      const endDate = month === 12
        ? `${year + 1}-01-01`
        : `${year}-${String(month + 1).padStart(2, '0')}-01`;

      let sql = 'SELECT * FROM appointments WHERE appointment_date >= ? AND appointment_date < ?';
      if (userId) {
        const uid = parseInt(userId);
        sql += ` AND (group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          OR (group_id IS NULL AND EXISTS (
            SELECT 1 FROM users u JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
            AND (appointments.person_tags LIKE '%' || u.name || '%' OR appointments.person_tags IS NULL)
          )))`;
      }
      sql += ' ORDER BY appointment_date, appointment_time';

      this.db.all(sql, [startDate, endDate], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  getRecurringAppointments(userId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM appointments WHERE recurrence_rule IS NOT NULL AND recurrence_rule != ""';
      if (userId) {
        const uid = parseInt(userId);
        sql += ` AND (group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          OR (group_id IS NULL AND EXISTS (
            SELECT 1 FROM users u JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
            AND (appointments.person_tags LIKE '%' || u.name || '%' OR appointments.person_tags IS NULL)
          )))`;
      }
      this.db.all(sql, (err, rows) => {
        if (err) reject(err);
        else resolve(rows || []);
      });
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
        sql += ' AND LOWER(category) = LOWER(?)';
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
        LEFT JOIN receipts r ON LOWER(c.name) = LOWER(r.category) AND strftime('%Y-%m', r.date) = ?
        GROUP BY c.name
        ORDER BY c.name
      `;
      this.db.all(sql, [month], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  getBudgetCategories() {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT * FROM budget_categories ORDER BY name', (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  addBudgetCategory(name, monthlyLimit, color) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO budget_categories (name, monthly_limit, color) VALUES (?, ?, ?)',
        [name, monthlyLimit || null, color || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  updateBudgetCategory(id, data) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const values = [];
      if (data.name !== undefined) { fields.push('name = ?'); values.push(data.name); }
      if (data.monthly_limit !== undefined) { fields.push('monthly_limit = ?'); values.push(data.monthly_limit); }
      if (data.color !== undefined) { fields.push('color = ?'); values.push(data.color); }
      if (fields.length === 0) return resolve();
      values.push(id);
      this.db.run(`UPDATE budget_categories SET ${fields.join(', ')} WHERE id = ?`, values, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  deleteBudgetCategory(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM budget_categories WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  ensureBudgetCategory(name) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT id FROM budget_categories WHERE LOWER(name) = LOWER(?)', [name], (err, row) => {
        if (err) return reject(err);
        if (row) return resolve(row.id);
        this.db.run('INSERT INTO budget_categories (name) VALUES (?)', [name], function(err2) {
          if (err2) reject(err2);
          else resolve(this.lastID);
        });
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
      if (filters.location) { sql += ' AND LOWER(location) = LOWER(?)'; params.push(filters.location); }
      if (filters.category) { sql += ' AND LOWER(category) = LOWER(?)'; params.push(filters.category); }
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
        `INSERT INTO decisions (title, decision_type, body, link_url, photo_data, poll_options, creator_name, status, expires_at, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          decision.title,
          decision.decision_type,
          decision.body || null,
          decision.link_url || null,
          decision.photo_data || null,
          JSON.stringify(decision.poll_options || []),
          decision.creator_name || 'Jesse',
          decision.status || 'active',
          decision.expires_at || null,
          decision.group_id || null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...decision });
        }
      );
    });
  }

  getDecisions(filters = {}, userId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM decisions WHERE 1=1';
      const params = [];
      if (filters.status) { sql += ' AND status = ?'; params.push(filters.status); }
      if (userId) {
        const uid = parseInt(userId);
        sql += ` AND (group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          OR (group_id IS NULL AND creator_name IN (
            SELECT u.name FROM users u JOIN group_members gm ON gm.user_id = u.id
            JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
            WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          )))`;
      }
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
        `INSERT INTO rivalries (title, challenge_type, initiator_name, opponent_name, start_date, end_date, status, point_value, winner_name, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          rivalry.title,
          rivalry.challenge_type,
          rivalry.initiator_name,
          rivalry.opponent_name,
          rivalry.start_date,
          rivalry.end_date,
          rivalry.status || 'active',
          rivalry.point_value || 100,
          rivalry.winner_name || null,
          rivalry.group_id || null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...rivalry });
        }
      );
    });
  }

  getRivalries(filters = {}, userId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM rivalries WHERE 1=1';
      const params = [];
      if (filters.status) { sql += ' AND status = ?'; params.push(filters.status); }
      if (userId) {
        const uid = parseInt(userId);
        sql += ` AND (group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          OR (group_id IS NULL AND (
            initiator_name IN (
              SELECT u.name FROM users u JOIN group_members gm ON gm.user_id = u.id
              JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
              WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
            ) OR opponent_name IN (
              SELECT u.name FROM users u JOIN group_members gm ON gm.user_id = u.id
              JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
              WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
            )
          )))`;
      }
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

  getRivalryLeaderboard(userId = null) {
    return new Promise((resolve, reject) => {
      const groupFilter = userId
        ? `WHERE (group_id IN (SELECT group_id FROM group_members WHERE user_id = ${parseInt(userId)})
            OR (group_id IS NULL AND (initiator_name IN (
              SELECT u.name FROM users u JOIN group_members gm ON gm.user_id = u.id
              JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
              WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${parseInt(userId)})
            ) OR opponent_name IN (
              SELECT u.name FROM users u JOIN group_members gm ON gm.user_id = u.id
              JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
              WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${parseInt(userId)})
            ))))`
        : '';
      const sql = `
        WITH scoped_rivalries AS (
          SELECT * FROM rivalries ${groupFilter}
        ),
        participants AS (
          SELECT DISTINCT member_name FROM (
            SELECT initiator_name AS member_name FROM scoped_rivalries
            UNION
            SELECT opponent_name AS member_name FROM scoped_rivalries
          )
        )
        SELECT
          p.member_name,
          (SELECT COUNT(*) FROM scoped_rivalries WHERE status = 'completed' AND (initiator_name = p.member_name OR opponent_name = p.member_name)) AS rivalries_completed,
          (SELECT COUNT(*) FROM scoped_rivalries WHERE status = 'completed' AND winner_name = p.member_name) AS rivalries_won,
          COALESCE((SELECT SUM(point_value) FROM scoped_rivalries WHERE status = 'completed' AND winner_name = p.member_name), 0) AS total_points
        FROM participants p
        ORDER BY total_points DESC, rivalries_won DESC, p.member_name ASC
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

  // Budget project operations
  addProject(project) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO budget_projects (name, budget, created_by) VALUES (?, ?, ?)',
        [project.name, project.budget || 0, project.created_by || 'jesse'],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...project });
        }
      );
    });
  }

  getProjects() {
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT p.*, COALESCE(SUM(e.amount), 0) as total_spent, COUNT(e.id) as expense_count
        FROM budget_projects p
        LEFT JOIN project_expenses e ON e.project_id = p.id
        GROUP BY p.id
        ORDER BY p.created_at DESC
      `;
      this.db.all(sql, [], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  deleteProject(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM budget_projects WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  addProjectExpense(projectId, expense) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO project_expenses (project_id, description, amount, category, notes) VALUES (?, ?, ?, ?, ?)',
        [projectId, expense.description, expense.amount, expense.category || 'General', expense.notes || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...expense });
        }
      );
    });
  }

  getProjectExpenses(projectId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM project_expenses WHERE project_id = ? ORDER BY created_at DESC',
        [projectId],
        (err, rows) => err ? reject(err) : resolve(rows)
      );
    });
  }

  deleteProjectExpense(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM project_expenses WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  // ============================================
  // Users
  // ============================================

  createUser(user) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO users (username, password_hash, name, email, phone, avatar) VALUES (?, ?, ?, ?, ?, ?)',
        [user.username, user.password_hash, user.name, user.email || null, user.phone || null, user.avatar || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, username: user.username, name: user.name });
        }
      );
    });
  }

  getUserByUsername(username) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM users WHERE username = ?', [username], (err, row) => {
        if (err) reject(err);
        else resolve(row || null);
      });
    });
  }

  getUserById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT id, username, name, email, phone, avatar, created_at FROM users WHERE id = ?', [id], (err, row) => {
        if (err) reject(err);
        else resolve(row || null);
      });
    });
  }

  // ============================================
  // Groups
  // ============================================

  createGroup(group) {
    return new Promise((resolve, reject) => {
      const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();
      this.db.run(
        'INSERT INTO groups (name, group_type, description, invite_code, created_by) VALUES (?, ?, ?, ?, ?)',
        [group.name, group.group_type || 'household', group.description || null, inviteCode, group.created_by],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, invite_code: inviteCode });
        }
      );
    });
  }

  getGroupsByUser(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT g.*, gm.role,
          (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) as member_count
        FROM groups g
        JOIN group_members gm ON gm.group_id = g.id AND gm.user_id = ?
        ORDER BY g.group_type, g.name
      `, [userId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  getGroupById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM groups WHERE id = ?', [id], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  getGroupByInviteCode(code) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM groups WHERE invite_code = ?', [code], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  addGroupMember(groupId, { user_id, contact_id, role, added_by }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO group_members (group_id, user_id, contact_id, role, added_by) VALUES (?, ?, ?, ?, ?)',
        [groupId, user_id || null, contact_id || null, role || 'member', added_by],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  getGroupMembers(groupId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT gm.*,
          u.name as user_name, u.username, u.avatar as user_avatar, u.profile_image,
          c.name as contact_name, c.relationship, c.avatar_initial, c.phone as contact_phone
        FROM group_members gm
        LEFT JOIN users u ON u.id = gm.user_id
        LEFT JOIN contacts c ON c.id = gm.contact_id
        WHERE gm.group_id = ?
        ORDER BY gm.role DESC, COALESCE(u.name, c.name)
      `, [groupId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  removeGroupMember(groupId, memberId) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM group_members WHERE group_id = ? AND id = ?', [groupId, memberId], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  deleteGroup(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM groups WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  // ============================================
  // Contacts (non-app family members)
  // ============================================

  addContact(contact) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO contacts (added_by, name, relationship, phone, email, birthday, avatar_initial, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [contact.added_by, contact.name, contact.relationship || null, contact.phone || null, contact.email || null, contact.birthday || null, contact.avatar_initial || contact.name.charAt(0).toUpperCase(), contact.notes || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...contact });
        }
      );
    });
  }

  getContactsByUser(userId) {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT * FROM contacts WHERE added_by = ? ORDER BY name', [userId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  updateContact(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      params.push(id);
      this.db.run(`UPDATE contacts SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  deleteContact(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM contacts WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  // ============================================
  // Feed
  // ============================================

  addFeedPost(post) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO feed_posts (group_id, author_id, post_type, title, body, link_url, photo_url, reference_type, reference_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [post.group_id, post.author_id, post.post_type || 'text', post.title || null, post.body || null, post.link_url || null, post.photo_url || null, post.reference_type || null, post.reference_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  getFeedPosts(groupId, { limit = 50, before_id } = {}) {
    return new Promise((resolve, reject) => {
      let sql = `
        SELECT fp.*, u.name as author_name, u.avatar as author_avatar,
          (SELECT COUNT(*) FROM feed_reactions WHERE post_id = fp.id) as reaction_count,
          (SELECT COUNT(*) FROM feed_comments WHERE post_id = fp.id) as comment_count
        FROM feed_posts fp
        JOIN users u ON u.id = fp.author_id
        WHERE fp.group_id = ?
      `;
      const params = [groupId];
      if (before_id) {
        sql += ' AND fp.id < ?';
        params.push(before_id);
      }
      sql += ' ORDER BY fp.id DESC LIMIT ?';
      params.push(limit);
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  deleteFeedPost(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM feed_posts WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  addFeedReaction(postId, userId, reactionType) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT OR REPLACE INTO feed_reactions (post_id, user_id, reaction_type) VALUES (?, ?, ?)',
        [postId, userId, reactionType || 'like'],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  removeFeedReaction(postId, userId) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM feed_reactions WHERE post_id = ? AND user_id = ?', [postId, userId], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  getFeedReactions(postId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT fr.*, u.name as user_name
        FROM feed_reactions fr
        JOIN users u ON u.id = fr.user_id
        WHERE fr.post_id = ?
      `, [postId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  addFeedComment(postId, userId, text) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO feed_comments (post_id, user_id, text) VALUES (?, ?, ?)',
        [postId, userId, text],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  getFeedComments(postId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT fc.*, u.name as user_name, u.avatar as user_avatar
        FROM feed_comments fc
        JOIN users u ON u.id = fc.user_id
        WHERE fc.post_id = ?
        ORDER BY fc.created_at ASC
      `, [postId], (err, rows) => err ? reject(err) : resolve(rows));
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
  // Unified activity feed — merges recent decisions, events, coverage, and posts
  // Posts/comments/reactions are filtered to groups the user belongs to
  getActivityFeed(limit = 20, userId = null) {
    return new Promise((resolve, reject) => {
      const uid = userId ? parseInt(userId) : null;
      // Subquery for user's group IDs
      const myGroups = uid
        ? `SELECT group_id FROM group_members WHERE user_id = ${uid}`
        : `SELECT id FROM groups`;
      // Subquery for household members (to scope events/decisions)
      const myHouseholdMembers = uid
        ? `SELECT u.name FROM users u JOIN group_members gm ON gm.user_id = u.id
           JOIN groups g ON g.id = gm.group_id WHERE g.group_type = 'household'
           AND gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})`
        : `SELECT name FROM users`;
      const sql = `
        SELECT 'decision' as feed_type, id as ref_id, title, NULL as body,
          creator_name as author, status, created_at,
          0 as reaction_count, 0 as comment_count, NULL as author_id, NULL as group_id, NULL as group_name
        FROM decisions WHERE status = 'active'
          AND creator_name IN (${myHouseholdMembers})
        UNION ALL
        SELECT 'event' as feed_type, a.id as ref_id, a.title, a.location as body,
          COALESCE(a.person_tags, 'Family') as author, 'upcoming' as status,
          a.created_at,
          0 as reaction_count, 0 as comment_count, NULL as author_id, NULL as group_id, NULL as group_name
        FROM appointments a WHERE a.appointment_date >= date('now') AND a.appointment_date <= date('now', '+7 days')${uid ? `
          AND EXISTS (
            SELECT 1 FROM users hu
            JOIN group_members hgm ON hgm.user_id = hu.id
            JOIN groups hg ON hg.id = hgm.group_id AND hg.group_type = 'household'
            WHERE hgm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
              AND hg.group_type = 'household'
              AND (a.person_tags LIKE '%' || hu.name || '%' OR a.person_tags IS NULL)
          )` : ''}
        UNION ALL
        SELECT 'coverage' as feed_type, cr.id as ref_id, cr.reason as title, cr.note as body,
          COALESCE(u.name, u.username, 'Family') as author, cr.status,
          cr.created_at,
          0 as reaction_count, 0 as comment_count, cr.requester_id as author_id, NULL as group_id, NULL as group_name
        FROM coverage_requests cr
        LEFT JOIN users u ON u.id = cr.requester_id
        WHERE cr.status IN ('pending', 'approved')${uid ? `
          AND cr.requester_id IN (
            SELECT gm2.user_id FROM group_members gm2
            JOIN groups g2 ON g2.id = gm2.group_id AND g2.group_type = 'household'
            WHERE gm2.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          )` : ''}
        UNION ALL
        SELECT 'rivalry' as feed_type, id as ref_id, title, challenge_type as body,
          initiator_name as author, status,
          created_at,
          0 as reaction_count, 0 as comment_count, NULL as author_id, NULL as group_id, NULL as group_name
        FROM rivalries WHERE status = 'active' AND created_at >= datetime('now', '-14 days')${uid ? `
          AND (group_id IN (${myGroups})
            OR (group_id IS NULL AND (
              initiator_name IN (${myHouseholdMembers})
              OR opponent_name IN (${myHouseholdMembers})
            )))` : ''}
        UNION ALL
        SELECT 'post' as feed_type, fp.id as ref_id, fp.title, fp.body,
          COALESCE(u.name, u.username, 'Family') as author, fp.post_type as status,
          fp.created_at,
          (SELECT COUNT(*) FROM feed_reactions WHERE post_id = fp.id) as reaction_count,
          (SELECT COUNT(*) FROM feed_comments WHERE post_id = fp.id) as comment_count,
          fp.author_id, fp.group_id, g.name as group_name
        FROM feed_posts fp
        LEFT JOIN users u ON u.id = fp.author_id
        LEFT JOIN groups g ON g.id = fp.group_id
        WHERE fp.group_id IN (${myGroups})
          AND fp.post_type != 'text'
        UNION ALL
        SELECT 'comment' as feed_type, fc.post_id as ref_id,
          (SELECT title FROM feed_posts WHERE id = fc.post_id) as title,
          fc.text as body,
          u.name as author, 'comment' as status,
          fc.created_at,
          0 as reaction_count, 0 as comment_count, fc.user_id as author_id,
          fp2.group_id, g2.name as group_name
        FROM feed_comments fc
        JOIN users u ON u.id = fc.user_id
        LEFT JOIN feed_posts fp2 ON fp2.id = fc.post_id
        LEFT JOIN groups g2 ON g2.id = fp2.group_id
        WHERE fc.created_at >= datetime('now', '-7 days')
          AND fp2.group_id IN (${myGroups})
          AND fp2.post_type != 'text'
        UNION ALL
        SELECT 'reaction' as feed_type, fr.post_id as ref_id,
          (SELECT title FROM feed_posts WHERE id = fr.post_id) as title,
          fr.reaction_type as body,
          u.name as author, 'reaction' as status,
          fr.created_at,
          0 as reaction_count, 0 as comment_count, fr.user_id as author_id,
          fp3.group_id, g3.name as group_name
        FROM feed_reactions fr
        JOIN users u ON u.id = fr.user_id
        LEFT JOIN feed_posts fp3 ON fp3.id = fr.post_id
        LEFT JOIN groups g3 ON g3.id = fp3.group_id
        WHERE fr.created_at >= datetime('now', '-7 days')
          AND fp3.post_type != 'text'
          AND fp3.group_id IN (${myGroups})
        ORDER BY created_at DESC
        LIMIT ?
      `;
      this.db.all(sql, [limit], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  getDailySummary(userId = null) {
    return new Promise((resolve, reject) => {
      const groupFilter = userId
        ? `AND group_id IN (SELECT group_id FROM group_members WHERE user_id = ${parseInt(userId)})`
        : '';
      const sql = `
        SELECT
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' AND date(due_date) = date('now')) as tasks_today,
          (SELECT COUNT(*) FROM appointments WHERE date(appointment_date) = date('now') ${groupFilter}) as appointments_today,
          (SELECT COUNT(*) FROM groceries WHERE status = 'needed') as groceries_needed,
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' AND due_date < date('now')) as overdue_tasks
      `;
      this.db.get(sql, [], (err, row) => {
        if (err) reject(err);
        else resolve(row);
      });
    });
  }

  // ============================================
  // Lists
  // ============================================

  createList(list) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO lists (name, icon, color, created_by) VALUES (?, ?, ?, ?)',
        [list.name, list.icon || 'list.bullet', list.color || null, list.created_by || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  getLists(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT l.*,
          (SELECT COUNT(*) FROM list_items WHERE list_id = l.id AND is_done = 0) as active_count,
          (SELECT COUNT(*) FROM list_items WHERE list_id = l.id) as total_count
        FROM lists l
        ORDER BY l.created_at ASC
      `, [], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  deleteList(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM lists WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  updateList(id, updates) {
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = ?`);
        params.push(value);
      }
      params.push(id);
      this.db.run(`UPDATE lists SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  getListItems(listId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM list_items WHERE list_id = ? ORDER BY is_done ASC, sort_order ASC, id DESC',
        [listId], (err, rows) => err ? reject(err) : resolve(rows)
      );
    });
  }

  addListItem(item) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO list_items (list_id, title, added_by) VALUES (?, ?, ?)',
        [item.list_id, item.title, item.added_by || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  toggleListItem(id) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `UPDATE list_items SET is_done = NOT is_done, completed_at = CASE WHEN is_done = 0 THEN CURRENT_TIMESTAMP ELSE NULL END WHERE id = ?`,
        [id], (err) => {
          if (err) reject(err);
          else resolve({ id });
        }
      );
    });
  }

  deleteListItem(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM list_items WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ deleted: true });
      });
    });
  }

  // ============================================
  // Coverage / Care Cascade
  // ============================================

  createCoverageRequest(req) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO coverage_requests (requester_id, reason, note) VALUES (?, ?, ?)',
        [req.requester_id, req.reason, req.note || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  addCoverageWindow(win) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO coverage_windows (request_id, window_date, start_time, end_time, description) VALUES (?, ?, ?, ?, ?)',
        [win.request_id, win.window_date, win.start_time, win.end_time, win.description || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  addCoverageRecipient(rec) {
    return new Promise((resolve, reject) => {
      const token = require('crypto').randomBytes(16).toString('hex');
      this.db.run(
        'INSERT INTO coverage_recipients (request_id, contact_id, invite_token) VALUES (?, ?, ?)',
        [rec.request_id, rec.contact_id, token],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, invite_token: token });
        }
      );
    });
  }

  getCoverageRequests(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT cr.*,
          (SELECT COUNT(*) FROM coverage_approvals WHERE request_id = cr.id) as approval_count,
          (SELECT COUNT(*) FROM coverage_recipients WHERE request_id = cr.id) as recipient_count
        FROM coverage_requests cr
        WHERE cr.requester_id = ?
        ORDER BY cr.id DESC
      `, [userId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  getCoverageRequestById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM coverage_requests WHERE id = ?', [id], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  getCoverageWindows(requestId) {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT * FROM coverage_windows WHERE request_id = ? ORDER BY window_date, start_time', [requestId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  getCoverageRecipients(requestId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT cr.*, c.name as contact_name, c.phone as contact_phone, c.avatar_initial
        FROM coverage_recipients cr
        JOIN contacts c ON c.id = cr.contact_id
        WHERE cr.request_id = ?
      `, [requestId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  getRecipientByToken(token) {
    return new Promise((resolve, reject) => {
      this.db.get(`
        SELECT cr.*, c.name as contact_name,
          creq.reason, creq.note, creq.requester_id,
          u.name as requester_name
        FROM coverage_recipients cr
        JOIN contacts c ON c.id = cr.contact_id
        JOIN coverage_requests creq ON creq.id = cr.request_id
        JOIN users u ON u.id = creq.requester_id
        WHERE cr.invite_token = ?
      `, [token], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  approveCoverage(approval) {
    return new Promise((resolve, reject) => {
      this.db.serialize(() => {
        // Insert approval
        this.db.run(
          `INSERT INTO coverage_approvals (request_id, recipient_id, window_id, approved_date, approved_start, approved_end, helper_note)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [approval.request_id, approval.recipient_id, approval.window_id, approval.approved_date, approval.approved_start, approval.approved_end, approval.helper_note || null],
          function(err) {
            if (err) return reject(err);
            const approvalId = this.lastID;

            // Update recipient status
            this.db.run('UPDATE coverage_recipients SET status = ? WHERE id = ?', ['approved', approval.recipient_id]);

            // Update request status
            this.db.run('UPDATE coverage_requests SET status = ? WHERE id = ?', ['approved', approval.request_id]);

            resolve({ id: approvalId });
          }.bind(this)
        );
      });
    });
  }

  getCoverageApprovals(requestId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT ca.*, c.name as helper_name, c.avatar_initial,
          cw.window_date, cw.start_time as proposed_start, cw.end_time as proposed_end
        FROM coverage_approvals ca
        JOIN coverage_recipients cr ON cr.id = ca.recipient_id
        JOIN contacts c ON c.id = cr.contact_id
        JOIN coverage_windows cw ON cw.id = ca.window_id
        WHERE ca.request_id = ?
        ORDER BY ca.approved_date, ca.approved_start
      `, [requestId], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  cancelCoverageRequest(id) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE coverage_requests SET status = ? WHERE id = ?', ['cancelled', id], (err) => {
        if (err) reject(err);
        else resolve({ id, status: 'cancelled' });
      });
    });
  }

  // ============================================
  // Direct Messages
  // ============================================

  sendMessage({ sender_id, recipient_id, text, reference_type, reference_id, reference_title, image_data }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO direct_messages (sender_id, recipient_id, text, reference_type, reference_id, reference_title, image_data) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [sender_id, recipient_id, text, reference_type || null, reference_id || null, reference_title || null, image_data || null],
        function(err) { err ? reject(err) : resolve({ id: this.lastID }); }
      );
    });
  }

  getConversations(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT dm.*, u.name as partner_name, u.profile_image as partner_image,
          CASE WHEN dm.sender_id = ? THEN dm.recipient_id ELSE dm.sender_id END as partner_id,
          (SELECT COUNT(*) FROM direct_messages dm2
           WHERE dm2.sender_id = CASE WHEN dm.sender_id = ? THEN dm.recipient_id ELSE dm.sender_id END
           AND dm2.recipient_id = ? AND dm2.read_at IS NULL) as unread_count
        FROM direct_messages dm
        JOIN users u ON u.id = CASE WHEN dm.sender_id = ? THEN dm.recipient_id ELSE dm.sender_id END
        WHERE dm.id IN (
          SELECT MAX(id) FROM direct_messages
          WHERE sender_id = ? OR recipient_id = ?
          GROUP BY CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END
        )
        ORDER BY dm.id DESC
      `, [userId, userId, userId, userId, userId, userId, userId], (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  getMessages(userId, partnerId, { limit = 50, before_id } = {}) {
    return new Promise((resolve, reject) => {
      let sql = `
        SELECT dm.id, dm.sender_id, dm.recipient_id, dm.text, dm.reference_type,
          dm.reference_id, dm.reference_title, dm.read_at, dm.created_at,
          CASE WHEN dm.image_data IS NOT NULL THEN 1 ELSE 0 END as has_image,
          u.name as sender_name
        FROM direct_messages dm
        JOIN users u ON u.id = dm.sender_id
        WHERE ((dm.sender_id = ? AND dm.recipient_id = ?) OR (dm.sender_id = ? AND dm.recipient_id = ?))
      `;
      const params = [userId, partnerId, partnerId, userId];
      if (before_id) { sql += ' AND dm.id < ?'; params.push(before_id); }
      sql += ' ORDER BY dm.id DESC LIMIT ?';
      params.push(limit);
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  getMessageImage(messageId) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT image_data FROM direct_messages WHERE id = ?', [messageId],
        (err, row) => err ? reject(err) : resolve(row?.image_data || null));
    });
  }

  markRead(userId, partnerId) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE direct_messages SET read_at = CURRENT_TIMESTAMP WHERE sender_id = ? AND recipient_id = ? AND read_at IS NULL',
        [partnerId, userId], (err) => err ? reject(err) : resolve()
      );
    });
  }

  getUnreadCount(userId) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT COUNT(*) as count FROM direct_messages WHERE recipient_id = ? AND read_at IS NULL', [userId],
        (err, row) => err ? reject(err) : resolve(row?.count || 0));
    });
  }

  close() {
    // No-op: using shared connection for WAL mode concurrency
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
