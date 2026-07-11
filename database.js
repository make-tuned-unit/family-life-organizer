#!/usr/bin/env node
/**
 * Family Life Organizer - Database Module
 * Simple SQLite wrapper for household management
 */

const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// Use an explicit override (tests), else the Render disk path, else local path.
const DB_DIR = process.env.FAMILY_DB_DIR
  ? process.env.FAMILY_DB_DIR
  : process.env.RENDER_DISK_PATH
  ? '/opt/render/project/src/vault/family-life'
  : path.join(process.env.HOME || '/tmp', '.openclaw/workspace/vault/family-life');
const DB_PATH = path.join(DB_DIR, 'family.db');

// Ensure directory exists
if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

// Columns that must never be set from a client-supplied update body. Blocks
// mass-assignment of ownership/isolation/identity fields in the dynamic update*
// helpers (a future sensitive column is protected by default, not exposed).
const PROTECTED_UPDATE_COLUMNS = new Set([
  'id', 'group_id', 'created_at', 'updated_at',
  'user_id', 'created_by', 'added_by', 'owner_id',
  'traveler_id', 'traveler_name', 'sender_id', 'recipient_id', 'author_id',
  'processed_by', 'email_id',
]);

// Coerce a caller-supplied user id to a safe integer before it is embedded in
// SQL. Throws on anything non-numeric so a bad session value fails loudly
// instead of silently matching zero rows (parseInt → NaN → empty result).
function safeUid(userId) {
  const uid = Number.parseInt(userId, 10);
  if (!Number.isInteger(uid)) throw new Error('Invalid user id');
  return uid;
}

// Shared connection for concurrent access
let _sharedDb = null;

function getSharedDb() {
  if (!_sharedDb) {
    _sharedDb = new sqlite3.Database(DB_PATH);
    _sharedDb.configure('busyTimeout', 10000);
    _sharedDb.run('PRAGMA journal_mode = WAL');
    _sharedDb.run('PRAGMA synchronous = NORMAL');
    // Enforce declared FOREIGN KEY constraints (off by default in SQLite) so the
    // schema's ON DELETE CASCADE clauses actually fire and orphans can't accrue.
    _sharedDb.run('PRAGMA foreign_keys = ON');
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
        // Budget categories are unique per household, NOT globally. Drop the
        // legacy global unique-name index (it would re-impose cross-household
        // uniqueness and let one household's category collide with another's).
        // Uniqueness is enforced by the UNIQUE(name, group_id) table constraint.
        this.db.run('DROP INDEX IF EXISTS idx_budget_cat_name');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_feed_reactions_post ON feed_reactions(post_id)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_feed_comments_post ON feed_comments(post_id)');
        // Recurring events columns
        this.db.run('ALTER TABLE appointments ADD COLUMN recurrence_rule TEXT', () => {});
        this.db.run('ALTER TABLE appointments ADD COLUMN recurrence_end TEXT', () => {});
        // Creator attribution — appointments previously had no creator, so the
        // activity feed mislabeled events by their person_tags (attendees).
        this.db.run('ALTER TABLE appointments ADD COLUMN created_by INTEGER REFERENCES users(id)', () => {});
        // Profile image column
        this.db.run('ALTER TABLE users ADD COLUMN profile_image TEXT', () => {});
        // Email 2FA columns (idempotent — error ignored if already present)
        this.db.run('ALTER TABLE users ADD COLUMN email_verified INTEGER DEFAULT 0', () => {});
        this.db.run('ALTER TABLE users ADD COLUMN two_factor_enabled INTEGER DEFAULT 0', () => {});
        // Group/household profile image
        this.db.run('ALTER TABLE groups ADD COLUMN profile_image TEXT', () => {});
        // DM image support
        this.db.run('ALTER TABLE direct_messages ADD COLUMN image_data TEXT', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_feed_posts_group ON feed_posts(group_id, id DESC)', () => {});
        // Data isolation: add group_id to household-scoped tables
        this.db.run('ALTER TABLE appointments ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE decisions ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE rivalries ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE tasks ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_tasks_group ON tasks(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_appointments_group ON appointments(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_decisions_group ON decisions(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_rivalries_group ON rivalries(group_id)', () => {});
        // User location/work fields
        this.db.run('ALTER TABLE users ADD COLUMN work_address TEXT', () => {});
        this.db.run('ALTER TABLE users ADD COLUMN work_lat REAL', () => {});
        this.db.run('ALTER TABLE users ADD COLUMN work_lng REAL', () => {});
        this.db.run('ALTER TABLE users ADD COLUMN last_lat REAL', () => {});
        this.db.run('ALTER TABLE users ADD COLUMN last_lng REAL', () => {});
        this.db.run('ALTER TABLE users ADD COLUMN last_location_name TEXT', () => {});
        this.db.run('ALTER TABLE lists ADD COLUMN pinned BOOLEAN DEFAULT 0', () => {});
        this.db.run('ALTER TABLE lists ADD COLUMN list_type TEXT DEFAULT \'standard\'', () => {});
        this.db.run('ALTER TABLE list_items ADD COLUMN category TEXT', () => {});
        // Auto-migrate existing grocery-named lists (run every startup to catch stragglers)
        this.db.run("UPDATE lists SET list_type = 'grocery' WHERE lower(name) IN ('groceries', 'grocery', 'costco', 'walmart') AND (list_type IS NULL OR list_type = 'standard' OR list_type = '')", () => {});
        // Grocery household isolation
        this.db.run('ALTER TABLE groceries ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        // Multi-player rivalries
        this.db.run('ALTER TABLE rivalries ADD COLUMN participants TEXT', () => {});
        // Team rivalries (household vs household or ad-hoc rosters)
        this.db.run("ALTER TABLE rivalries ADD COLUMN rivalry_type TEXT DEFAULT 'individual'", () => {});
        this.db.run('ALTER TABLE rivalries ADD COLUMN team_a TEXT', () => {});
        this.db.run('ALTER TABLE rivalries ADD COLUMN team_b TEXT', () => {});
        this.db.run('ALTER TABLE rivalries ADD COLUMN winner_team TEXT', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_groceries_group ON groceries(group_id)', () => {});
        // Dedupe any historical duplicate memberships, then enforce uniqueness
        // so retried joins/adds can't create duplicate rows.
        this.db.run(`DELETE FROM group_members WHERE user_id IS NOT NULL AND id NOT IN (
          SELECT MIN(id) FROM group_members WHERE user_id IS NOT NULL GROUP BY group_id, user_id)`, () => {
          this.db.run('CREATE UNIQUE INDEX IF NOT EXISTS idx_group_members_unique_user ON group_members(group_id, user_id) WHERE user_id IS NOT NULL', () => {});
        });
        // Data isolation (round 2): budgets, pantry, trips, gifts, special events
        this.db.run('ALTER TABLE receipts ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE budget_projects ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE project_expenses ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE pantry ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE trips ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE gift_people ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE gift_ideas ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE special_events ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('ALTER TABLE family_addresses ADD COLUMN group_id INTEGER REFERENCES groups(id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_receipts_group ON receipts(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_budget_projects_group ON budget_projects(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_project_expenses_group ON project_expenses(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_pantry_group ON pantry(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_trips_group ON trips(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_gift_people_group ON gift_people(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_gift_ideas_group ON gift_ideas(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_special_events_group ON special_events(group_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_family_addresses_group ON family_addresses(group_id)', () => {});
        // People registry: gift_people doubles as the household's people list.
        // user_id links a row to a real account; dependents (kids without
        // devices) have user_id NULL + is_dependent 1.
        this.db.run('ALTER TABLE gift_people ADD COLUMN user_id INTEGER REFERENCES users(id)', () => {});
        this.db.run('ALTER TABLE gift_people ADD COLUMN is_dependent BOOLEAN DEFAULT 0', () => {});
        this.db.run('ALTER TABLE gift_people ADD COLUMN avatar_color TEXT', () => {});
        // Decisions can be tagged "about" a person (shows on their person card).
        this.db.run('ALTER TABLE decisions ADD COLUMN person_id INTEGER REFERENCES gift_people(id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_milestones_person ON milestones(person_id)', () => {});
        this.db.run('CREATE INDEX IF NOT EXISTS idx_milestones_group ON milestones(group_id)', () => {});
        // Itinerary travelers column (added after initial table creation)
        this.db.run('ALTER TABLE itineraries ADD COLUMN travelers TEXT', () => {});
        this.db.run('ALTER TABLE receipts ADD COLUMN itinerary_id INTEGER REFERENCES itineraries(id)', () => {});
        // Per-day HealthKit totals: one synced row per member per calendar day
        this.db.run('ALTER TABLE rivalry_entries ADD COLUMN activity_date TEXT', () => {});
        this.db.run(`CREATE UNIQUE INDEX IF NOT EXISTS idx_rivalry_entries_daily
          ON rivalry_entries(rivalry_id, member_name, activity_date)
          WHERE note = 'Synced from Apple Health'`, () => {});
        this.db.run('ALTER TABLE users ADD COLUMN last_location_at DATETIME', (err) => {
          if (err) console.error('Migration error:', err.message);
          // budget_categories: rebuild to drop the global UNIQUE(name) so each
          // household can have its own same-named categories (e.g. "Groceries").
          // Must finish before resolve so the backfill sees the new column.
          this._migrateBudgetCategoriesGroup().then(resolve).catch(() => resolve());
        });
      });
    });
  }

  // Ensure Jesse + Sophie share a "Fairbanks" household, fix any bad state
  runHouseholdMigrations() {
    return new Promise((resolve, reject) => {
      // Find jesse and sophie specifically
      this.db.all("SELECT id, username, name FROM users WHERE username IN ('jesse', 'sophie')", (err, users) => {
        if (err || !users || users.length === 0) {
          console.log('Household migration: no jesse/sophie users found');
          return this._backfillGroupIds().then(resolve, reject);
        }
        const jesse = users.find(u => u.username === 'jesse');
        const sophie = users.find(u => u.username === 'sophie');
        console.log('Found users:', JSON.stringify({ jesse, sophie }));

        // Find their current household memberships
        const userIds = [jesse?.id, sophie?.id].filter(Boolean);
        this.db.all(`
          SELECT gm.user_id, g.id as group_id, g.name as group_name
          FROM group_members gm
          JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
          WHERE gm.user_id IN (${userIds.map(() => '?').join(',')})
        `, userIds, (err2, memberships) => {
          console.log('Current household memberships:', JSON.stringify(memberships));

          this.db.serialize(() => {
            let householdId = null;

            // Find or determine the household to use
            const jesseHH = memberships?.find(m => m.user_id === jesse?.id);
            const sophieHH = memberships?.find(m => m.user_id === sophie?.id);

            if (jesseHH) {
              householdId = jesseHH.group_id;
            } else if (sophieHH) {
              householdId = sophieHH.group_id;
            }

            if (householdId) {
              console.log(`Using existing household ${householdId}`);
              // Ensure both jesse and sophie are in this household
              for (const uid of userIds) {
                this.db.run(`INSERT INTO group_members (group_id, user_id, role, added_by)
                  SELECT ?, ?, 'admin', ? WHERE NOT EXISTS (
                    SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?
                  )`, [householdId, uid, uid, householdId, uid]);
              }
              // Remove jesse/sophie from any OTHER household groups
              this.db.run(`DELETE FROM group_members WHERE user_id IN (${userIds.join(',')})
                AND group_id != ? AND group_id IN (SELECT id FROM groups WHERE group_type = 'household')`,
                [householdId]);
              // Remove non-jesse/sophie users from this household (e.g. Ariel wrongly merged in)
              this.db.run(`DELETE FROM group_members WHERE group_id = ?
                AND user_id IS NOT NULL AND user_id NOT IN (${userIds.join(',')})`,
                [householdId]);
              // Rename to Fairbanks
              this.db.run("UPDATE groups SET name = 'Fairbanks' WHERE id = ?", [householdId], () => {
                console.log(`✅ Fairbanks household = group ${householdId} with users ${userIds}`);
                // Restore any non-jesse/sophie users removed from wrong merges back to their households
                this._restoreOtherHouseholds().then(() => {
                  this._backfillGroupIds().then(resolve, reject);
                });
              });
            } else {
              // Neither has a household — create one
              console.log('Creating new Fairbanks household');
              this.db.run("INSERT INTO groups (name, group_type, invite_code, created_by) VALUES ('Fairbanks', 'household', ?, ?)",
                [crypto.randomBytes(6).toString('hex').toUpperCase(), jesse?.id || userIds[0]], function() {
                  const newId = this.lastID;
                  for (const uid of userIds) {
                    this.db.run(`INSERT INTO group_members (group_id, user_id, role, added_by) VALUES (?, ?, 'admin', ?)`,
                      [newId, uid, uid]);
                  }
                  console.log(`✅ Created Fairbanks household = group ${newId}`);
                  this._backfillGroupIds().then(resolve, reject);
                }.bind(this));
            }
          });
        });
      });
    });
  }

  // Ensure non-jesse/sophie users are back in their own households
  _restoreOtherHouseholds() {
    return new Promise((resolve) => {
      // Find users not in any household and restore them
      this.db.all(`
        SELECT u.id, u.username, g.id as old_group_id, g.name as old_group_name
        FROM users u
        JOIN groups g ON g.created_by = u.id AND g.group_type = 'household'
        WHERE u.username NOT IN ('jesse', 'sophie')
        AND NOT EXISTS (
          SELECT 1 FROM group_members gm
          JOIN groups g2 ON g2.id = gm.group_id AND g2.group_type = 'household'
          WHERE gm.user_id = u.id
        )
      `, (err, orphans) => {
        if (!orphans || orphans.length === 0) return resolve();
        console.log('Restoring orphaned users to their households:', JSON.stringify(orphans));
        let pending = orphans.length;
        for (const orphan of orphans) {
          this.db.run(`INSERT INTO group_members (group_id, user_id, role, added_by)
            SELECT ?, ?, 'admin', ? WHERE NOT EXISTS (
              SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?
            )`, [orphan.old_group_id, orphan.id, orphan.id, orphan.old_group_id, orphan.id], () => {
              pending--;
              if (pending === 0) resolve();
            });
        }
      });
    });
  }

  // Rebuild budget_categories to add group_id and drop the legacy global
  // UNIQUE(name) constraint, replacing it with UNIQUE(name, group_id).
  // Idempotent: only rebuilds if the group_id column is not yet present.
  _migrateBudgetCategoriesGroup() {
    return new Promise((resolve) => {
      this.db.all('PRAGMA table_info(budget_categories)', (err, cols) => {
        if (err || !cols) return resolve();
        const hasGroup = cols.some(c => c.name === 'group_id');
        if (hasGroup) return resolve();
        this.db.serialize(() => {
          // Wrap the rebuild in a transaction so a crash can't leave the
          // canonical table dropped with data stranded in the _new table.
          this.db.run('BEGIN');
          this.db.run(`CREATE TABLE IF NOT EXISTS budget_categories_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            monthly_limit DECIMAL(10,2),
            color TEXT,
            group_id INTEGER REFERENCES groups(id),
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(name, group_id)
          )`);
          this.db.run(`INSERT INTO budget_categories_new (id, name, monthly_limit, color, created_at)
            SELECT id, name, monthly_limit, color, created_at FROM budget_categories`);
          this.db.run('DROP TABLE budget_categories');
          this.db.run('ALTER TABLE budget_categories_new RENAME TO budget_categories');
          this.db.run('COMMIT', (err) => {
            if (err) { this.db.run('ROLLBACK', () => resolve()); return; }
            console.log('Migration: rebuilt budget_categories with per-household uniqueness');
            this.db.run('CREATE INDEX IF NOT EXISTS idx_budget_categories_group ON budget_categories(group_id)', () => resolve());
          });
        });
      });
    });
  }

  // Backfill group_id — runs EVERY startup, reassigns ALL records to jesse+sophie's household
  _backfillGroupIds() {
    return new Promise((resolve, reject) => {
      // Find the Fairbanks household (jesse+sophie's household)
      this.db.get(`
        SELECT g.id FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        JOIN users u ON u.id = gm.user_id AND u.username = 'jesse'
        WHERE g.group_type = 'household'
        LIMIT 1
      `, (err, hhRow) => {
        const householdId = hhRow?.id;
        console.log(`Backfill: jesse's household = ${householdId}`);
        if (!householdId) return resolve();

        this.db.serialize(() => {
          // Assign LEGACY (pre-isolation, NULL) records to the primary household.
          // NULL-only — must NOT touch rows already assigned to another household,
          // or every restart would steal other households' records into this one.
          this.db.run('UPDATE appointments SET group_id = ? WHERE group_id IS NULL',
            [householdId], function() {
              console.log(`Backfill: updated ${this.changes} appointments to household ${householdId}`);
            });
          this.db.run('UPDATE decisions SET group_id = ? WHERE group_id IS NULL',
            [householdId], function() {
              console.log(`Backfill: updated ${this.changes} decisions to household ${householdId}`);
            });
          this.db.run('UPDATE rivalries SET group_id = ? WHERE group_id IS NULL',
            [householdId], function() {
              console.log(`Backfill: updated ${this.changes} rivalries to household ${householdId}`);
            });
          // Assign legacy tasks (no group) to the primary household — NULL-only so
          // future per-household assignments are preserved.
          this.db.run('UPDATE tasks SET group_id = ? WHERE group_id IS NULL',
            [householdId], function() {
              console.log(`Backfill: updated ${this.changes} tasks to household ${householdId}`);
            });
          // Legacy (pre-isolation) records had no group_id — they were all created
          // by the primary household, so assign NULL-only rows to it. NULL-only
          // preserves any per-household assignments made after isolation shipped.
          for (const t of ['budget_categories', 'receipts', 'budget_projects', 'project_expenses',
                           'pantry', 'trips', 'gift_people', 'gift_ideas', 'special_events', 'family_addresses']) {
            this.db.run(`UPDATE ${t} SET group_id = ? WHERE group_id IS NULL`,
              [householdId], function(uErr) {
                if (!uErr && this.changes) console.log(`Backfill: updated ${this.changes} ${t} to household ${householdId}`);
              });
          }
          // Fix rivalry entries where member_name doesn't match the rivalry's participant name
          // e.g. entry has "Sophie" or "sophie" but rivalry has "Sophie Chiasson"
          this.db.all(`
            SELECT re.id, re.member_name, r.initiator_name, r.opponent_name, r.participants
            FROM rivalry_entries re
            JOIN rivalries r ON r.id = re.rivalry_id
          `, (bfErr, rows) => {
            if (bfErr || !rows) { resolve(); return; }
            let fixed = 0;
            const stmts = [];
            for (const row of rows) {
              let participants;
              try { participants = JSON.parse(row.participants || '[]'); } catch { participants = []; }
              if (!participants.length) participants = [row.initiator_name, row.opponent_name];
              // Check if member_name already exactly matches a participant (case-insensitive)
              const exactMatch = participants.find(p => p.toLowerCase() === row.member_name.toLowerCase());
              if (exactMatch) continue;
              // Find participant whose first name matches entry member_name
              const prefixMatch = participants.find(p =>
                p.toLowerCase().startsWith(row.member_name.toLowerCase() + ' ')
                || row.member_name.toLowerCase().startsWith(p.toLowerCase() + ' ')
              );
              if (prefixMatch) {
                stmts.push([prefixMatch, row.id]);
                fixed++;
              }
            }
            if (stmts.length > 0) {
              for (const [name, id] of stmts) {
                this.db.run('UPDATE rivalry_entries SET member_name = ? WHERE id = ?', [name, id]);
              }
              console.log(`Backfill: normalized ${fixed} rivalry entry names to match participant names`);
            }
          });
          // Clear legacy delta-append HealthKit entries on ACTIVE rivalries. The old
          // model appended a delta row per sync (and split across "jesse"/"Jesse"
          // name forms), double-counting via SUM(value). The app now pushes one
          // idempotent per-day total per member, so wiping active synced rows lets
          // them repopulate correctly on next sync. Completed rivalries keep their
          // stored final totals; manual entries (note != synced) are untouched.
          // Only legacy rows (no activity_date) — new per-day rows survive restarts.
          this.db.run(`DELETE FROM rivalry_entries
            WHERE note = 'Synced from Apple Health'
            AND activity_date IS NULL
            AND rivalry_id IN (SELECT id FROM rivalries WHERE status = 'active')`,
            function(delErr) {
              if (delErr) return;
              if (this.changes) console.log(`Backfill: cleared ${this.changes} legacy synced entries on active rivalries (re-syncing as daily totals)`);
            });
          resolve();
        });
      });
    });
  }

  // Get the user's household group ID
  getSharedGroupByNames(name1, name2) {
    return new Promise((resolve, reject) => {
      this.db.get(`
        SELECT g.id FROM groups g
        JOIN group_members gm1 ON gm1.group_id = g.id
        JOIN users u1 ON u1.id = gm1.user_id AND u1.name = ?
        JOIN group_members gm2 ON gm2.group_id = g.id
        JOIN users u2 ON u2.id = gm2.user_id AND u2.name = ?
        ORDER BY CASE WHEN g.group_type = 'household' THEN 1 ELSE 0 END, g.id
        LIMIT 1
      `, [name1, name2], (err, row) => {
        if (err) reject(err);
        else resolve(row?.id || null);
      });
    });
  }

  // Primary household — used as the DEFAULT target when CREATING household-scoped
  // data. Prefers the household with the MOST members (the shared one) over a
  // stale single-member solo group left over from signup — otherwise a spouse's
  // events silently land in their private group that their partner can't see.
  // Tiebreak by lowest id. A user may belong to more than one household, so reads
  // must use the (all-households) subquery, not this.
  getUserHouseholdId(userId) {
    return new Promise((resolve, reject) => {
      this.db.get(`
        SELECT g.id,
          (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id) AS member_count
        FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        WHERE gm.user_id = ? AND g.group_type = 'household'
        ORDER BY member_count DESC, g.id ASC
        LIMIT 1
      `, [userId], (err, row) => {
        if (err) reject(err);
        else resolve(row?.id || null);
      });
    });
  }

  // ALL households the user belongs to (usually one, but two for shared-custody
  // teens / adult kids with divorced parents). Household-scoped reads filter by
  // this set so a multi-household member sees every household they're in — and
  // ONLY those (strictly per-membership, so no cross-household leak).
  getUserHouseholdIds(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT g.id FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        WHERE gm.user_id = ? AND g.group_type = 'household'
        ORDER BY g.id
      `, [userId], (err, rows) => {
        if (err) reject(err);
        else resolve((rows || []).map(r => r.id));
      });
    });
  }

  // Is the user an admin of this group? Used to gate destructive/membership ops.
  isGroupAdmin(groupId, userId) {
    return new Promise((resolve, reject) => {
      this.db.get("SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ? AND role = 'admin' LIMIT 1",
        [groupId, userId], (err, row) => err ? reject(err) : resolve(!!row));
    });
  }

  // Is `groupId` a HOUSEHOLD the user belongs to? Used by household-row guards so
  // they accept any of a multi-household user's households (not just the primary)
  // while still rejecting clans and other households.
  isHouseholdMember(groupId, userId) {
    return new Promise((resolve, reject) => {
      this.db.get(`SELECT 1 FROM group_members gm JOIN groups g ON g.id = gm.group_id
         WHERE gm.group_id = ? AND gm.user_id = ? AND g.group_type = 'household' LIMIT 1`,
        [groupId, userId], (err, row) => err ? reject(err) : resolve(!!row));
    });
  }

  // Task operations
  addTask(task) {
    return new Promise((resolve, reject) => {
      const stmt = this.db.prepare(`
        INSERT INTO tasks (category, title, description, priority, due_date, due_time, assigned_to, recurrence_pattern, tags, group_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        task.tags ? task.tags.join(',') : null,
        task.group_id || null
      ], function(err) {
        stmt.finalize();
        if (err) reject(err);
        else resolve({ id: this.lastID, ...task });
      });
    });
  }

  getTasks(filters = {}, userId = null) {
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

      if (userId) {
        // Household-scoped: the user's household(s) only, never their clans.
        sql += ` AND group_id IN (SELECT gm.group_id FROM group_members gm
                   JOIN groups g ON g.id = gm.group_id
                   WHERE gm.user_id = ? AND g.group_type = 'household')`;
        params.push(parseInt(userId, 10));
      }

      // Safety cap: household-scoped list, newest first. Far above realistic
      // family scale; prevents an unbounded scan if data accumulates for years.
      // (Full cursor pagination is deferred — see review notes.)
      sql += ' ORDER BY created_at DESC LIMIT 1000';

      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  // Scoped to the user's household when groupId is provided (prevents cross-household completion).
  updateTask(id, updates, groupId = null) {
    const ALLOWED = new Set(['title', 'description', 'category', 'priority', 'due_date', 'due_time', 'assigned_to', 'status']);
    const keys = Object.keys(updates).filter(k => ALLOWED.has(k));
    if (!keys.length) return Promise.resolve({ id, changed: 0 });
    return new Promise((resolve, reject) => {
      const sets = keys.map(k => `${k} = ?`).join(', ');
      const params = [...keys.map(k => updates[k]), id];
      const sql = groupId
        ? `UPDATE tasks SET ${sets} WHERE id = ? AND group_id = ?`
        : `UPDATE tasks SET ${sets} WHERE id = ?`;
      if (groupId) params.push(groupId);
      this.db.run(sql, params, function(err) {
        if (err) reject(err);
        else resolve({ id, changed: this.changes });
      });
    });
  }

  deleteTask(id, groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId
        ? 'DELETE FROM tasks WHERE id = ? AND group_id = ?'
        : 'DELETE FROM tasks WHERE id = ?';
      const params = groupId ? [id, groupId] : [id];
      this.db.run(sql, params, function(err) {
        if (err) reject(err);
        else resolve({ id, changed: this.changes });
      });
    });
  }

  completeTask(id, groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId
        ? 'UPDATE tasks SET status = "completed", completed_at = CURRENT_TIMESTAMP WHERE id = ? AND group_id = ?'
        : 'UPDATE tasks SET status = "completed", completed_at = CURRENT_TIMESTAMP WHERE id = ?';
      const params = groupId ? [id, groupId] : [id];
      this.db.run(sql, params,
        function(err) {
          if (err) reject(err);
          else resolve({ id, status: 'completed', changed: this.changes });
        }
      );
    });
  }

  // Grocery operations
  addGrocery(item, category = null, quantity = '1', addedBy = 'jesse', groupId = null) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO groceries (item, category, quantity, added_by, group_id) VALUES (?, ?, ?, ?, ?)',
        [item, category, quantity, addedBy, groupId],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, item, category, quantity });
        }
      );
    });
  }

  getGroceries(status = 'needed', userId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM groceries WHERE status = ?';
      if (userId) {
        const uid = safeUid(userId);
        sql += ` AND group_id IN (SELECT gm.group_id FROM group_members gm
                   JOIN groups g ON g.id = gm.group_id
                   WHERE gm.user_id = ${uid} AND g.group_type = 'household')`;
      }
      sql += ' ORDER BY category, item';
      this.db.all(sql, [status], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
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
        'INSERT INTO appointments (title, description, appointment_date, appointment_time, location, with_person, category, person_tags, recurrence_rule, recurrence_end, group_id, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          appointment.title,
          appointment.description || null,
          appointment.appointment_date,
          appointment.appointment_time || null,
          appointment.location || null,
          appointment.with_person || null,
          appointment.category || 'appointments',
          appointment.person_tags ? (Array.isArray(appointment.person_tags) ? appointment.person_tags.join(',') : String(appointment.person_tags)) : null,
          appointment.recurrence_rule || null,
          appointment.recurrence_end || null,
          appointment.group_id || null,
          appointment.created_by || null
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
        const uid = safeUid(userId);
        sql += ` AND group_id IN (SELECT gm.group_id FROM group_members gm
                   JOIN groups g ON g.id = gm.group_id
                   WHERE gm.user_id = ${uid} AND g.group_type = 'household')`;
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
        const uid = safeUid(userId);
        sql += ` AND group_id IN (SELECT gm.group_id FROM group_members gm
                   JOIN groups g ON g.id = gm.group_id
                   WHERE gm.user_id = ${uid} AND g.group_type = 'household')`;
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
        const uid = safeUid(userId);
        sql += ` AND group_id IN (SELECT gm.group_id FROM group_members gm
                   JOIN groups g ON g.id = gm.group_id
                   WHERE gm.user_id = ${uid} AND g.group_type = 'household')`;
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

  // ---- Synced device-calendar events (household calendar sharing) ----

  // Upsert the caller's device-calendar events for a date window and soft-delete
  // any of their previously-synced events in that window that are no longer
  // present (handles deletions on the phone). Only ever touches user_id's own
  // rows, so it can't disturb other household members' synced events.
  upsertSyncedCalendarEvents(userId, groupId, events, windowStart, windowEnd) {
    return new Promise((resolve, reject) => {
      const run = (sql, p = []) => new Promise((r, j) => this.db.run(sql, p, function (e) { e ? j(e) : r(this); }));
      (async () => {
        await run('BEGIN');
        try {
          // Tentatively mark the window deleted; each re-sent event revives itself.
          await run(
            'UPDATE synced_calendar_events SET deleted = 1 WHERE user_id = ? AND starts_at >= ? AND starts_at < ?',
            [userId, windowStart, windowEnd]
          );
          for (const ev of events || []) {
            if (!ev || !ev.external_id || !ev.starts_at) continue;
            await run(
              `INSERT INTO synced_calendar_events
                 (user_id, group_id, external_id, calendar_name, title, location, starts_at, ends_at, all_day, deleted, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP)
               ON CONFLICT(user_id, external_id, starts_at) DO UPDATE SET
                 group_id = excluded.group_id, calendar_name = excluded.calendar_name,
                 title = excluded.title, location = excluded.location,
                 ends_at = excluded.ends_at, all_day = excluded.all_day,
                 deleted = 0, updated_at = CURRENT_TIMESTAMP`,
              [userId, groupId || null, ev.external_id, ev.calendar_name || null, ev.title || null,
               ev.location || null, ev.starts_at, ev.ends_at || null, ev.all_day ? 1 : 0]
            );
          }
          await run('COMMIT');
          resolve({ synced: (events || []).length });
        } catch (e) {
          await run('ROLLBACK').catch(() => {});
          reject(e);
        }
      })();
    });
  }

  // Household members' synced device-calendar events for a month (group-scoped).
  getSyncedCalendarEventsByMonth(year, month, userId) {
    return new Promise((resolve, reject) => {
      const uid = safeUid(userId);
      // Half-open range instead of substr() so idx_synced_cal_group_date is
      // usable — this is the app's hottest polled query.
      const y = parseInt(year, 10), m = parseInt(month, 10);
      const monthStart = `${y}-${String(m).padStart(2, '0')}-01`;
      const monthEnd = m === 12
        ? `${y + 1}-01-01`
        : `${y}-${String(m + 1).padStart(2, '0')}-01`;
      const sql = `
        SELECT s.id, s.user_id AS owner_id, u.name AS owner_name, s.external_id,
          s.calendar_name, s.title, s.location, s.starts_at, s.ends_at, s.all_day, s.group_id
        FROM synced_calendar_events s
        JOIN users u ON u.id = s.user_id
        WHERE s.deleted = 0
          AND s.starts_at >= ? AND s.starts_at < ?
          AND s.group_id IN (
            SELECT gm.group_id FROM group_members gm
            JOIN groups g ON g.id = gm.group_id
            WHERE gm.user_id = ? AND g.group_type = 'household')
        ORDER BY s.starts_at`;
      this.db.all(sql, [monthStart, monthEnd, uid], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  // Housekeeping: drop soft-deleted synced events once every client has had
  // ample time to observe the tombstone. Keeps the hottest table bounded.
  purgeDeletedSyncedEvents(days = 30) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `DELETE FROM synced_calendar_events WHERE deleted = 1 AND updated_at < datetime('now', ?)`,
        [`-${parseInt(days, 10) || 30} days`],
        function (err) { err ? reject(err) : resolve({ purged: this.changes }); }
      );
    });
  }

  updateAppointment(id, updates) {
    const ALLOWED = new Set(['title', 'description', 'appointment_date', 'appointment_time', 'location', 'with_person', 'category', 'person_tags', 'recurrence_rule', 'recurrence_end', 'reminder_sent']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE appointments SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  // Event attachments (polymorphic links from an appointment to other entities)
  // Resolves a display title/subtitle for each attached entity in one pass so the
  // client can render previews without a fetch per item.
  getEventAttachments(appointmentId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM event_attachments WHERE appointment_id = ? ORDER BY created_at',
        [appointmentId],
        async (err, rows) => {
          if (err) return reject(err);
          try {
            const enriched = await Promise.all((rows || []).map(r => this._resolveAttachment(r)));
            resolve(enriched);
          } catch (e) { reject(e); }
        }
      );
    });
  }

  // Look up the source entity for one attachment row and attach title/subtitle.
  // If the source was deleted, the attachment still returns with a fallback label.
  _resolveAttachment(row) {
    const specs = {
      list:      { table: 'lists',       title: 'name',        subtitle: 'list_type' },
      note:      { table: 'notes',       title: 'title',       subtitle: 'body' },
      decision:  { table: 'decisions',   title: 'title',       subtitle: 'decision_type' },
      receipt:   { table: 'receipts',    title: 'merchant',    subtitle: 'amount' },
      trip:      { table: 'trips',       title: 'destination', subtitle: 'traveler' },
      itinerary: { table: 'itineraries', title: 'title',       subtitle: 'start_date' },
      task:      { table: 'tasks',       title: 'title',       subtitle: 'category' },
    };
    const spec = specs[row.attachment_type];
    const base = {
      id: row.id,
      appointment_id: row.appointment_id,
      attachment_type: row.attachment_type,
      attachment_id: row.attachment_id,
      created_at: row.created_at,
    };
    if (!spec) return Promise.resolve({ ...base, title: row.attachment_type, subtitle: null, missing: true });
    return new Promise((resolve) => {
      this.db.get(
        `SELECT ${spec.title} AS _title, ${spec.subtitle} AS _subtitle FROM ${spec.table} WHERE id = ?`,
        [row.attachment_id],
        (err, item) => {
          if (err || !item) return resolve({ ...base, title: `(deleted ${row.attachment_type})`, subtitle: null, missing: true });
          let subtitle = item._subtitle != null ? String(item._subtitle) : null;
          if (row.attachment_type === 'receipt' && subtitle != null) subtitle = '$' + subtitle;
          if (row.attachment_type === 'note' && subtitle) subtitle = subtitle.slice(0, 80);
          resolve({ ...base, title: item._title || `(${row.attachment_type})`, subtitle });
        }
      );
    });
  }

  addEventAttachment({ appointment_id, attachment_type, attachment_id, group_id, added_by }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT OR IGNORE INTO event_attachments (appointment_id, attachment_type, attachment_id, group_id, added_by)
         VALUES (?, ?, ?, ?, ?)`,
        [appointment_id, attachment_type, attachment_id, group_id || null, added_by || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  // Scope the delete to the appointment so a stray attachment id can't be removed
  // from another event.
  deleteEventAttachment(id, appointmentId) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'DELETE FROM event_attachments WHERE id = ? AND appointment_id = ?',
        [id, appointmentId],
        function(err) {
          if (err) reject(err);
          else resolve({ id, deleted: this.changes > 0 });
        }
      );
    });
  }

  // Receipt operations
  addReceipt(receipt) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO receipts (amount, merchant, date, category, payment_method, image_path, notes, processed_by, email_id, added_by, itinerary_id, group_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
          receipt.added_by || 'jesse',
          receipt.itinerary_id || null,
          receipt.group_id || null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...receipt });
        }
      );
    });
  }

  getReceipts(filters = {}, groupId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM receipts WHERE 1=1';
      const params = [];

      if (groupId != null) {
        sql += ' AND group_id = ?';
        params.push(groupId);
      }
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

  getBudgetSummary(month, groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT
          c.name as category,
          c.monthly_limit,
          c.color,
          COALESCE(SUM(r.amount), 0) as spent
        FROM budget_categories c
        LEFT JOIN receipts r ON LOWER(c.name) = LOWER(r.category) AND strftime('%Y-%m', r.date) = ? AND r.itinerary_id IS NULL
          ${groupId != null ? 'AND r.group_id = ?' : ''}
        WHERE ${groupId != null ? 'c.group_id = ?' : '1=1'}
        GROUP BY c.name
        ORDER BY c.name
      `;
      const params = groupId != null ? [month, groupId, groupId] : [month];
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  getBudgetCategories(groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId != null
        ? 'SELECT * FROM budget_categories WHERE group_id = ? ORDER BY name'
        : 'SELECT * FROM budget_categories ORDER BY name';
      this.db.all(sql, groupId != null ? [groupId] : [], (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
      });
    });
  }

  addBudgetCategory(name, monthlyLimit, color, groupId = null) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO budget_categories (name, monthly_limit, color, group_id) VALUES (?, ?, ?, ?)',
        [name, monthlyLimit || null, color || null, groupId || null],
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

  ensureBudgetCategory(name, groupId = null) {
    return new Promise((resolve, reject) => {
      const lookupSql = groupId != null
        ? 'SELECT id FROM budget_categories WHERE LOWER(name) = LOWER(?) AND group_id = ?'
        : 'SELECT id FROM budget_categories WHERE LOWER(name) = LOWER(?)';
      this.db.get(lookupSql, groupId != null ? [name, groupId] : [name], (err, row) => {
        if (err) return reject(err);
        if (row) return resolve(row.id);
        this.db.run('INSERT INTO budget_categories (name, group_id) VALUES (?, ?)', [name, groupId || null], function(err2) {
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
        'INSERT INTO pantry (item, category, location, quantity, unit, expiry_date, receipt_id, added_by, group_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [item.item, item.category || null, item.location || 'pantry', item.quantity || '1', item.unit || null, item.expiry_date || null, item.receipt_id || null, item.added_by || 'jesse', item.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...item });
        }
      );
    });
  }

  getPantry(filters = {}, groupId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM pantry WHERE 1=1';
      const params = [];
      if (groupId != null) { sql += ' AND group_id = ?'; params.push(groupId); }
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
    const ALLOWED = new Set(['item', 'category', 'location', 'quantity', 'unit', 'expiry_date']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
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
        'INSERT INTO trips (traveler, origin, origin_lat, origin_lng, destination, destination_lat, destination_lng, purpose, status, eta_minutes, group_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [trip.traveler, trip.origin || null, trip.origin_lat || null, trip.origin_lng || null, trip.destination, trip.destination_lat || null, trip.destination_lng || null, trip.purpose || null, 'active', trip.eta_minutes || null, trip.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...trip });
        }
      );
    });
  }

  getTrips(filters = {}, groupId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM trips WHERE 1=1';
      const params = [];
      if (groupId != null) { sql += ' AND group_id = ?'; params.push(groupId); }
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
    const ALLOWED = new Set(['origin', 'origin_lat', 'origin_lng', 'destination', 'destination_lat', 'destination_lng', 'purpose', 'status', 'current_lat', 'current_lng', 'eta_minutes', 'started_at', 'arrived_at']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
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

  deleteTrip(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM trips WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id });
      });
    });
  }

  // Family address operations
  addFamilyAddress(addr) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO family_addresses (name, address, lat, lng, radius_meters, created_by, group_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [addr.name, addr.address || null, addr.lat, addr.lng, addr.radius_meters || 500, addr.created_by || 'jesse', addr.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...addr });
        }
      );
    });
  }

  getFamilyAddresses(groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId != null
        ? 'SELECT * FROM family_addresses WHERE group_id = ? ORDER BY name'
        : 'SELECT * FROM family_addresses ORDER BY name';
      this.db.all(sql, groupId != null ? [groupId] : [], (err, rows) => {
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
        `INSERT INTO decisions (title, decision_type, body, link_url, photo_data, poll_options, creator_name, status, expires_at, group_id, person_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
          decision.group_id || null,
          decision.person_id || null
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
        const uid = safeUid(userId);
        sql += ` AND group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})`;
      }
      sql += ' ORDER BY datetime(created_at) DESC LIMIT 1000'; // safety cap (household-scoped); full pagination deferred
      this.db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve(rows.map(row => ({ ...row, poll_options: this.parseJSONList(row.poll_options) })));
      });
    });
  }

  getDecisionById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM decisions WHERE id = ?', [id], (err, row) => {
        if (err) reject(err);
        else resolve(row ? { ...row, poll_options: this.parseJSONList(row.poll_options) } : null);
      });
    });
  }

  updateDecision(id, updates) {
    const ALLOWED = new Set(['title', 'decision_type', 'body', 'link_url', 'photo_data', 'poll_options', 'status', 'expires_at', 'person_id']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(key === 'poll_options' ? JSON.stringify(value || []) : value);
      }
      if (!fields.length) return resolve({ id });
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
        `INSERT INTO rivalries (title, challenge_type, initiator_name, opponent_name, start_date, end_date, status, point_value, winner_name, group_id, participants, rivalry_type, team_a, team_b)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
          rivalry.group_id || null,
          rivalry.participants
            ? (Array.isArray(rivalry.participants) ? JSON.stringify(rivalry.participants) : String(rivalry.participants))
            : null,
          rivalry.rivalry_type || 'individual',
          rivalry.team_a ? (Array.isArray(rivalry.team_a) ? JSON.stringify(rivalry.team_a) : String(rivalry.team_a)) : null,
          rivalry.team_b ? (Array.isArray(rivalry.team_b) ? JSON.stringify(rivalry.team_b) : String(rivalry.team_b)) : null
        ],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...rivalry });
        }
      );
    });
  }

  getRivalryById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM rivalries WHERE id = ?', [id], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  getRivalryEntryTotals(rivalryId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT member_name, SUM(value) as total FROM rivalry_entries WHERE rivalry_id = ? GROUP BY member_name',
        [rivalryId],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  // Batched version of getRivalryEntryTotals: one query for many rivalries,
  // returns a Map<rivalry_id, [{member_name, total}]>. Avoids N+1 when
  // enriching a list of rivalries with their score totals.
  getRivalryEntryTotalsBatch(rivalryIds = []) {
    return new Promise((resolve, reject) => {
      if (!rivalryIds.length) return resolve(new Map());
      const placeholders = rivalryIds.map(() => '?').join(',');
      this.db.all(
        `SELECT rivalry_id, member_name, SUM(value) as total
           FROM rivalry_entries
          WHERE rivalry_id IN (${placeholders})
          GROUP BY rivalry_id, member_name`,
        rivalryIds,
        (err, rows) => {
          if (err) return reject(err);
          const byRivalry = new Map();
          for (const row of rows || []) {
            if (!byRivalry.has(row.rivalry_id)) byRivalry.set(row.rivalry_id, []);
            byRivalry.get(row.rivalry_id).push({ member_name: row.member_name, total: row.total });
          }
          resolve(byRivalry);
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
        const uid = safeUid(userId);
        sql += ` AND group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})`;
      }
      sql += ' ORDER BY datetime(created_at) DESC LIMIT 1000'; // safety cap (household-scoped); full pagination deferred
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  updateRivalry(id, updates) {
    const ALLOWED = new Set(['title', 'challenge_type', 'initiator_name', 'opponent_name', 'start_date', 'end_date', 'status', 'point_value', 'winner_name', 'participants', 'rivalry_type', 'team_a', 'team_b', 'winner_team']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE rivalries SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  deleteRivalry(id) {
    return new Promise((resolve, reject) => {
      // rivalry_entries cascade via FK ON DELETE CASCADE.
      this.db.run('DELETE FROM rivalries WHERE id = ?', [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
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
      // HealthKit syncs carry a daily total tagged with activity_date. Upsert so
      // re-syncing a day OVERWRITES its total instead of appending — never doubles.
      if (entry.note === 'Synced from Apple Health' && entry.activity_date) {
        this.db.run(
          `INSERT INTO rivalry_entries (rivalry_id, member_name, value, note, is_verified, activity_date)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(rivalry_id, member_name, activity_date) WHERE note = 'Synced from Apple Health'
           DO UPDATE SET value = excluded.value, is_verified = excluded.is_verified, logged_at = CURRENT_TIMESTAMP`,
          [entry.rivalry_id, entry.member_name, entry.value, entry.note, entry.is_verified ? 1 : 0, entry.activity_date],
          function(err) {
            if (err) reject(err);
            else resolve({ id: this.lastID, ...entry });
          }
        );
      } else {
        this._insertRivalryEntry(entry, resolve, reject);
      }
    });
  }

  _insertRivalryEntry(entry, resolve, reject) {
    this.db.run(
      `INSERT INTO rivalry_entries (rivalry_id, member_name, value, note, is_verified, activity_date)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [entry.rivalry_id, entry.member_name, entry.value, entry.note || null, entry.is_verified ? 1 : 0, entry.activity_date || null],
      function(err) {
        if (err) reject(err);
        else resolve({ id: this.lastID, ...entry });
      }
    );
  }

  getUserIdByName(name) {
    return new Promise((resolve, reject) => {
      // Try exact match first, then first-name prefix match (e.g. "Sophie Chiasson" finds user "Sophie")
      this.db.get('SELECT id FROM users WHERE name = ? COLLATE NOCASE', [name], (err, row) => {
        if (err) return reject(err);
        if (row) return resolve(row.id);
        const firstName = name.split(' ')[0];
        if (firstName === name) return resolve(null);
        this.db.get('SELECT id FROM users WHERE name = ? COLLATE NOCASE', [firstName], (err2, row2) => {
          if (err2) reject(err2);
          else resolve(row2?.id || null);
        });
      });
    });
  }

  completeRivalryWithTotals(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM rivalries WHERE id = ?', [id], (err, rivalry) => {
        if (err) return reject(err);
        if (!rivalry) return reject(new Error('Rivalry not found'));

        this.db.all('SELECT member_name, SUM(value) as total FROM rivalry_entries WHERE rivalry_id = ? GROUP BY member_name', [id], (err2, totals) => {
          if (err2) return reject(err2);

          // Build participant list — from participants JSON or 1v1 fields
          let participants;
          try { participants = JSON.parse(rivalry.participants || '[]'); } catch { participants = []; }
          if (!participants.length) participants = [rivalry.initiator_name, rivalry.opponent_name];

          // Match entry names to participant names, handling "Sophie" vs "Sophie Chiasson"
          const nameMatch = (a, b) => {
            const aL = a.toLowerCase(), bL = b.toLowerCase();
            return aL === bL || aL.startsWith(bL + ' ') || bL.startsWith(aL + ' ');
          };
          const findTotal = (name) => totals.find(t => nameMatch(t.member_name, name))?.total || 0;

          const scores = participants.map(name => ({
            name,
            total: findTotal(name)
          })).sort((a, b) => b.total - a.total);

          // Team mode: sum each side; winner is the higher-total team.
          let teamA = [], teamB = [];
          try { teamA = JSON.parse(rivalry.team_a || '[]'); } catch (_) {}
          try { teamB = JSON.parse(rivalry.team_b || '[]'); } catch (_) {}
          const isTeam = rivalry.rivalry_type === 'team' && teamA.length > 0 && teamB.length > 0;
          const teamATotal = teamA.reduce((s, n) => s + findTotal(n), 0);
          const teamBTotal = teamB.reduce((s, n) => s + findTotal(n), 0);

          // For teams, iTotal/oTotal carry the two TEAM totals (reused by the client).
          const iTotal = isTeam ? teamATotal : findTotal(rivalry.initiator_name);
          const oTotal = isTeam ? teamBTotal : findTotal(rivalry.opponent_name);

          if (rivalry.status === 'completed') {
            return resolve({ rivalry, initiator_total: iTotal, opponent_total: oTotal, scores, winner_name: rivalry.winner_name, winner_team: rivalry.winner_team, already_completed: true });
          }

          // Determine winner
          let winnerName = null;
          let winnerTeam = null;
          if (isTeam) {
            if (teamATotal !== teamBTotal && (teamATotal > 0 || teamBTotal > 0)) {
              winnerTeam = teamATotal > teamBTotal ? 'a' : 'b';
              winnerName = (winnerTeam === 'a' ? teamA : teamB).join(' & ');
            }
          } else if (scores.length > 0 && scores[0].total > 0) {
            if (scores.length === 1 || scores[0].total > scores[1].total) {
              winnerName = scores[0].name;
            }
          }

          // Guard the transition in SQL so two concurrent completes can't both
          // "win" (which would duplicate the completion feed post and pushes).
          this.db.run('UPDATE rivalries SET status = ?, winner_name = ?, winner_team = ? WHERE id = ? AND status != ?',
            ['completed', winnerName, winnerTeam, id, 'completed'], function(err3) {
              if (err3) return reject(err3);
              const lost = this.changes === 0;
              resolve({
                rivalry: { ...rivalry, status: 'completed', winner_name: winnerName, winner_team: winnerTeam },
                initiator_total: iTotal, opponent_total: oTotal,
                scores, winner_name: winnerName, winner_team: winnerTeam, already_completed: lost
              });
            });
        });
      });
    });
  }

  // Participant-aware leaderboard: expands each rivalry's full participant set
  // (JSON `participants`, falling back to initiator+opponent) so 3rd+ players
  // are credited, then aggregates completions/wins/points in JS.
  getRivalryLeaderboard(userId = null) {
    return new Promise((resolve, reject) => {
      const groupFilter = userId
        ? `WHERE group_id IN (SELECT group_id FROM group_members WHERE user_id = ${safeUid(userId)})`
        : '';
      this.db.all(`SELECT * FROM rivalries ${groupFilter}`, [], (err, rows) => {
        if (err) return reject(err);
        const stats = new Map();
        const ensure = (n) => {
          if (!stats.has(n)) stats.set(n, { member_name: n, rivalries_completed: 0, rivalries_won: 0, total_points: 0 });
          return stats.get(n);
        };
        const parseArr = (s) => { try { const p = JSON.parse(s || '[]'); return Array.isArray(p) ? p.filter(Boolean).map(String) : []; } catch (_) { return []; } };
        for (const r of rows || []) {
          const teamA = parseArr(r.team_a), teamB = parseArr(r.team_b);
          let names = (r.rivalry_type === 'team') ? [...teamA, ...teamB] : parseArr(r.participants);
          if (!names.length) names = [r.initiator_name, r.opponent_name].filter(Boolean).map(String);
          const uniq = [...new Set(names)];
          for (const n of uniq) ensure(n);              // appear on the board even mid-rivalry
          if (r.status === 'completed') {
            for (const n of uniq) ensure(n).rivalries_completed += 1;
            if (r.rivalry_type === 'team' && r.winner_team) {
              // Every member of the winning team gets the win + points.
              for (const n of (r.winner_team === 'a' ? teamA : teamB)) {
                const w = ensure(String(n)); w.rivalries_won += 1; w.total_points += (r.point_value || 0);
              }
            } else if (r.winner_name) {
              const w = ensure(String(r.winner_name));
              w.rivalries_won += 1;
              w.total_points += (r.point_value || 0);
            }
          }
        }
        const out = [...stats.values()].sort((a, b) =>
          b.total_points - a.total_points || b.rivalries_won - a.rivalries_won || a.member_name.localeCompare(b.member_name));
        resolve(out);
      });
    });
  }

  // Itinerary operations
  createItinerary(data) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO itineraries (title, traveler_id, traveler_name, start_date, end_date, travelers, notes, status, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [data.title, data.traveler_id, data.traveler_name, data.start_date, data.end_date, data.travelers || null, data.notes || null, data.status || 'planning', data.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...data });
        }
      );
    });
  }

  getItineraries(userId) {
    return new Promise((resolve, reject) => {
      const uid = safeUid(userId);
      this.db.all(
        `SELECT * FROM itineraries WHERE traveler_id = ? OR group_id IN (SELECT group_id FROM group_members WHERE user_id = ?) ORDER BY datetime(start_date) DESC`,
        [uid, uid],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  getItineraryById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM itineraries WHERE id = ?', [id], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  updateItinerary(id, updates) {
    // group_id deliberately NOT updatable — re-homing an itinerary to another
    // group is an isolation escape; ownership is fixed at creation.
    const ALLOWED = new Set(['title', 'start_date', 'end_date', 'travelers', 'notes', 'status']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE itineraries SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  deleteItinerary(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM itineraries WHERE id = ?', [id], function(err) {
        if (err) reject(err);
        else resolve({ deleted: this.changes });
      });
    });
  }

  addItineraryStay(stay) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO itinerary_stays (itinerary_id, check_in, check_out, host_name, host_user_id, host_contact_id, location_name, address, lat, lng, notes, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [stay.itinerary_id, stay.check_in, stay.check_out, stay.host_name || null, stay.host_user_id || null, stay.host_contact_id || null, stay.location_name || null, stay.address || null, stay.lat || null, stay.lng || null, stay.notes || null, stay.status || 'draft'],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...stay });
        }
      );
    });
  }

  getItineraryStays(itineraryId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM itinerary_stays WHERE itinerary_id = ? ORDER BY check_in ASC',
        [itineraryId],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  updateItineraryStay(id, updates, itineraryId = null) {
    const ALLOWED = new Set(['check_in', 'check_out', 'host_name', 'host_user_id', 'host_contact_id', 'location_name', 'address', 'lat', 'lng', 'notes', 'status', 'calendar_event_id', 'host_calendar_event_id']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      let where = 'id = ?';
      if (itineraryId != null) { where += ' AND itinerary_id = ?'; params.push(itineraryId); }
      this.db.run(`UPDATE itinerary_stays SET ${fields.join(', ')} WHERE ${where}`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  deleteItineraryStay(id, itineraryId = null) {
    return new Promise((resolve, reject) => {
      const sql = itineraryId != null
        ? 'DELETE FROM itinerary_stays WHERE id = ? AND itinerary_id = ?'
        : 'DELETE FROM itinerary_stays WHERE id = ?';
      this.db.run(sql, itineraryId != null ? [id, itineraryId] : [id], function(err) {
        if (err) reject(err);
        else resolve({ deleted: this.changes });
      });
    });
  }

  getItineraryStayById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM itinerary_stays WHERE id = ?', [id], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  getPendingStayRequests(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT s.*, i.title as itinerary_title, i.traveler_name
         FROM itinerary_stays s
         JOIN itineraries i ON i.id = s.itinerary_id
         WHERE s.host_user_id = ? AND s.status = 'requested'
         ORDER BY s.check_in ASC`,
        [userId],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  getItineraryExpenses(itineraryId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM receipts WHERE itinerary_id = ? ORDER BY date DESC',
        [itineraryId],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  getItineraryExpenseTotal(itineraryId) {
    return new Promise((resolve, reject) => {
      this.db.get(
        'SELECT COALESCE(SUM(amount), 0) as total, COUNT(*) as count FROM receipts WHERE itinerary_id = ?',
        [itineraryId],
        (err, row) => err ? reject(err) : resolve(row || { total: 0, count: 0 })
      );
    });
  }

  // Gift operations
  addGiftPerson(person) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO gift_people (name, relationship, birthday, anniversary, notes, group_id) VALUES (?, ?, ?, ?, ?, ?)',
        [person.name, person.relationship || 'other', person.birthday || null, person.anniversary || null, person.notes || null, person.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...person });
        }
      );
    });
  }

  getGiftPeople(groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId != null
        ? 'SELECT * FROM gift_people WHERE group_id = ? ORDER BY name'
        : 'SELECT * FROM gift_people ORDER BY name';
      this.db.all(sql, groupId != null ? [groupId] : [], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  addGiftIdea(idea) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO gift_ideas (person_id, title, notes, link_url, estimated_price, status, for_event, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [idea.person_id, idea.title, idea.notes || null, idea.link_url || null, idea.estimated_price || null, idea.status || 'idea', idea.for_event || null, idea.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...idea });
        }
      );
    });
  }

  getGiftIdeas(personId = null, groupId = null) {
    return new Promise((resolve, reject) => {
      let sql = 'SELECT * FROM gift_ideas WHERE 1=1';
      const params = [];
      if (groupId != null) {
        sql += ' AND group_id = ?';
        params.push(groupId);
      }
      if (personId != null) {
        sql += ' AND person_id = ?';
        params.push(personId);
      }
      sql += ' ORDER BY datetime(created_at) DESC LIMIT 1000'; // safety cap (household-scoped); full pagination deferred
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  updateGiftIdea(id, updates) {
    const ALLOWED = new Set(['title', 'notes', 'link_url', 'estimated_price', 'status', 'for_event']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
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
        `INSERT INTO special_events (person_id, title, date, is_recurring, event_type, notes, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [event.person_id || null, event.title, event.date, event.is_recurring ? 1 : 0, event.event_type || 'custom', event.notes || null, event.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...event });
        }
      );
    });
  }

  getSpecialEvents(groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId != null
        ? 'SELECT * FROM special_events WHERE group_id = ? ORDER BY date'
        : 'SELECT * FROM special_events ORDER BY date';
      this.db.all(sql, groupId != null ? [groupId] : [], (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  updateSpecialEvent(id, updates) {
    const ALLOWED = new Set(['person_id', 'title', 'date', 'is_recurring', 'event_type', 'notes']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(key === 'is_recurring' ? (value ? 1 : 0) : value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE special_events SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        err ? reject(err) : resolve({ id, ...updates });
      });
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

  // ==========================================================================
  // People registry (gift_people doubles as the household's people list).
  // Rows are either linked to a user account (user_id) or dependents — kids
  // and relatives without devices — so milestones, gift ideas, key dates and
  // tagged decisions all hang off one person id.
  // ==========================================================================

  getPeople(groupId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT p.*,
           (SELECT COUNT(*) FROM gift_ideas g WHERE g.person_id = p.id) AS gift_idea_count,
           (SELECT COUNT(*) FROM milestones m WHERE m.person_id = p.id) AS milestone_count,
           (SELECT COUNT(*) FROM decisions d WHERE d.person_id = p.id) AS decision_count,
           (SELECT COUNT(*) FROM special_events s WHERE s.person_id = p.id) AS key_date_count
         FROM gift_people p WHERE p.group_id = ?
         ORDER BY p.is_dependent DESC, p.name`,
        [groupId],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  // Make sure every household USER has a person row (so adults appear in the
  // People hub without manual setup). Adopts an existing same-name gift person
  // first (pre-People rows like a manually added "Sophie") so nobody shows up
  // twice, then inserts rows for any still-unlinked users. Idempotent; runs on
  // every list fetch.
  ensureHouseholdUserPeople(groupId) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `UPDATE gift_people SET user_id = (
           SELECT u.id FROM users u
           JOIN group_members gm ON gm.user_id = u.id AND gm.group_id = gift_people.group_id
           WHERE lower(u.name) = lower(gift_people.name)
             AND NOT EXISTS (SELECT 1 FROM gift_people p2
                             WHERE p2.user_id = u.id AND p2.group_id = gift_people.group_id))
         WHERE group_id = ? AND user_id IS NULL
           AND EXISTS (
             SELECT 1 FROM users u
             JOIN group_members gm ON gm.user_id = u.id AND gm.group_id = gift_people.group_id
             WHERE lower(u.name) = lower(gift_people.name)
               AND NOT EXISTS (SELECT 1 FROM gift_people p2
                               WHERE p2.user_id = u.id AND p2.group_id = gift_people.group_id))`,
        [groupId],
        (err) => {
          if (err) return reject(err);
          this.db.run(
            `INSERT INTO gift_people (name, relationship, group_id, user_id, is_dependent)
             SELECT u.name, 'household', gm.group_id, u.id, 0
             FROM group_members gm
             JOIN users u ON u.id = gm.user_id
             WHERE gm.group_id = ?
               AND NOT EXISTS (SELECT 1 FROM gift_people p WHERE p.user_id = u.id AND p.group_id = gm.group_id)`,
            [groupId],
            function (err2) { err2 ? reject(err2) : resolve({ added: this.changes }); }
          );
        }
      );
    });
  }

  addPerson(person) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO gift_people (name, relationship, birthday, anniversary, notes, group_id, user_id, is_dependent, avatar_color)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [person.name, person.relationship || 'other', person.birthday || null,
         person.anniversary || null, person.notes || null, person.group_id,
         person.user_id || null, person.is_dependent ? 1 : 0, person.avatar_color || null],
        function (err) { err ? reject(err) : resolve({ id: this.lastID, ...person }); }
      );
    });
  }

  updatePerson(id, updates) {
    const ALLOWED = new Set(['name', 'relationship', 'birthday', 'anniversary', 'notes', 'is_dependent', 'avatar_color']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(key === 'is_dependent' ? (value ? 1 : 0) : value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE gift_people SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        err ? reject(err) : resolve({ id, ...updates });
      });
    });
  }

  deletePerson(id) {
    return new Promise((resolve, reject) => {
      // Decisions keep living when a person goes — just drop the tag. (Their
      // FK has no ON DELETE action on already-migrated DBs, so a lingering
      // tag would block the delete under foreign_keys=ON.)
      this.db.run('UPDATE decisions SET person_id = NULL WHERE person_id = ?', [id], (err) => {
        if (err) return reject(err);
        // gift_ideas / special_events / milestones cascade via their FKs.
        this.db.run('DELETE FROM gift_people WHERE id = ?', [id], (err2) => {
          err2 ? reject(err2) : resolve({ id, deleted: true });
        });
      });
    });
  }

  // ==========================================================================
  // Milestones — the family's memory line
  // ==========================================================================

  getMilestones(groupId, personId = null) {
    return new Promise((resolve, reject) => {
      let sql = `
        SELECT m.*, p.name AS person_name
        FROM milestones m JOIN gift_people p ON p.id = m.person_id
        WHERE m.group_id = ?`;
      const params = [groupId];
      if (personId != null) { sql += ' AND m.person_id = ?'; params.push(personId); }
      sql += ' ORDER BY m.milestone_date DESC, m.id DESC';
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  addMilestone(m) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO milestones (person_id, title, description, milestone_date, category,
           photo_data, shared_scope, shared_group_id, created_by, creator_name, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [m.person_id, m.title, m.description || null, m.milestone_date, m.category || 'moment',
         m.photo_data || null, m.shared_scope || 'household', m.shared_group_id || null,
         m.created_by || null, m.creator_name || null, m.group_id],
        function (err) { err ? reject(err) : resolve({ id: this.lastID, ...m }); }
      );
    });
  }

  updateMilestone(id, updates) {
    const ALLOWED = new Set(['title', 'description', 'milestone_date', 'category', 'photo_data']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE milestones SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        err ? reject(err) : resolve({ id, ...updates });
      });
    });
  }

  deleteMilestone(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM milestones WHERE id = ?', [id], (err) => {
        err ? reject(err) : resolve({ id, deleted: true });
      });
    });
  }

  // Decisions tagged "about" this person — the person card's discussion history.
  getDecisionsForPerson(personId, groupId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT * FROM decisions WHERE person_id = ? AND group_id = ? ORDER BY datetime(created_at) DESC',
        [personId, groupId],
        (err, rows) => err ? reject(err)
          : resolve((rows || []).map(r => ({ ...r, poll_options: this.parseJSONList(r.poll_options) })))
      );
    });
  }

  // Budget project operations
  addProject(project) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO budget_projects (name, budget, created_by, group_id) VALUES (?, ?, ?, ?)',
        [project.name, project.budget || 0, project.created_by || 'jesse', project.group_id || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, ...project });
        }
      );
    });
  }

  getProjects(groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = `
        SELECT p.*, COALESCE(SUM(e.amount), 0) as total_spent, COUNT(e.id) as expense_count
        FROM budget_projects p
        LEFT JOIN project_expenses e ON e.project_id = p.id
        ${groupId != null ? 'WHERE p.group_id = ?' : ''}
        GROUP BY p.id
        ORDER BY p.created_at DESC
      `;
      this.db.all(sql, groupId != null ? [groupId] : [], (err, rows) => err ? reject(err) : resolve(rows));
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

  addProjectExpense(projectId, expense, groupId = null) {
    return new Promise((resolve, reject) => {
      // Guard: the parent project must belong to the caller's household.
      this.db.get('SELECT group_id FROM budget_projects WHERE id = ?', [projectId], (gErr, proj) => {
        if (gErr) return reject(gErr);
        if (!proj) return reject(new Error('Project not found'));
        if (groupId != null && proj.group_id != null && proj.group_id !== groupId) {
          return reject(new Error('Forbidden'));
        }
        this.db.run(
          'INSERT INTO project_expenses (project_id, description, amount, category, notes, group_id) VALUES (?, ?, ?, ?, ?, ?)',
          [projectId, expense.description, expense.amount, expense.category || 'General', expense.notes || null, proj.group_id || groupId || null],
          function(err) {
            if (err) reject(err);
            else resolve({ id: this.lastID, ...expense });
          }
        );
      });
    });
  }

  getProjectExpenses(projectId, groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId != null
        ? `SELECT pe.* FROM project_expenses pe
           JOIN budget_projects p ON p.id = pe.project_id
           WHERE pe.project_id = ? AND p.group_id = ? ORDER BY pe.created_at DESC`
        : 'SELECT * FROM project_expenses WHERE project_id = ? ORDER BY created_at DESC';
      this.db.all(sql, groupId != null ? [projectId, groupId] : [projectId],
        (err, rows) => err ? reject(err) : resolve(rows));
    });
  }

  deleteProjectExpense(id, projectId = null) {
    return new Promise((resolve, reject) => {
      const sql = projectId != null
        ? 'DELETE FROM project_expenses WHERE id = ? AND project_id = ?'
        : 'DELETE FROM project_expenses WHERE id = ?';
      this.db.run(sql, projectId != null ? [id, projectId] : [id], (err) => {
        if (err) reject(err);
        else resolve({ id, deleted: true });
      });
    });
  }

  // ============================================
  // Recurring payments (rent, mortgage, subscriptions, ...) — track-only
  // ============================================

  // Normalize any cadence to a comparable monthly figure.
  static monthlyEquivalent(amount, frequency) {
    const a = Number(amount) || 0;
    switch (frequency) {
      case 'weekly': return a * 52 / 12;
      case 'yearly': return a / 12;
      default: return a; // monthly
    }
  }

  getRecurringPayments(groupId = null) {
    return new Promise((resolve, reject) => {
      const sql = groupId != null
        ? 'SELECT * FROM recurring_payments WHERE group_id = ? AND active = 1 ORDER BY due_day IS NULL, due_day, name'
        : 'SELECT * FROM recurring_payments WHERE active = 1 ORDER BY due_day IS NULL, due_day, name';
      this.db.all(sql, groupId != null ? [groupId] : [], (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  addRecurringPayment(p) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO recurring_payments (name, amount, category, frequency, due_day, due_date, autopay, icon, notes, created_by, group_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [p.name, p.amount, p.category || null, p.frequency || 'monthly', p.due_day || null, p.due_date || null,
         p.autopay ? 1 : 0, p.icon || null, p.notes || null, p.created_by || null, p.group_id || null],
        function (err) { err ? reject(err) : resolve({ id: this.lastID, ...p }); }
      );
    });
  }

  updateRecurringPayment(id, updates) {
    const ALLOWED = new Set(['name', 'amount', 'category', 'frequency', 'due_day', 'due_date', 'autopay', 'icon', 'notes', 'active']);
    return new Promise((resolve, reject) => {
      const fields = [], params = [];
      for (const [k, v] of Object.entries(updates)) {
        if (!ALLOWED.has(k)) continue;
        fields.push(`${k} = ?`);
        params.push(k === 'autopay' || k === 'active' ? (v ? 1 : 0) : v);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE recurring_payments SET ${fields.join(', ')} WHERE id = ?`, params, (err) => err ? reject(err) : resolve({ id, ...updates }));
    });
  }

  deleteRecurringPayment(id) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM recurring_payments WHERE id = ?', [id], (err) => err ? reject(err) : resolve({ id, deleted: true }));
    });
  }

  // ============================================
  // Notes (private by default; owner can share to household or a group)
  // ============================================

  // Notes the user owns OR that have been shared to a group they belong to.
  getNotes(userId) {
    return new Promise((resolve, reject) => {
      const uid = safeUid(userId);
      this.db.all(
        `SELECT n.*, u.name AS author_name, g.name AS shared_group_name
         FROM notes n
         LEFT JOIN users u ON u.id = n.user_id
         LEFT JOIN groups g ON g.id = n.group_id
         WHERE n.user_id = ?
            OR (n.shared_scope != 'private' AND n.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?))
         ORDER BY n.pinned DESC, datetime(n.updated_at) DESC`,
        [uid, uid], (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  addNote(note) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO notes (title, body, color, pinned, user_id, shared_scope, group_id, can_collaborate)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [note.title || null, note.body || null, note.color || null, note.pinned ? 1 : 0,
         note.user_id || null, note.shared_scope || 'private', note.group_id || null, note.can_collaborate ? 1 : 0],
        function (err) { err ? reject(err) : resolve({ id: this.lastID, ...note }); }
      );
    });
  }

  getNoteById(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM notes WHERE id = ?', [id], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  // Owner update — full control incl. sharing + collaboration settings.
  updateNote(id, updates, userId) {
    const ALLOWED = new Set(['title', 'body', 'color', 'pinned', 'shared_scope', 'group_id', 'can_collaborate']);
    return new Promise((resolve, reject) => {
      const fields = [], params = [];
      for (const [k, v] of Object.entries(updates)) {
        if (!ALLOWED.has(k)) continue;
        fields.push(`${k} = ?`);
        params.push((k === 'pinned' || k === 'can_collaborate') ? (v ? 1 : 0) : v);
      }
      fields.push("updated_at = CURRENT_TIMESTAMP");
      params.push(id, parseInt(userId));
      this.db.run(`UPDATE notes SET ${fields.join(', ')} WHERE id = ? AND user_id = ?`, params,
        function (err) { err ? reject(err) : resolve({ changed: this.changes }); });
    });
  }

  // Collaborator update — CONTENT ONLY, and only when the note is shared with a
  // group the user belongs to AND collaboration is enabled. Cannot touch
  // sharing/ownership. Enforced atomically in the WHERE clause.
  updateNoteAsCollaborator(id, updates, userId) {
    const ALLOWED = new Set(['title', 'body', 'color']);
    return new Promise((resolve, reject) => {
      const fields = [], params = [];
      for (const [k, v] of Object.entries(updates)) {
        if (!ALLOWED.has(k)) continue;
        fields.push(`${k} = ?`);
        params.push(v);
      }
      if (!fields.length) return resolve({ changed: 0 });
      fields.push("updated_at = CURRENT_TIMESTAMP");
      const uid = safeUid(userId);
      params.push(id, uid);
      this.db.run(
        `UPDATE notes SET ${fields.join(', ')}
         WHERE id = ? AND can_collaborate = 1 AND shared_scope != 'private'
           AND group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)`,
        params, function (err) { err ? reject(err) : resolve({ changed: this.changes }); });
    });
  }

  deleteNote(id, userId) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM notes WHERE id = ? AND user_id = ?', [id, parseInt(userId)],
        function (err) { err ? reject(err) : resolve({ changed: this.changes }); });
    });
  }

  // ============================================
  // Spending statistics / trends (for the Budget > Stats view)
  // ============================================

  // One round-trip-ish aggregate: monthly totals, current-month category
  // breakdown, recurring fixed total, and a few derived figures. All scoped to
  // the caller's household. itinerary receipts (trip expenses) are excluded.
  getSpendingStats(groupId, months = 6) {
    return new Promise((resolve, reject) => {
      const all = (sql, p = []) => new Promise((r, j) => this.db.all(sql, p, (e, x) => e ? j(e) : r(x || [])));
      const gFilter = groupId != null ? 'AND group_id = ?' : '';
      const gp = groupId != null ? [groupId] : [];
      (async () => {
        const n = Math.max(1, Math.min(24, parseInt(months) || 6));
        // Monthly totals for the trailing window (oldest -> newest).
        const monthly = await all(
          `SELECT strftime('%Y-%m', date) AS ym, COALESCE(SUM(amount), 0) AS total
           FROM receipts WHERE itinerary_id IS NULL ${gFilter}
             AND date >= date('now', 'start of month', '-${n - 1} months')
           GROUP BY ym ORDER BY ym`, gp);
        // Current-month category breakdown (largest first).
        const thisMonth = new Date().toLocaleDateString('en-CA').slice(0, 7);
        const byCategory = await all(
          `SELECT COALESCE(category, 'Other') AS category, COALESCE(SUM(amount), 0) AS spent
           FROM receipts WHERE itinerary_id IS NULL AND strftime('%Y-%m', date) = ? ${gFilter}
           GROUP BY category ORDER BY spent DESC`, [thisMonth, ...gp]);
        // Recurring fixed monthly commitment.
        const recurring = await all(
          `SELECT amount, frequency FROM recurring_payments WHERE active = 1 ${gFilter}`, gp);
        const recurringMonthly = recurring.reduce((sum, r) => sum + FamilyDB.monthlyEquivalent(r.amount, r.frequency), 0);
        resolve({ thisMonth, monthly, byCategory, recurringMonthly });
      })().catch(reject);
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

  updateUserPassword(userId, passwordHash) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE users SET password_hash = ? WHERE id = ?', [passwordHash, userId],
        function(err) { err ? reject(err) : resolve({ changed: this.changes }); });
    });
  }

  // ── Email + two-factor ──────────────────────────────────────────────────
  // Set (or change) a user's email. Always resets verification — the new
  // address must be proven again via a code.
  setUserEmail(userId, email) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE users SET email = ?, email_verified = 0 WHERE id = ?', [email, userId],
        (err) => err ? reject(err) : resolve({ ok: true }));
    });
  }

  markEmailVerifiedAndEnable(userId) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE users SET email_verified = 1, two_factor_enabled = 1 WHERE id = ?', [userId],
        (err) => err ? reject(err) : resolve({ ok: true }));
    });
  }

  createLoginChallenge({ token, userId, status, codeHash = null, expiresAt }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO login_challenges (token, user_id, code_hash, status, expires_at) VALUES (?, ?, ?, ?, ?)',
        [token, userId, codeHash, status, expiresAt],
        function(err) { err ? reject(err) : resolve({ id: this.lastID }); }
      );
    });
  }

  getLoginChallenge(token) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM login_challenges WHERE token = ?', [token],
        (err, row) => err ? reject(err) : resolve(row || null));
    });
  }

  updateLoginChallengeCode(token, { codeHash, status, expiresAt }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE login_challenges SET code_hash = ?, status = ?, expires_at = ?, attempts = 0 WHERE token = ?',
        [codeHash, status, expiresAt, token],
        (err) => err ? reject(err) : resolve({ ok: true }));
    });
  }

  incrementLoginChallengeAttempts(token) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE login_challenges SET attempts = attempts + 1 WHERE token = ?', [token],
        (err) => err ? reject(err) : resolve({ ok: true }));
    });
  }

  consumeLoginChallenge(token) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE login_challenges SET consumed = 1 WHERE token = ?', [token],
        (err) => err ? reject(err) : resolve({ ok: true }));
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
      this.db.get('SELECT id, username, name, email, phone, avatar, work_address, work_lat, work_lng, created_at FROM users WHERE id = ?', [id], (err, row) => {
        if (err) reject(err);
        else resolve(row || null);
      });
    });
  }

  // ============================================
  // Groups
  // ============================================

  // Allowed group kinds. 'household' = sensitive, one-or-more per user; the rest
  // are cross-household "clans". Anything else is rejected so a client can't mint
  // an unknown type to dodge scoping.
  static get GROUP_TYPES() { return ['household', 'family', 'tribe', 'friends', 'group']; }

  // Unguessable, collision-checked invite code (replaces the old Math.random one,
  // which was predictable and could be brute-forced to join a household).
  _generateInviteCode() {
    return new Promise((resolve, reject) => {
      const tryOnce = (attempt) => {
        if (attempt > 10) return reject(new Error('Could not generate a unique invite code'));
        const code = crypto.randomBytes(8).toString('base64url').slice(0, 10).toUpperCase();
        this.db.get('SELECT 1 FROM groups WHERE invite_code = ?', [code], (err, row) => {
          if (err) return reject(err);
          if (row) return tryOnce(attempt + 1); // collision — retry (bounded)
          resolve(code);
        });
      };
      tryOnce(0);
    });
  }

  async createGroup(group) {
    const groupType = FamilyDB.GROUP_TYPES.includes(group.group_type) ? group.group_type : 'family';
    const inviteCode = await this._generateInviteCode();
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO groups (name, group_type, description, invite_code, created_by) VALUES (?, ?, ?, ?, ?)',
        [group.name, groupType, group.description || null, inviteCode, group.created_by],
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

  // Group profile image (base64), mirroring the user-avatar storage.
  updateGroupAvatar(groupId, image) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE groups SET profile_image = ? WHERE id = ?', [image, groupId],
        (err) => err ? reject(err) : resolve({ ok: true }));
    });
  }

  getGroupAvatar(groupId) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT profile_image FROM groups WHERE id = ?', [groupId],
        (err, row) => err ? reject(err) : resolve(row?.profile_image || null));
    });
  }

  isGroupMember(groupId, userId) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ? LIMIT 1',
        [groupId, userId], (err, row) => err ? reject(err) : resolve(!!row));
    });
  }

  async addGroupMember(groupId, { user_id, contact_id, role, added_by }) {
    // Idempotent for app users: a retried add/join returns the existing row
    // instead of inserting a duplicate membership.
    if (user_id) {
      const existing = await new Promise((resolve, reject) => {
        this.db.get('SELECT id FROM group_members WHERE group_id = ? AND user_id = ? LIMIT 1',
          [groupId, user_id], (err, row) => err ? reject(err) : resolve(row));
      });
      if (existing) return { id: existing.id, existed: true };
    }
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

  // Household-scoped tables whose group_id must follow a merge. budget_categories
  // is special-cased (UNIQUE(name, group_id)) so duplicate names collapse.
  static get HOUSEHOLD_TABLES() {
    return ['tasks', 'appointments', 'decisions', 'rivalries', 'groceries', 'receipts',
      'budget_categories', 'budget_projects', 'project_expenses', 'pantry', 'trips',
      'gift_people', 'gift_ideas', 'special_events', 'family_addresses', 'feed_posts',
      'itineraries', 'itinerary_stays', 'subscriptions', 'concierge_memory', 'concierge_nudges',
      'concierge_conversations', 'recurring_payments', 'notes', 'event_attachments',
      'synced_calendar_events', 'milestones'];
  }

  // Merge one household into another: re-point all household-scoped data and
  // members from sourceId to targetId, then delete the (now empty) source group.
  // Both must be group_type='household'. Idempotent-ish and transactional.
  mergeHousehold(sourceId, targetId) {
    const src = parseInt(sourceId), tgt = parseInt(targetId);
    return new Promise((resolve, reject) => {
      if (!src || !tgt || src === tgt) return reject(new Error('Invalid source/target household'));
      const get = (sql, p = []) => new Promise((r, j) => this.db.get(sql, p, (e, x) => e ? j(e) : r(x)));
      const run = (sql, p = []) => new Promise((r, j) => this.db.run(sql, p, function (e) { e ? j(e) : r(this); }));
      (async () => {
        const a = await get(`SELECT id, group_type FROM groups WHERE id = ?`, [src]);
        const b = await get(`SELECT id, group_type FROM groups WHERE id = ?`, [tgt]);
        if (!a || !b) throw new Error('Household not found');
        if (a.group_type !== 'household' || b.group_type !== 'household') {
          throw new Error('Both groups must be households to merge');
        }
        await run('BEGIN');
        try {
          for (const t of FamilyDB.HOUSEHOLD_TABLES) {
            // Skip tables that don't exist / lack group_id in this DB.
            const cols = await new Promise((r) => this.db.all(`PRAGMA table_info(${t})`, (e, rows) => r(e ? [] : rows)));
            if (!cols.some(c => c.name === 'group_id')) continue;
            // OR IGNORE lets UNIQUE(name, group_id) duplicates fall through; the
            // leftover source rows are then removed (target already has them).
            await run(`UPDATE OR IGNORE ${t} SET group_id = ? WHERE group_id = ?`, [tgt, src]);
            await run(`DELETE FROM ${t} WHERE group_id = ?`, [src]);
          }
          // Move members that aren't already in the target, then drop source rows.
          await run(`UPDATE group_members SET group_id = ? WHERE group_id = ? AND user_id IS NOT NULL
            AND user_id NOT IN (SELECT user_id FROM group_members WHERE group_id = ? AND user_id IS NOT NULL)`,
            [tgt, src, tgt]);
          await run(`UPDATE group_members SET group_id = ? WHERE group_id = ? AND contact_id IS NOT NULL
            AND contact_id NOT IN (SELECT contact_id FROM group_members WHERE group_id = ? AND contact_id IS NOT NULL)`,
            [tgt, src, tgt]);
          await run(`DELETE FROM group_members WHERE group_id = ?`, [src]);
          await run(`DELETE FROM groups WHERE id = ?`, [src]);
          await run('COMMIT');
          resolve({ merged: true, source: src, target: tgt });
        } catch (e) {
          await run('ROLLBACK').catch(() => {});
          reject(e);
        }
      })().catch(reject);
    });
  }

  // Tables that carry a per-row owner NAME we can map back to a household.
  // The one durable ownership signal that survives the legacy backfill.
  static get REATTRIBUTION_OWNED() {
    return [
      { table: 'receipts', col: 'added_by' },
      { table: 'pantry', col: 'added_by' },
      { table: 'trips', col: 'traveler' },
      { table: 'budget_projects', col: 'created_by' },
      { table: 'decisions', col: 'creator_name' },
      { table: 'rivalries', col: 'initiator_name' },
      { table: 'family_addresses', col: 'created_by' },
      { table: 'appointments', col: 'person_tags', tags: true, fallback: 'with_person' },
    ];
  }

  // Core re-attribution: move household-scoped rows to the household their
  // owner-name resolves to. Conservative — a row is moved ONLY when its owner
  // resolves UNAMBIGUOUSLY to a single household different from its current one;
  // unresolved/ambiguous owners are left untouched (never set to NULL). Shared
  // by the CLI script and the one-time startup pass so there is one source of
  // truth. Returns { moves, applied }.
  reattributeHouseholds({ apply = false, onLog = () => {} } = {}) {
    return new Promise((resolve, reject) => {
      const all = (sql, p = []) => new Promise((r, j) => this.db.all(sql, p, (e, x) => e ? j(e) : r(x)));
      const run = (sql, p = []) => new Promise((r, j) => this.db.run(sql, p, function (e) { e ? j(e) : r(this); }));
      const cache = new Map();
      const hhForName = async (raw) => {
        if (!raw) return null;
        const key = String(raw).trim().toLowerCase();
        if (!key) return null;
        if (cache.has(key)) return cache.get(key);
        const rows = await all(`SELECT DISTINCT g.id FROM users u
          JOIN group_members gm ON gm.user_id = u.id
          JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
          WHERE LOWER(u.name) = ? OR LOWER(u.username) = ?`, [key, key]);
        const hh = rows.length === 1 ? rows[0].id : null; // >1 household = ambiguous, leave it
        cache.set(key, hh);
        return hh;
      };
      const hhForTags = async (val, fb) => {
        let parts = [];
        const v = (val || '').trim();
        if (v.startsWith('[')) { try { parts = JSON.parse(v); } catch { parts = []; } }
        else if (v) { parts = v.split(','); }
        parts = parts.map(s => String(s).trim()).filter(Boolean);
        if (!parts.length && fb) parts = [String(fb).trim()].filter(Boolean);
        if (!parts.length) return null;
        const set = new Set();
        for (const p of parts) { const hh = await hhForName(p); if (!hh) return null; set.add(hh); }
        return set.size === 1 ? [...set][0] : null;
      };
      (async () => {
        const moves = [];
        for (const cfg of FamilyDB.REATTRIBUTION_OWNED) {
          const cols = await all(`PRAGMA table_info(${cfg.table})`);
          if (!cols.some(c => c.name === 'group_id')) continue;
          const extra = cfg.fallback ? `, ${cfg.fallback}` : '';
          const rows = await all(`SELECT id, group_id, ${cfg.col}${extra} FROM ${cfg.table}`);
          for (const row of rows) {
            const target = cfg.tags
              ? await hhForTags(row[cfg.col], cfg.fallback ? row[cfg.fallback] : null)
              : await hhForName(row[cfg.col]);
            if (!target || target === row.group_id) continue;
            moves.push({ table: cfg.table, id: row.id, from: row.group_id, to: target, by: row[cfg.col] });
          }
        }
        if (apply && moves.length) {
          await run('BEGIN');
          try {
            for (const m of moves) await run(`UPDATE ${m.table} SET group_id = ? WHERE id = ?`, [m.to, m.id]);
            await run('COMMIT');
          } catch (e) { await run('ROLLBACK').catch(() => {}); throw e; }
        }
        onLog(`household re-attribution: ${moves.length} ${apply ? 'applied' : 'proposed'}`);
        resolve({ moves, applied: apply ? moves.length : 0 });
      })().catch(reject);
    });
  }

  // One-time, self-guarded startup pass. Runs reattributeHouseholds({apply})
  // exactly once (tracked via app_meta) so a deploy auto-corrects any legacy
  // mis-attribution and never repeats. No-op on a clean DB.
  reattributeHouseholdsOnce() {
    return new Promise((resolve, reject) => {
      const get = (sql, p = []) => new Promise((r, j) => this.db.get(sql, p, (e, x) => e ? j(e) : r(x)));
      const run = (sql, p = []) => new Promise((r, j) => this.db.run(sql, p, function (e) { e ? j(e) : r(this); }));
      (async () => {
        await run(`CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)`);
        const done = await get(`SELECT value FROM app_meta WHERE key = 'reattribution_v1'`);
        if (done) return resolve({ skipped: true });
        const res = await this.reattributeHouseholds({ apply: true, onLog: (m) => console.log('[startup]', m) });
        await run(`INSERT OR REPLACE INTO app_meta (key, value) VALUES ('reattribution_v1', ?)`, [String(res.applied)]);
        console.log(`[startup] one-time household re-attribution complete (${res.applied} rows moved)`);
        resolve(res);
      })().catch(reject);
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

  // Marketing waitlist (public, not household data).
  // Resolves { created: bool, total: int } — created=false when already present.
  addWaitlistEntry({ email, source, referrer, user_agent }) {
    return new Promise((resolve, reject) => {
      const db = this.db;
      db.run(
        'INSERT OR IGNORE INTO waitlist (email, source, referrer, user_agent) VALUES (?, ?, ?, ?)',
        [email, source || null, referrer || null, user_agent || null],
        function (err) {
          if (err) return reject(err);
          const created = this.changes > 0;
          db.get('SELECT COUNT(*) AS n FROM waitlist', [], (e, row) => {
            if (e) return reject(e);
            resolve({ created, total: row ? row.n : 0 });
          });
        }
      );
    });
  }

  markWaitlistWelcomed(email) {
    return new Promise((resolve) => {
      this.db.run('UPDATE waitlist SET welcomed = 1 WHERE email = ?', [email], () => resolve());
    });
  }

  updateContact(id, updates) {
    const ALLOWED = new Set(['name', 'relationship', 'phone', 'email', 'birthday', 'avatar_initial', 'notes']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
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
      const uid = userId ? safeUid(userId) : null;
      // Subquery for user's group IDs
      const myGroups = uid
        ? `SELECT group_id FROM group_members WHERE user_id = ${uid}`
        : `SELECT id FROM groups`;
      const sql = `
        SELECT 'decision' as feed_type, d.id as ref_id, d.title, NULL as body,
          d.creator_name as author, d.status, d.created_at as created_at,
          0 as reaction_count, 0 as comment_count, NULL as author_id, d.group_id, g.name as group_name, 0 as has_photo
        FROM decisions d LEFT JOIN groups g ON g.id = d.group_id
        WHERE d.status = 'active'${uid ? `
          AND d.group_id IN (${myGroups})` : ''}
        UNION ALL
        SELECT 'event' as feed_type, a.id as ref_id, a.title, a.location as body,
          COALESCE(au.name, au.username, 'Family') as author, 'upcoming' as status,
          a.created_at,
          0 as reaction_count, 0 as comment_count, a.created_by as author_id, a.group_id, g.name as group_name, 0 as has_photo
        FROM appointments a
        LEFT JOIN groups g ON g.id = a.group_id
        LEFT JOIN users au ON au.id = a.created_by
        WHERE a.appointment_date <= date('now', '+7 days', 'localtime')
          AND (
            a.appointment_date > date('now', 'localtime')
            OR (
              a.appointment_date = date('now', 'localtime')
              AND (
                a.appointment_time IS NULL
                OR a.appointment_time = ''
                OR time(a.appointment_time) >= time('now', 'localtime')
              )
            )
          )${uid ? `
          AND a.group_id IN (${myGroups})` : ''}
        UNION ALL
        SELECT 'coverage' as feed_type, cr.id as ref_id, cr.reason as title, cr.note as body,
          COALESCE(u.name, u.username, 'Family') as author, cr.status,
          cr.created_at,
          0 as reaction_count, 0 as comment_count, cr.requester_id as author_id, NULL as group_id, NULL as group_name, 0 as has_photo
        FROM coverage_requests cr
        LEFT JOIN users u ON u.id = cr.requester_id
        WHERE cr.status IN ('pending', 'approved')${uid ? `
          AND cr.requester_id IN (
            SELECT gm2.user_id FROM group_members gm2
            JOIN groups g2 ON g2.id = gm2.group_id AND g2.group_type = 'household'
            WHERE gm2.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${uid})
          )` : ''}
        UNION ALL
        SELECT 'rivalry' as feed_type, r.id as ref_id, r.title, r.challenge_type as body,
          r.initiator_name as author, r.status,
          r.created_at,
          0 as reaction_count, 0 as comment_count, NULL as author_id, r.group_id, g.name as group_name, 0 as has_photo
        FROM rivalries r
        LEFT JOIN groups g ON g.id = r.group_id
        WHERE r.status = 'active' AND r.created_at >= datetime('now', '-14 days')${uid ? `
          AND r.group_id IN (${myGroups})` : ''}
        UNION ALL
        SELECT 'post' as feed_type, fp.id as ref_id, fp.title, fp.body,
          COALESCE(u.name, u.username, 'Family') as author, fp.post_type as status,
          fp.created_at,
          (SELECT COUNT(*) FROM feed_reactions WHERE post_id = fp.id) as reaction_count,
          (SELECT COUNT(*) FROM feed_comments WHERE post_id = fp.id) as comment_count,
          fp.author_id, fp.group_id, g.name as group_name,
          CASE WHEN fp.photo_url IS NOT NULL AND fp.photo_url != '' THEN 1 ELSE 0 END as has_photo
        FROM feed_posts fp
        LEFT JOIN users u ON u.id = fp.author_id
        LEFT JOIN groups g ON g.id = fp.group_id
        WHERE fp.group_id IN (${myGroups})
          AND fp.post_type != 'text'
          AND (
            (fp.post_type NOT IN ('decision', 'poll') AND (fp.reference_type IS NULL OR fp.reference_type != 'decision'))
            OR EXISTS (SELECT 1 FROM decisions d WHERE d.id = fp.reference_id AND d.status = 'active')
          )
        UNION ALL
        SELECT 'comment' as feed_type, fc.post_id as ref_id,
          (SELECT title FROM feed_posts WHERE id = fc.post_id) as title,
          fc.text as body,
          u.name as author, 'comment' as status,
          fc.created_at,
          0 as reaction_count, 0 as comment_count, fc.user_id as author_id,
          fp2.group_id, g2.name as group_name, 0 as has_photo
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
          fp3.group_id, g3.name as group_name, 0 as has_photo
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
      // Scope to the user's HOUSEHOLD(s) only (tasks/appointments are household
      // data) — never their clans, and no "OR group_id IS NULL" (which would leak
      // every untagged record from other households into this user's summary).
      const groupFilter = userId
        ? `AND group_id IN (SELECT gm.group_id FROM group_members gm
             JOIN groups g ON g.id = gm.group_id
             WHERE gm.user_id = ${safeUid(userId)} AND g.group_type = 'household')`
        : '';
      // Lists have no group_id — tenancy is derived from created_by, so the
      // pinned list must be scoped to the household's members (mirrors the
      // scoping used by POST /api/lists/:id/pin), never the global first pin.
      const pinnedListFilter = userId
        ? `AND (created_by = ${safeUid(userId)} OR created_by IN (
             SELECT gm2.user_id FROM group_members gm2
             JOIN groups g ON g.id = gm2.group_id AND g.group_type = 'household'
             WHERE gm2.group_id IN (SELECT group_id FROM group_members WHERE user_id = ${safeUid(userId)})))`
        : '';
      const sql = `
        SELECT
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' AND date(due_date) = date('now') ${groupFilter}) as tasks_today,
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' ${groupFilter}) as active_tasks,
          (SELECT COUNT(*) FROM appointments WHERE date(appointment_date) = date('now') ${groupFilter}) as appointments_today,
          (SELECT COUNT(*) FROM list_items WHERE is_done = 0 AND list_id IN (
            SELECT id FROM lists WHERE pinned = 1 ${pinnedListFilter} LIMIT 1
          )) as groceries_needed,
          (SELECT COUNT(*) FROM tasks WHERE status = 'active' AND due_date < date('now') ${groupFilter}) as overdue_tasks,
          (SELECT name FROM lists WHERE pinned = 1 ${pinnedListFilter} LIMIT 1) as pinned_list_name
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

  // Grocery auto-categorizer — keyword-based
  static categorizeGroceryItem(title) {
    const t = title.toLowerCase().trim();
    const categories = {
      'Produce': ['apple','banana','orange','lemon','lime','grape','strawberr','blueberr','raspberr','blackberr','peach','pear','plum','mango','pineapple','melon','watermelon','avocado','tomato','potato','onion','garlic','ginger','carrot','celery','broccoli','cauliflower','spinach','lettuce','kale','arugula','cucumber','pepper','zucchini','squash','corn','mushroom','asparagus','green bean','snap pea','radish','beet','sweet potato','cabbage','brussels','eggplant','artichoke','leek','shallot','cilantro','parsley','basil','mint','dill','rosemary','thyme','jalapen','serrano','habanero','chive','scallion','green onion','fruit','vegetable','produce','salad','herb','berry','citrus','clementine','tangerine','grapefruit','kiwi','fig','pomegranate','cranberr','cherry','apricot','nectarine','coconut','plantain','yam','turnip','parsnip','rutabaga','bok choy','fennel','okra','watercress','endive','radicchio'],
      'Dairy': ['milk','cream','cheese','yogurt','yoghurt','butter','egg','eggs','sour cream','cottage','ricotta','mozzarella','cheddar','parmesan','gouda','brie','feta','cream cheese','whipping cream','half and half','half & half','buttermilk','kefir','ghee','dairy','margarine','oat milk','almond milk','soy milk','coconut milk'],
      'Meat & Seafood': ['chicken','beef','pork','steak','ground','turkey','lamb','sausage','bacon','ham','salami','pepperoni','prosciutto','fish','salmon','tuna','shrimp','prawn','crab','lobster','scallop','clam','mussel','oyster','cod','tilapia','halibut','mahi','trout','sardine','anchov','meat','seafood','hot dog','wiener','brisket','ribs','roast','chop','filet','fillet','deli','veal','duck','bison','venison','chorizo','kielbasa','bratwurst','meatball'],
      'Bakery': ['bread','bagel','croissant','muffin','roll','bun','tortilla','pita','naan','wrap','cake','pie','cookie','pastry','donut','doughnut','danish','scone','biscuit','loaf','sourdough','rye','ciabatta','focaccia','baguette','english muffin','hamburger bun','hot dog bun','crouton','breadcrumb','flatbread'],
      'Frozen': ['frozen','ice cream','pizza','fries','waffle','popsicle','gelato','sorbet','frozen dinner','tv dinner','frozen fruit','frozen vegetable','frozen meal','fish stick','corn dog','frozen pie'],
      'Pantry': ['rice','pasta','noodle','flour','sugar','salt','pepper','oil','olive oil','vinegar','soy sauce','ketchup','mustard','mayo','mayonnaise','relish','hot sauce','bbq sauce','barbecue sauce','salsa','peanut butter','almond butter','jam','jelly','honey','maple syrup','cereal','oatmeal','granola','cracker','chip','pretzel','popcorn','nut','almond','cashew','walnut','pecan','pistachio','peanut','can','canned','bean','lentil','chickpea','broth','stock','soup','sauce','dressing','spice','seasoning','cinnamon','cumin','paprika','oregano','turmeric','curry','chili powder','nutmeg','vanilla','baking soda','baking powder','yeast','cornstarch','cocoa','chocolate','panko','breadcrumb','quinoa','couscous','barley','taco','tortilla chip','salsa','hummus','tahini','coconut oil','sesame','teriyaki','worcestershire','sriracha','ranch','italian','balsamic','dijon'],
      'Beverages': ['water','juice','soda','pop','cola','coffee','tea','beer','wine','kombucha','lemonade','gatorade','energy drink','sparkling','seltzer','tonic','liquor','vodka','rum','whiskey','bourbon','gin','tequila','champagne','prosecco','cider','smoothie','protein shake','creamer','espresso','matcha','drink','beverage'],
      'Snacks': ['chip','chips','cracker','pretzel','popcorn','trail mix','granola bar','protein bar','candy','chocolate bar','gummy','dried fruit','jerky','cookie','fruit snack','rice cake','cheese puff','goldfish','animal cracker','snack'],
      'Deli': ['deli','lunch meat','roast beef','turkey breast','pastrami','corned beef','hummus','olive','pickle','coleslaw','potato salad','rotisserie','prepared','sub','hoagie'],
      'Household': ['paper towel','toilet paper','tissue','napkin','trash bag','garbage bag','aluminum foil','plastic wrap','saran','parchment','wax paper','ziploc','sandwich bag','sponge','dish soap','detergent','laundry','fabric softener','dryer sheet','bleach','cleaner','disinfectant','wipe','mop','broom','light bulb','battery','candle','air freshener','soap'],
      'Personal Care': ['shampoo','conditioner','body wash','lotion','deodorant','toothpaste','toothbrush','floss','mouthwash','razor','shaving','sunscreen','bandaid','band-aid','medicine','vitamin','supplement','tylenol','advil','ibuprofen','allergy','antacid','cotton','q-tip','nail','lip balm','hand sanitizer'],
      'Baby & Kids': ['diaper','wipe','formula','baby food','sippy','pacifier','baby','kids','children','juice box'],
      'Pet': ['dog food','cat food','pet food','kitty litter','cat litter','dog treat','cat treat','pet','chew toy','flea','tick']
    };
    for (const [category, keywords] of Object.entries(categories)) {
      for (const kw of keywords) {
        if (t.includes(kw)) return category;
      }
    }
    return 'Other';
  }

  createList(list) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO lists (name, icon, color, list_type, created_by) VALUES (?, ?, ?, ?, ?)',
        [list.name, list.icon || 'list.bullet', list.color || null, list.list_type || 'standard', list.created_by || null],
        function(err) {
          if (err) reject(err);
          else resolve({ id: this.lastID });
        }
      );
    });
  }

  getLists(userId) {
    return new Promise((resolve, reject) => {
      const sql = userId
        ? `SELECT l.*,
            (SELECT COUNT(*) FROM list_items WHERE list_id = l.id AND is_done = 0) as active_count,
            (SELECT COUNT(*) FROM list_items WHERE list_id = l.id) as total_count
          FROM lists l
          WHERE l.created_by = ? OR l.created_by IN (
            SELECT gm2.user_id FROM group_members gm2
            JOIN groups g ON g.id = gm2.group_id AND g.group_type = 'household'
            WHERE gm2.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
          )
          ORDER BY l.pinned DESC, l.created_at ASC`
        : `SELECT l.*,
            (SELECT COUNT(*) FROM list_items WHERE list_id = l.id AND is_done = 0) as active_count,
            (SELECT COUNT(*) FROM list_items WHERE list_id = l.id) as total_count
          FROM lists l ORDER BY l.created_at ASC`;
      this.db.all(sql, userId ? [userId, userId] : [], (err, rows) => err ? reject(err) : resolve(rows));
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
    const ALLOWED = new Set(['name', 'icon', 'color', 'pinned', 'list_type']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
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
        'SELECT * FROM list_items WHERE list_id = ? ORDER BY is_done ASC, category ASC, sort_order ASC, id DESC',
        [listId], (err, rows) => err ? reject(err) : resolve(rows)
      );
    });
  }

  addListItem(item) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO list_items (list_id, title, added_by, category) VALUES (?, ?, ?, ?)',
        [item.list_id, item.title, item.added_by || null, item.category || null],
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

  updateListItem(id, updates) {
    const ALLOWED = new Set(['title', 'is_done', 'sort_order', 'category', 'completed_at']);
    return new Promise((resolve, reject) => {
      const fields = [];
      const params = [];
      for (const [key, value] of Object.entries(updates)) {
        if (!ALLOWED.has(key)) continue;
        fields.push(`${key} = ?`);
        params.push(value);
      }
      if (!fields.length) return resolve({ id });
      params.push(id);
      this.db.run(`UPDATE list_items SET ${fields.join(', ')} WHERE id = ?`, params, (err) => {
        if (err) reject(err);
        else resolve({ id, ...updates });
      });
    });
  }

  reorderListItems(listId, orderedIds) {
    return new Promise((resolve, reject) => {
      // Scope every update to the owning list so a caller can't reorder (touch)
      // items belonging to another list / household by passing foreign ids.
      const stmt = this.db.prepare('UPDATE list_items SET sort_order = ? WHERE id = ? AND list_id = ?');
      for (let i = 0; i < orderedIds.length; i++) {
        stmt.run(i, orderedIds[i], listId);
      }
      stmt.finalize((err) => {
        if (err) reject(err);
        else resolve({ success: true });
      });
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
      this.db.get(`
        SELECT cr.*, u.name as requester_name
        FROM coverage_requests cr
        JOIN users u ON u.id = cr.requester_id
        WHERE cr.id = ?
      `, [id], (err, row) => err ? reject(err) : resolve(row));
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
      const db = this.db;
      db.serialize(() => {
        db.run('BEGIN');
        db.run(
          `INSERT INTO coverage_approvals (request_id, recipient_id, window_id, approved_date, approved_start, approved_end, helper_note)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [approval.request_id, approval.recipient_id, approval.window_id, approval.approved_date, approval.approved_start, approval.approved_end, approval.helper_note || null],
          function(err) {
            if (err) { db.run('ROLLBACK'); return reject(err); }
            const approvalId = this.lastID;
            db.run('UPDATE coverage_recipients SET status = ? WHERE id = ?', ['approved', approval.recipient_id]);
            db.run('UPDATE coverage_requests SET status = ? WHERE id = ?', ['approved', approval.request_id]);
            db.run('COMMIT', (cErr) => cErr ? reject(cErr) : resolve({ id: approvalId }));
          }
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

  getUserIdByContactId(contactId) {
    return new Promise((resolve, reject) => {
      this.db.get(`
        SELECT u.id FROM users u
        JOIN contacts c ON LOWER(u.name) = LOWER(c.name)
        WHERE c.id = ? LIMIT 1
      `, [contactId], (err, row) => err ? reject(err) : resolve(row?.id || null));
    });
  }

  getIncomingCoverageRequests(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT cr.id, cr.reason, cr.note, cr.status, cr.created_at,
          u.name as requester_name,
          crec.id as recipient_id, crec.status as recipient_status, crec.invite_token
        FROM coverage_requests cr
        JOIN coverage_recipients crec ON crec.request_id = cr.id
        JOIN contacts c ON c.id = crec.contact_id
        JOIN users u ON u.id = cr.requester_id
        WHERE LOWER(c.name) = (SELECT LOWER(name) FROM users WHERE id = ?)
          AND cr.status IN ('pending', 'approved')
        ORDER BY cr.created_at DESC
      `, [userId], (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  getRecipientByUserId(requestId, userId) {
    return new Promise((resolve, reject) => {
      this.db.get(`
        SELECT crec.* FROM coverage_recipients crec
        JOIN contacts c ON c.id = crec.contact_id
        WHERE crec.request_id = ?
          AND LOWER(c.name) = (SELECT LOWER(name) FROM users WHERE id = ?)
      `, [requestId, userId], (err, row) => err ? reject(err) : resolve(row));
    });
  }

  getCoverageBlocks(userId, dateFrom, dateTo) {
    return new Promise((resolve, reject) => {
      let sql = `
        SELECT ca.id, ca.approved_date, ca.approved_start, ca.approved_end,
          ca.helper_note, c.name as helper_name,
          cr.reason, cr.id as request_id
        FROM coverage_approvals ca
        JOIN coverage_recipients crec ON crec.id = ca.recipient_id
        JOIN contacts c ON c.id = crec.contact_id
        JOIN coverage_requests cr ON cr.id = ca.request_id
        WHERE cr.requester_id = ? AND cr.status != 'cancelled'
      `;
      const params = [userId];
      if (dateFrom) { sql += ' AND ca.approved_date >= ?'; params.push(dateFrom); }
      if (dateTo) { sql += ' AND ca.approved_date <= ?'; params.push(dateTo); }
      sql += ' ORDER BY ca.approved_date, ca.approved_start';
      this.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows || []));
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

  getMessageImage(messageId, userId = null) {
    return new Promise((resolve, reject) => {
      // Only the sender or recipient of the message may fetch its image.
      const sql = userId != null
        ? 'SELECT image_data FROM direct_messages WHERE id = ? AND (sender_id = ? OR recipient_id = ?)'
        : 'SELECT image_data FROM direct_messages WHERE id = ?';
      const params = userId != null ? [messageId, userId, userId] : [messageId];
      this.db.get(sql, params, (err, row) => err ? reject(err) : resolve(row?.image_data || null));
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

  // ============================================
  // User Location & Work Address
  // ============================================

  updateUserWorkAddress(userId, { work_address, work_lat, work_lng }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE users SET work_address = ?, work_lat = ?, work_lng = ? WHERE id = ?',
        [work_address || null, work_lat || null, work_lng || null, userId],
        (err) => err ? reject(err) : resolve()
      );
    });
  }

  updateUserLocation(userId, { lat, lng, location_name }) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'UPDATE users SET last_lat = ?, last_lng = ?, last_location_name = ?, last_location_at = CURRENT_TIMESTAMP WHERE id = ?',
        [lat, lng, location_name || null, userId],
        (err) => err ? reject(err) : resolve()
      );
    });
  }

  getHouseholdPresence(userId) {
    return new Promise((resolve, reject) => {
      this.db.all(`
        SELECT u.id, u.name, u.last_lat, u.last_lng, u.last_location_name, u.last_location_at,
          u.work_address, u.work_lat, u.work_lng
        FROM users u
        JOIN group_members gm ON gm.user_id = u.id
        JOIN groups g ON g.id = gm.group_id AND g.group_type = 'household'
        WHERE gm.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
      `, [userId], (err, rows) => err ? reject(err) : resolve(rows || []));
    });
  }

  getUserWorkAddress(userId) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT work_address, work_lat, work_lng FROM users WHERE id = ?', [userId],
        (err, row) => err ? reject(err) : resolve(row));
    });
  }

  // ============================================
  // Device Tokens (APNs)
  // ============================================

  saveDeviceToken(userId, token) {
    return new Promise((resolve, reject) => {
      this.db.run(`
        INSERT INTO device_tokens (user_id, token, updated_at)
        VALUES (?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(token) DO UPDATE SET user_id = ?, updated_at = CURRENT_TIMESTAMP
      `, [userId, token, userId], function(err) {
        if (err) reject(err);
        else resolve({ id: this.lastID });
      });
    });
  }

  getDeviceTokens(userId) {
    return new Promise((resolve, reject) => {
      this.db.all('SELECT token FROM device_tokens WHERE user_id = ?', [userId],
        (err, rows) => err ? reject(err) : resolve(rows?.map(r => r.token) || []));
    });
  }

  getDeviceTokensForUsers(userIds) {
    if (!userIds || userIds.length === 0) return Promise.resolve([]);
    const placeholders = userIds.map(() => '?').join(',');
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT user_id, token FROM device_tokens WHERE user_id IN (${placeholders})`,
        userIds,
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  removeDeviceToken(token) {
    return new Promise((resolve, reject) => {
      this.db.run('DELETE FROM device_tokens WHERE token = ?', [token],
        (err) => err ? reject(err) : resolve());
    });
  }

  // === Concierge (chat + memory) ===

  createConciergeConversation(userId, groupId) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO concierge_conversations (user_id, group_id) VALUES (?, ?)',
        [userId, groupId || null],
        function(err) { err ? reject(err) : resolve({ id: this.lastID }); }
      );
    });
  }

  getConciergeConversation(id) {
    return new Promise((resolve, reject) => {
      this.db.get('SELECT * FROM concierge_conversations WHERE id = ?', [id],
        (err, row) => err ? reject(err) : resolve(row || null));
    });
  }

  getConciergeMessages(conversationId, limit = 20) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT role, content FROM concierge_messages WHERE conversation_id = ? ORDER BY id DESC LIMIT ?',
        [conversationId, limit],
        (err, rows) => err ? reject(err) : resolve((rows || []).reverse())
      );
    });
  }

  addConciergeMessage(conversationId, role, content) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO concierge_messages (conversation_id, role, content) VALUES (?, ?, ?)',
        [conversationId, role, content],
        function(err) { err ? reject(err) : resolve({ id: this.lastID }); }
      );
    });
  }

  touchConciergeConversation(id) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE concierge_conversations SET updated_at = CURRENT_TIMESTAMP WHERE id = ?',
        [id], (err) => err ? reject(err) : resolve());
    });
  }

  // List a user's conversations, newest first, with a preview of the last message
  // so the client can render a resumable history list.
  getConciergeConversations(userId, limit = 50) {
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT c.id, c.title, c.created_at, c.updated_at,
                (SELECT content FROM concierge_messages m
                 WHERE m.conversation_id = c.id ORDER BY m.id DESC LIMIT 1) AS last_message,
                (SELECT COUNT(*) FROM concierge_messages m WHERE m.conversation_id = c.id) AS message_count
         FROM concierge_conversations c
         WHERE c.user_id = ?
           AND EXISTS (SELECT 1 FROM concierge_messages m WHERE m.conversation_id = c.id)
         ORDER BY datetime(c.updated_at) DESC, c.id DESC LIMIT ?`,
        [parseInt(userId), limit],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  setConciergeConversationTitle(id, title) {
    return new Promise((resolve, reject) => {
      this.db.run('UPDATE concierge_conversations SET title = ? WHERE id = ? AND title IS NULL',
        [title, id], (err) => err ? reject(err) : resolve());
    });
  }

  getConciergeMemory(groupId) {
    return new Promise((resolve, reject) => {
      this.db.all(
        'SELECT content FROM concierge_memory WHERE group_id IS ? ORDER BY created_at DESC LIMIT 50',
        [groupId || null],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  addConciergeMemory(userId, groupId, content) {
    return new Promise((resolve, reject) => {
      this.db.run(
        'INSERT INTO concierge_memory (user_id, group_id, content) VALUES (?, ?, ?)',
        [userId, groupId || null, content],
        function(err) { err ? reject(err) : resolve({ id: this.lastID }); }
      );
    });
  }

  // === Subscriptions (per-household premium entitlement) ===

  // Insert or update by original_transaction_id (the stable subscription key).
  upsertSubscription(sub) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `INSERT INTO subscriptions (group_id, user_id, product_id, original_transaction_id, expires_at, environment, status, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(original_transaction_id) DO UPDATE SET
           group_id = excluded.group_id,
           user_id = excluded.user_id,
           product_id = excluded.product_id,
           expires_at = excluded.expires_at,
           environment = excluded.environment,
           status = excluded.status,
           updated_at = CURRENT_TIMESTAMP`,
        [sub.group_id || null, sub.user_id, sub.product_id || null,
         sub.original_transaction_id, sub.expires_at || null,
         sub.environment || null, sub.status || 'active'],
        (err) => err ? reject(err) : resolve({ ok: true })
      );
    });
  }

  // Every household group with a representative member user id — used to seed
  // comp ("on the house") premium for the family.
  getHouseholdGroupsWithMember() {
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT g.id AS group_id, MIN(gm.user_id) AS user_id
         FROM groups g JOIN group_members gm ON gm.group_id = g.id
         WHERE g.group_type = 'household'
         GROUP BY g.id`,
        [],
        (err, rows) => err ? reject(err) : resolve(rows || [])
      );
    });
  }

  // The household's currently-active subscription (expiry in the future), if any.
  getActiveSubscriptionForGroup(groupId) {
    return new Promise((resolve, reject) => {
      if (!groupId) return resolve(null); // never treat the NULL-group bucket as entitled
      this.db.get(
        `SELECT * FROM subscriptions
         WHERE group_id = ? AND status = 'active' AND expires_at > CURRENT_TIMESTAMP
         ORDER BY expires_at DESC LIMIT 1`,
        [groupId],
        (err, row) => err ? reject(err) : resolve(row || null)
      );
    });
  }

  // Distinct household groups with an active (unexpired) subscription.
  getPremiumGroups() {
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT DISTINCT group_id FROM subscriptions
         WHERE group_id IS NOT NULL AND status = 'active' AND expires_at > CURRENT_TIMESTAMP`,
        [],
        (err, rows) => err ? reject(err) : resolve((rows || []).map(r => r.group_id))
      );
    });
  }

  updateSubscriptionStatus(originalTransactionId, status, expiresAt) {
    return new Promise((resolve, reject) => {
      this.db.run(
        `UPDATE subscriptions SET status = ?, expires_at = COALESCE(?, expires_at), updated_at = CURRENT_TIMESTAMP
         WHERE original_transaction_id = ?`,
        [status, expiresAt || null, String(originalTransactionId)],
        function(err) { err ? reject(err) : resolve({ changed: this.changes }); }
      );
    });
  }

  // === Concierge proactive nudges (throttle/dedup) ===

  recordNudge(groupId, key) {
    return new Promise((resolve, reject) => {
      this.db.run('INSERT INTO concierge_nudges (group_id, nudge_key) VALUES (?, ?)',
        [groupId, key], (err) => err ? reject(err) : resolve());
    });
  }

  // How many nudges this group received in the last N hours (daily-cap check).
  countRecentNudges(groupId, hours) {
    return new Promise((resolve, reject) => {
      this.db.get(
        `SELECT COUNT(*) AS n FROM concierge_nudges WHERE group_id = ? AND sent_at > datetime('now', ?)`,
        [groupId, `-${hours} hours`],
        (err, row) => err ? reject(err) : resolve(row ? row.n : 0)
      );
    });
  }

  // Whether this exact nudge key was sent to the group within the last N hours (dedup).
  recentNudgeKey(groupId, key, hours) {
    return new Promise((resolve, reject) => {
      this.db.get(
        `SELECT 1 FROM concierge_nudges WHERE group_id = ? AND nudge_key = ? AND sent_at > datetime('now', ?) LIMIT 1`,
        [groupId, key, `-${hours} hours`],
        (err, row) => err ? reject(err) : resolve(!!row)
      );
    });
  }

  // Snapshot the live DB into destPath. VACUUM INTO produces a consistent,
  // compacted copy even while writers are active under WAL.
  backupTo(destPath) {
    return new Promise((resolve, reject) => {
      this.db.run('VACUUM INTO ?', [destPath], (err) => err ? reject(err) : resolve(destPath));
    });
  }

  close() {
    // No-op: using shared connection for WAL mode concurrency
  }
}

FamilyDB.DB_DIR = DB_DIR;
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
