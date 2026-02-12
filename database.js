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
