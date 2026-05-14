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
    person_tags TEXT,
    recurrence_rule TEXT,
    recurrence_end TEXT,
    reminder_sent BOOLEAN DEFAULT 0,
    group_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (group_id) REFERENCES groups(id)
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
  name TEXT NOT NULL UNIQUE,
  monthly_limit DECIMAL(10,2),
  color TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Default budget categories (inserted at end of schema to avoid blocking table creation)

-- Pantry inventory
CREATE TABLE IF NOT EXISTS pantry (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item TEXT NOT NULL,
    category TEXT,
    location TEXT DEFAULT 'pantry',
    quantity TEXT DEFAULT '1',
    unit TEXT,
    expiry_date TEXT,
    receipt_id INTEGER,
    added_by TEXT DEFAULT 'jesse',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (receipt_id) REFERENCES receipts(id)
);

CREATE INDEX IF NOT EXISTS idx_pantry_location ON pantry(location);
CREATE INDEX IF NOT EXISTS idx_pantry_expiry ON pantry(expiry_date);

-- Trips and location sharing
CREATE TABLE IF NOT EXISTS trips (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    traveler TEXT NOT NULL,
    origin TEXT,
    origin_lat REAL,
    origin_lng REAL,
    destination TEXT NOT NULL,
    destination_lat REAL,
    destination_lng REAL,
    purpose TEXT,
    status TEXT DEFAULT 'active',
    current_lat REAL,
    current_lng REAL,
    eta_minutes INTEGER,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    arrived_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Known family addresses
CREATE TABLE IF NOT EXISTS family_addresses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    address TEXT,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    radius_meters INTEGER DEFAULT 500,
    created_by TEXT DEFAULT 'jesse',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_trips_status ON trips(status);
CREATE INDEX IF NOT EXISTS idx_trips_traveler ON trips(traveler);

-- Family decisions
CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    decision_type TEXT NOT NULL,
    body TEXT,
    link_url TEXT,
    photo_data TEXT,
    poll_options TEXT,
    creator_name TEXT DEFAULT 'Jesse',
    status TEXT DEFAULT 'active',
    expires_at TEXT,
    group_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (group_id) REFERENCES groups(id)
);

CREATE TABLE IF NOT EXISTS decision_reactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    decision_id INTEGER NOT NULL,
    member_name TEXT NOT NULL,
    reaction_type TEXT NOT NULL,
    poll_choice INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (decision_id) REFERENCES decisions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS decision_comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    decision_id INTEGER NOT NULL,
    member_name TEXT NOT NULL,
    text TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (decision_id) REFERENCES decisions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_decisions_status ON decisions(status);
CREATE INDEX IF NOT EXISTS idx_decision_reactions_decision_id ON decision_reactions(decision_id);
CREATE INDEX IF NOT EXISTS idx_decision_comments_decision_id ON decision_comments(decision_id);

-- Family rivalries
CREATE TABLE IF NOT EXISTS rivalries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    challenge_type TEXT NOT NULL,
    initiator_name TEXT NOT NULL,
    opponent_name TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    status TEXT DEFAULT 'active',
    point_value INTEGER DEFAULT 100,
    winner_name TEXT,
    group_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (group_id) REFERENCES groups(id)
);

CREATE TABLE IF NOT EXISTS rivalry_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rivalry_id INTEGER NOT NULL,
    member_name TEXT NOT NULL,
    value REAL NOT NULL,
    note TEXT,
    is_verified BOOLEAN DEFAULT 0,
    logged_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (rivalry_id) REFERENCES rivalries(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rivalries_status ON rivalries(status);
CREATE INDEX IF NOT EXISTS idx_rivalry_entries_rivalry_id ON rivalry_entries(rivalry_id);

-- Gifts and events
CREATE TABLE IF NOT EXISTS gift_people (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    relationship TEXT DEFAULT 'other',
    birthday TEXT,
    anniversary TEXT,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS gift_ideas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    notes TEXT,
    link_url TEXT,
    estimated_price REAL,
    status TEXT DEFAULT 'idea',
    for_event TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (person_id) REFERENCES gift_people(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS special_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER,
    title TEXT NOT NULL,
    date TEXT NOT NULL,
    is_recurring BOOLEAN DEFAULT 1,
    event_type TEXT DEFAULT 'custom',
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (person_id) REFERENCES gift_people(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_gift_ideas_person_id ON gift_ideas(person_id);
CREATE INDEX IF NOT EXISTS idx_special_events_person_id ON special_events(person_id);

-- Budget projects (shared between family members)
CREATE TABLE IF NOT EXISTS budget_projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    budget REAL NOT NULL DEFAULT 0,
    created_by TEXT DEFAULT 'jesse',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS project_expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    description TEXT NOT NULL,
    amount REAL NOT NULL,
    category TEXT DEFAULT 'General',
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES budget_projects(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_project_expenses_project_id ON project_expenses(project_id);

-- ============================================
-- Family Graph: Users, Groups, Contacts, Feed
-- ============================================

-- Registered app users (replaces hardcoded USERS)
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    avatar TEXT,
    profile_image TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Groups: household (core couple), family (one side), tribe (merged)
CREATE TABLE IF NOT EXISTS groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    group_type TEXT NOT NULL DEFAULT 'household', -- household | family | tribe
    description TEXT,
    invite_code TEXT UNIQUE,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Links users to groups
CREATE TABLE IF NOT EXISTS group_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL,
    user_id INTEGER,          -- for app users
    contact_id INTEGER,       -- for non-app family contacts
    role TEXT DEFAULT 'member', -- admin | member
    added_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (contact_id) REFERENCES contacts(id),
    FOREIGN KEY (added_by) REFERENCES users(id)
);

-- Non-app family contacts (mom, dad, sister, etc.)
CREATE TABLE IF NOT EXISTS contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    added_by INTEGER NOT NULL,
    name TEXT NOT NULL,
    relationship TEXT,        -- mom, dad, sister, brother, etc.
    phone TEXT,
    email TEXT,
    birthday TEXT,
    avatar_initial TEXT,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (added_by) REFERENCES users(id)
);

-- Group feed posts
CREATE TABLE IF NOT EXISTS feed_posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    post_type TEXT NOT NULL DEFAULT 'text', -- text | photo | link | event | decision | rivalry | poll
    title TEXT,
    body TEXT,
    link_url TEXT,
    photo_url TEXT,
    reference_type TEXT,     -- decision | rivalry | appointment (for linked content)
    reference_id INTEGER,    -- id in the linked table
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES users(id)
);

-- Feed reactions (likes, hearts, etc.)
CREATE TABLE IF NOT EXISTS feed_reactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    reaction_type TEXT NOT NULL DEFAULT 'like', -- like | love | laugh | wow | sad
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES feed_posts(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id),
    UNIQUE(post_id, user_id, reaction_type)
);

-- Feed comments
CREATE TABLE IF NOT EXISTS feed_comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES feed_posts(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_groups_type ON groups(group_type);
CREATE INDEX IF NOT EXISTS idx_groups_invite_code ON groups(invite_code);
CREATE INDEX IF NOT EXISTS idx_group_members_group_id ON group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user_id ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_added_by ON contacts(added_by);
CREATE INDEX IF NOT EXISTS idx_feed_posts_group_id ON feed_posts(group_id);
CREATE INDEX IF NOT EXISTS idx_feed_posts_created_at ON feed_posts(created_at);
CREATE INDEX IF NOT EXISTS idx_feed_reactions_post_id ON feed_reactions(post_id);
CREATE INDEX IF NOT EXISTS idx_feed_comments_post_id ON feed_comments(post_id);

-- ============================================
-- Lists (user-created, each with their own items)
-- ============================================

CREATE TABLE IF NOT EXISTS lists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    icon TEXT DEFAULT 'list.bullet',
    color TEXT,
    created_by INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS list_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    list_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    is_done BOOLEAN DEFAULT 0,
    sort_order INTEGER DEFAULT 0,
    added_by TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    FOREIGN KEY (list_id) REFERENCES lists(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_list_items_list_id ON list_items(list_id);

-- ============================================
-- Coverage / Care Cascade
-- ============================================

-- A coverage request sent by a user to their care team
CREATE TABLE IF NOT EXISTS coverage_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    requester_id INTEGER NOT NULL,
    reason TEXT NOT NULL,               -- 'kids' | 'dog' | 'house' | custom text
    note TEXT,
    status TEXT DEFAULT 'pending',      -- pending | approved | expired | cancelled
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (requester_id) REFERENCES users(id)
);

-- Candidate time windows proposed by the requester
CREATE TABLE IF NOT EXISTS coverage_windows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id INTEGER NOT NULL,
    window_date TEXT NOT NULL,           -- YYYY-MM-DD
    start_time TEXT NOT NULL,            -- HH:MM
    end_time TEXT NOT NULL,              -- HH:MM
    description TEXT,                    -- e.g. "Jesse: 2 meetings"
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (request_id) REFERENCES coverage_requests(id) ON DELETE CASCADE
);

-- Which contacts were asked (the care team for this request)
CREATE TABLE IF NOT EXISTS coverage_recipients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id INTEGER NOT NULL,
    contact_id INTEGER NOT NULL,
    invite_token TEXT UNIQUE,            -- unique token for the approval link
    status TEXT DEFAULT 'pending',       -- pending | viewed | approved | declined
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (request_id) REFERENCES coverage_requests(id) ON DELETE CASCADE,
    FOREIGN KEY (contact_id) REFERENCES contacts(id)
);

-- An approval from a care team member (they pick a window + confirm their time)
CREATE TABLE IF NOT EXISTS coverage_approvals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id INTEGER NOT NULL,
    recipient_id INTEGER NOT NULL,       -- which coverage_recipient approved
    window_id INTEGER NOT NULL,          -- which proposed window they picked
    approved_date TEXT NOT NULL,          -- YYYY-MM-DD (may match window or differ)
    approved_start TEXT NOT NULL,         -- HH:MM
    approved_end TEXT NOT NULL,           -- HH:MM
    helper_note TEXT,                     -- e.g. "Thursday works, we'll bring lunch"
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (request_id) REFERENCES coverage_requests(id) ON DELETE CASCADE,
    FOREIGN KEY (recipient_id) REFERENCES coverage_recipients(id),
    FOREIGN KEY (window_id) REFERENCES coverage_windows(id)
);

CREATE INDEX IF NOT EXISTS idx_coverage_requests_requester ON coverage_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_coverage_requests_status ON coverage_requests(status);
CREATE INDEX IF NOT EXISTS idx_coverage_windows_request ON coverage_windows(request_id);
CREATE INDEX IF NOT EXISTS idx_coverage_recipients_request ON coverage_recipients(request_id);
CREATE INDEX IF NOT EXISTS idx_coverage_recipients_token ON coverage_recipients(invite_token);
CREATE INDEX IF NOT EXISTS idx_coverage_approvals_request ON coverage_approvals(request_id);

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

-- Direct messages
CREATE TABLE IF NOT EXISTS direct_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id INTEGER NOT NULL,
    recipient_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    reference_type TEXT,
    reference_id INTEGER,
    reference_title TEXT,
    image_data TEXT,
    read_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (sender_id) REFERENCES users(id),
    FOREIGN KEY (recipient_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_dm_conversation ON direct_messages(sender_id, recipient_id, id DESC);

-- Seed budget categories (last so any failure doesn't block table creation)
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Groceries', 800.00, '#43e97b' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Groceries');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Dining Out', 300.00, '#f093fb' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Dining Out');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Gas/Transport', 200.00, '#4facfe' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Gas/Transport');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Household', 150.00, '#667eea' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Household');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Health', 100.00, '#fa709a' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Health');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Entertainment', 150.00, '#fee140' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Entertainment');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Kids', 200.00, '#30cfd0' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Kids');
INSERT OR IGNORE INTO budget_categories (name, monthly_limit, color)
  SELECT 'Other', 100.00, '#a8edea' WHERE NOT EXISTS (SELECT 1 FROM budget_categories WHERE name='Other');
