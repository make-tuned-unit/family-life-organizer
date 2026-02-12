-- Family Life Organizer Database Schema
-- SQLite database for household management

-- Main tasks table
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'active',
    priority TEXT DEFAULT 'medium',
    due_date TEXT,
    due_time TEXT,
    assigned_to TEXT,
    created_by TEXT DEFAULT 'jesse',
    recurrence_pattern TEXT,
    tags TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    reminder_sent BOOLEAN DEFAULT 0
);

-- Knowledge/memory storage
CREATE TABLE IF NOT EXISTS memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    expires_at TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Health metrics tracking
CREATE TABLE IF NOT EXISTS health (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    metric_type TEXT NOT NULL,
    value REAL NOT NULL,
    unit TEXT,
    source TEXT DEFAULT 'manual',
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Grocery lists
CREATE TABLE IF NOT EXISTS groceries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item TEXT NOT NULL,
    category TEXT,
    quantity TEXT DEFAULT '1',
    status TEXT DEFAULT 'needed',
    added_by TEXT DEFAULT 'jesse',
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    purchased_at DATETIME
);

-- Appointments
CREATE TABLE IF NOT EXISTS appointments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    appointment_date TEXT NOT NULL,
    appointment_time TEXT,
    location TEXT,
    with_person TEXT,
    category TEXT,
    reminder_sent BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Automations
CREATE TABLE IF NOT EXISTS automations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    trigger_pattern TEXT NOT NULL,
    action TEXT NOT NULL,
    schedule TEXT,
    enabled BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Message log for parsing history
CREATE TABLE IF NOT EXISTS message_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_message TEXT NOT NULL,
    parsed_category TEXT,
    parsed_action TEXT,
    task_id INTEGER,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
);

-- Migration: Add person_tags to appointments if not exists
ALTER TABLE appointments ADD COLUMN person_tags TEXT;

-- Receipts and budget tracking
CREATE TABLE IF NOT EXISTS receipts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  amount DECIMAL(10,2) NOT NULL,
  merchant TEXT NOT NULL,
  date TEXT NOT NULL,
  category TEXT,
  payment_method TEXT,
  image_path TEXT,
  notes TEXT,
  processed_by TEXT, -- 'email' or 'manual'
  email_id TEXT, -- reference to original email if from email
  added_by TEXT DEFAULT 'jesse',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Budget categories and limits
CREATE TABLE IF NOT EXISTS budget_categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  monthly_limit DECIMAL(10,2),
  color TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Default budget categories
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color) VALUES 
  ('Groceries', 800.00, '#43e97b'),
  ('Dining Out', 300.00, '#f093fb'),
  ('Gas/Transport', 200.00, '#4facfe'),
  ('Household', 150.00, '#667eea'),
  ('Health', 100.00, '#fa709a'),
  ('Entertainment', 150.00, '#fee140'),
  ('Kids', 200.00, '#30cfd0'),
  ('Other', 100.00, '#a8edea');

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks(category);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_memory_type ON memory(type);
CREATE INDEX IF NOT EXISTS idx_health_date ON health(date);
CREATE INDEX IF NOT EXISTS idx_groceries_status ON groceries(status);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments(appointment_date);
CREATE INDEX IF NOT EXISTS idx_receipts_date ON receipts(date);
CREATE INDEX IF NOT EXISTS idx_receipts_category ON receipts(category);
