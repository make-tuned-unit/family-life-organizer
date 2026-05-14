const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const bcrypt = require('bcryptjs');
const path = require('path');
const FamilyDB = require('./database');
const push = require('./push');

const app = express();
const PORT = process.env.PORT || 3456;

// Legacy hardcoded users — only used as fallback during migration
const LEGACY_USERS = {
  'jesse': { password: 'REDACTED-PASSWORD', name: 'Jesse', avatar: '👨‍💼' },
  'sophie': { password: 'REDACTED-PASSWORD', name: 'Sophie', avatar: '👩‍⚕️' }
};

// Middleware
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));
app.use(session({
  secret: 'REDACTED-SESSION-SECRET',
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false }
}));
app.use(express.static(path.join(__dirname, 'public')));

// Auth middleware
function requireAuth(req, res, next) {
  if (req.session.user) {
    next();
  } else {
    // Return JSON 401 for API requests, redirect for browser
    const isApi = req.path.startsWith('/api/');
    if (isApi) {
      res.status(401).json({ error: 'Not authenticated' });
    } else {
      res.redirect('/login');
    }
  }
}

// JSON API registration
app.post('/api/auth/register', async (req, res) => {
  const db = new FamilyDB();
  try {
    const { username, password, name, invite_code } = req.body;
    if (!username || !password || !name) {
      return res.status(400).json({ error: 'Username, password, and name are required' });
    }

    // Check if username exists
    const existing = await db.getUserByUsername(username);
    if (existing) {
      return res.status(409).json({ error: 'Username already taken' });
    }

    // Hash password and create user
    const password_hash = await bcrypt.hash(password, 10);
    const user = await db.createUser({ username, password_hash, name });

    // If invite code provided, join that household
    let household = null;
    if (invite_code) {
      household = await db.getGroupByInviteCode(invite_code);
      if (household) {
        await db.addGroupMember(household.id, { user_id: user.id, role: 'member', added_by: user.id });
      }
    }

    // If no invite code (or invalid), create a new household
    if (!household) {
      const householdName = req.body.household_name || (name + "'s Home");
      const newHousehold = await db.createGroup({
        name: householdName,
        group_type: 'household',
        created_by: user.id
      });
      await db.addGroupMember(newHousehold.id, { user_id: user.id, role: 'admin', added_by: user.id });
      household = { id: newHousehold.id, invite_code: newHousehold.invite_code };
    }

    // Set session
    req.session.user = { username, name: user.name, id: user.id };
    res.json({
      success: true,
      user: { id: user.id, username, name, avatar: null },
      household: { id: household.id, invite_code: household.invite_code }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// JSON API login — checks users table first, falls back to legacy
app.post('/api/auth/login', async (req, res) => {
  const db = new FamilyDB();
  try {
    const { username, password } = req.body;

    // Try database user first
    const dbUser = await db.getUserByUsername(username);
    if (dbUser) {
      const valid = await bcrypt.compare(password, dbUser.password_hash);
      if (valid) {
        req.session.user = { username: dbUser.username, name: dbUser.name, id: dbUser.id };
        return res.json({ success: true, user: { id: dbUser.id, username: dbUser.username, name: dbUser.name, avatar: dbUser.avatar } });
      }
    }

    // Fallback to legacy hardcoded users (auto-migrate to DB)
    const legacy = LEGACY_USERS[username];
    if (legacy && legacy.password === password) {
      // Migrate legacy user to database
      let user = dbUser;
      if (!user) {
        const password_hash = await bcrypt.hash(password, 10);
        user = await db.createUser({ username, password_hash, name: legacy.name, avatar: legacy.avatar });
        // Auto-create household for migrated user
        const household = await db.createGroup({ name: legacy.name + "'s Home", group_type: 'household', created_by: user.id });
        await db.addGroupMember(household.id, { user_id: user.id, role: 'admin', added_by: user.id });
      }
      req.session.user = { username, name: legacy.name, id: user.id };
      return res.json({ success: true, user: { id: user.id, username, name: legacy.name, avatar: legacy.avatar } });
    }

    res.status(401).json({ error: 'Invalid credentials' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Register device token for push notifications
app.post('/api/auth/device-token', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { token } = req.body;
    if (!token) return res.status(400).json({ error: 'Token required' });
    await db.saveDeviceToken(req.session.user.id, token);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Get current user profile
app.get('/api/auth/me', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.json({ user: req.session.user, groups: [] });
    const user = await db.getUserById(userId);
    const groups = await db.getGroupsByUser(userId);
    res.json({ user, groups });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Profile image upload
app.put('/api/users/me/avatar', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.status(401).json({ error: 'Not authenticated' });
    const { image } = req.body;
    if (!image) return res.status(400).json({ error: 'No image provided' });
    await new Promise((resolve, reject) => {
      db.db.run('UPDATE users SET profile_image = ? WHERE id = ?', [image, userId], (err) => err ? reject(err) : resolve());
    });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Profile image for any user
app.get('/api/users/:id/avatar', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const row = await new Promise((resolve, reject) => {
      db.db.get('SELECT profile_image FROM users WHERE id = ?', [req.params.id], (err, row) => err ? reject(err) : resolve(row));
    });
    if (!row?.profile_image) return res.status(404).json({ error: 'No avatar' });
    res.json({ image: row.profile_image });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Login page - Modern Design
app.get('/login', (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Family Life - Sign In</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', sans-serif;
      background: linear-gradient(135deg, #1e1b4b 0%, #312e81 50%, #4338ca 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .login-card {
      background: white;
      border-radius: 24px;
      padding: 48px;
      width: 100%;
      max-width: 420px;
      box-shadow: 0 25px 80px rgba(0,0,0,0.3);
    }
    .brand {
      text-align: center;
      margin-bottom: 40px;
    }
    .brand-icon {
      width: 64px;
      height: 64px;
      background: linear-gradient(135deg, #6366f1, #ec4899);
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
      margin: 0 auto 16px;
    }
    .brand h1 { font-size: 24px; font-weight: 700; color: #1e293b; }
    .brand p { color: #64748b; margin-top: 8px; }
    .user-selector { margin-bottom: 28px; }
    .selector-label {
      font-size: 14px;
      font-weight: 600;
      color: #374151;
      margin-bottom: 12px;
      display: block;
    }
    .user-options {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    .user-option {
      position: relative;
      cursor: pointer;
    }
    .user-option input {
      position: absolute;
      opacity: 0;
    }
    .user-card {
      border: 2px solid #e5e7eb;
      border-radius: 16px;
      padding: 24px;
      text-align: center;
      transition: all 0.2s;
    }
    .user-option:hover .user-card {
      border-color: #d1d5db;
    }
    .user-option input:checked + .user-card {
      border-color: #6366f1;
      background: #eef2ff;
    }
    .user-avatar {
      font-size: 40px;
      margin-bottom: 8px;
    }
    .user-name {
      font-weight: 600;
      color: #1f2937;
    }
    .password-section { margin-bottom: 24px; }
    .password-input {
      width: 100%;
      padding: 16px;
      border: 2px solid #e5e7eb;
      border-radius: 12px;
      font-size: 16px;
      transition: all 0.2s;
    }
    .password-input:focus {
      outline: none;
      border-color: #6366f1;
    }
    .signin-btn {
      width: 100%;
      padding: 16px;
      background: linear-gradient(135deg, #6366f1, #4f46e5);
      color: white;
      border: none;
      border-radius: 12px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    }
    .signin-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 25px rgba(99, 102, 241, 0.4);
    }
    .error {
      background: #fee2e2;
      color: #dc2626;
      padding: 12px 16px;
      border-radius: 8px;
      margin-bottom: 20px;
      font-size: 14px;
      text-align: center;
    }
    @media (max-width: 480px) {
      .login-card { padding: 32px 24px; }
    }
  </style>
</head>
<body>
  <div class="login-card">
    <div class="brand">
      <div class="brand-icon">🏠</div>
      <h1>Family Life</h1>
      <p>Organize your household together</p>
    </div>
    ${req.query.error ? '<div class="error">Incorrect password. Please try again.</div>' : ''}
    <form method="POST" action="/login">
      <div class="user-selector">
        <label class="selector-label">Who's signing in?</label>
        <div class="user-options">
          <label class="user-option">
            <input type="radio" name="username" value="jesse" checked>
            <div class="user-card">
              <div class="user-avatar">👨‍💼</div>
              <div class="user-name">Jesse</div>
            </div>
          </label>
          <label class="user-option">
            <input type="radio" name="username" value="sophie">
            <div class="user-card">
              <div class="user-avatar">👩‍⚕️</div>
              <div class="user-name">Sophie</div>
            </div>
          </label>
        </div>
      </div>
      <div class="password-section">
        <input type="password" name="password" class="password-input" placeholder="Enter your password" required>
      </div>
      <button type="submit" class="signin-btn">Sign In</button>
    </form>
  </div>
</body>
</html>`);
});

// Login POST (web)
app.post('/login', async (req, res) => {
  const db = new FamilyDB();
  try {
    const { username, password } = req.body;

    // Try DB user
    const dbUser = await db.getUserByUsername(username);
    if (dbUser) {
      const valid = await bcrypt.compare(password, dbUser.password_hash);
      if (valid) {
        req.session.user = { username: dbUser.username, name: dbUser.name, avatar: dbUser.avatar, id: dbUser.id };
        return res.redirect('/');
      }
    }

    // Legacy fallback
    const legacy = LEGACY_USERS[username];
    if (legacy && legacy.password === password) {
      req.session.user = { username, name: legacy.name, avatar: legacy.avatar };
      return res.redirect('/');
    }

    res.redirect('/login?error=1');
  } catch (err) {
    res.redirect('/login?error=1');
  } finally {
    db.close();
  }
});

// Logout
app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

// Dashboard
app.get('/', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const summary = await db.getDailySummary(userId);
    const groceries = await db.getGroceries('needed');
    const tasks = await db.getTasks({ status: 'active' });
    const appointments = await db.getAppointments({}, userId);
    const tasksByCategory = {};
    tasks.forEach(task => {
      if (!tasksByCategory[task.category]) tasksByCategory[task.category] = [];
      tasksByCategory[task.category].push(task);
    });
    res.send(renderDashboard(req.session.user, summary, groceries, tasksByCategory, appointments));
  } catch (err) {
    res.status(500).send('Error: ' + err.message);
  } finally {
    db.close();
  }
});

// Render Dashboard
function renderDashboard(user, summary, groceries, tasksByCategory, appointments) {
  const categories = Object.keys(tasksByCategory).sort();
  const today = new Date().toISOString().split('T')[0];
  const todayAppointments = appointments.filter(a => a.appointment_date === today);
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Family Life Organizer</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    * { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --primary: #6366f1;
      --primary-dark: #4f46e5;
      --gray-50: #f8fafc;
      --gray-100: #f1f5f9;
      --gray-200: #e2e8f0;
      --gray-300: #cbd5e1;
      --gray-600: #475569;
      --gray-800: #1e293b;
      --gray-900: #0f172a;
    }
    body {
      font-family: 'Inter', sans-serif;
      background: var(--gray-50);
      color: var(--gray-800);
    }
    .header {
      background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%);
      color: white;
      padding: 16px 24px;
      position: sticky;
      top: 0;
      z-index: 100;
    }
    .header-content {
      max-width: 1200px;
      margin: 0 auto;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .brand { display: flex; align-items: center; gap: 12px; }
    .brand-icon {
      width: 40px; height: 40px;
      background: linear-gradient(135deg, var(--primary), #ec4899);
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      font-size: 20px;
    }
    .brand h1 { font-size: 20px; font-weight: 700; }
    .user-menu { display: flex; align-items: center; gap: 16px; }
    .user-badge {
      display: flex; align-items: center; gap: 8px;
      padding: 8px 16px;
      background: rgba(255,255,255,0.1);
      border-radius: 9999px;
      font-size: 14px;
    }
    .logout-btn {
      padding: 8px 16px;
      background: rgba(255,255,255,0.1);
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      cursor: pointer;
    }
    .nav-tabs {
      background: white;
      border-bottom: 1px solid var(--gray-200);
      position: sticky;
      top: 72px;
      z-index: 99;
    }
    .nav-tabs-content {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 24px;
      display: flex;
      gap: 4px;
    }
    .nav-tab {
      padding: 16px 20px;
      background: none;
      border: none;
      border-bottom: 2px solid transparent;
      margin-bottom: -1px;
      font-size: 14px;
      font-weight: 500;
      color: var(--gray-600);
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .nav-tab.active {
      color: var(--primary);
      border-bottom-color: var(--primary);
    }
    .main-content {
      max-width: 1200px;
      margin: 0 auto;
      padding: 24px;
    }
    .tab-panel {
      display: none;
      animation: fadeIn 0.3s ease;
    }
    .tab-panel.active { display: block; }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(10px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin-bottom: 32px;
    }
    .stat-card {
      background: white;
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .stat-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 16px;
    }
    .stat-icon {
      width: 48px; height: 48px;
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      font-size: 24px;
    }
    .stat-value { font-size: 32px; font-weight: 700; }
    .stat-label { font-size: 14px; color: var(--gray-600); margin-top: 4px; }
    .card {
      background: white;
      border-radius: 16px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      overflow: hidden;
    }
    .card-header {
      padding: 20px 24px;
      border-bottom: 1px solid var(--gray-100);
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .card-title { font-size: 18px; font-weight: 600; }
    .card-body { padding: 24px; }
    .form-input, .form-select {
      width: 100%;
      padding: 12px 16px;
      border: 1px solid var(--gray-300);
      border-radius: 10px;
      font-size: 15px;
      margin-bottom: 12px;
    }
    .btn {
      padding: 12px 24px;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      border: none;
    }
    .btn-primary {
      background: linear-gradient(135deg, var(--primary), var(--primary-dark));
      color: white;
    }
    .list-item {
      display: flex;
      align-items: center;
      padding: 16px;
      border-bottom: 1px solid var(--gray-100);
    }
    .list-item:last-child { border-bottom: none; }
    .checkbox {
      width: 22px; height: 22px;
      border: 2px solid var(--gray-300);
      border-radius: 6px;
      margin-right: 16px;
      cursor: pointer;
    }
    .list-content { flex: 1; }
    .badge {
      padding: 4px 12px;
      border-radius: 9999px;
      font-size: 12px;
      background: var(--gray-100);
      color: var(--gray-600);
    }
    .two-column {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 24px;
    }
    @media (max-width: 768px) {
      .two-column { grid-template-columns: 1fr; }
      .nav-tab-text { display: none; }
      .stats-grid { grid-template-columns: repeat(2, 1fr); gap: 12px; }
      .stat-card { padding: 16px; }
      .stat-value { font-size: 24px; }
      .stat-icon { width: 36px; height: 36px; font-size: 18px; }
      .card-header { padding: 16px; }
      .card-body { padding: 16px; }
      .form-input, .form-select { padding: 14px; font-size: 16px; }
      .btn { padding: 14px 20px; width: 100%; margin-bottom: 8px; }
      .main-content { padding: 16px; }
      .header-content { padding: 12px 16px; }
      .brand h1 { font-size: 18px; }
    }
    
    /* Calendar Grid Styles */
    .calendar-grid {
      display: grid;
      grid-template-columns: repeat(7, 1fr);
      gap: 4px;
    }
    .calendar-day-header {
      text-align: center;
      padding: 12px 4px;
      font-size: 12px;
      font-weight: 600;
      color: var(--gray-500);
      text-transform: uppercase;
    }
    .calendar-day {
      aspect-ratio: 1;
      border: 1px solid var(--gray-200);
      border-radius: 8px;
      padding: 6px;
      min-height: 80px;
      display: flex;
      flex-direction: column;
      background: white;
    }
    .calendar-day.other-month {
      background: var(--gray-50);
      color: var(--gray-400);
    }
    .calendar-day.today {
      border-color: var(--primary);
      border-width: 2px;
      background: #eef2ff;
    }
    .calendar-day-number {
      font-weight: 600;
      font-size: 14px;
      margin-bottom: 4px;
    }
    .calendar-day.today .calendar-day-number {
      color: var(--primary);
    }
    .calendar-event {
      font-size: 10px;
      padding: 2px 4px;
      background: var(--primary);
      color: white;
      border-radius: 4px;
      margin-bottom: 2px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .calendar-event-dot {
      width: 6px;
      height: 6px;
      background: var(--primary);
      border-radius: 50%;
      display: inline-block;
      margin-right: 4px;
    }
    @media (max-width: 640px) {
      .calendar-day {
        min-height: 50px;
        padding: 4px;
      }
      .calendar-day-header {
        padding: 8px 2px;
        font-size: 10px;
      }
      .calendar-day-number {
        font-size: 12px;
      }
      .calendar-event {
        font-size: 8px;
        padding: 1px 2px;
      }
    }
  </style>
</head>
<body>
  <header class="header">
    <div class="header-content">
      <div class="brand">
        <div class="brand-icon">🏠</div>
        <h1>Family Life</h1>
      </div>
      <div class="user-menu">
        <div class="user-badge">
          <span>${user.avatar}</span>
          <span>${user.name}</span>
        </div>
        <button class="logout-btn" onclick="location.href='/logout'">Sign Out</button>
      </div>
    </div>
  </header>
  
  <nav class="nav-tabs">
    <div class="nav-tabs-content">
      <button class="nav-tab active" onclick="switchTab('overview', this)">
        <span>📊</span><span class="nav-tab-text">Overview</span>
      </button>
      <button class="nav-tab" onclick="switchTab('calendar', this)">
        <span>📅</span><span class="nav-tab-text">Calendar</span>
      </button>
      <button class="nav-tab" onclick="switchTab('budget', this)">
        <span>💰</span><span class="nav-tab-text">Budget</span>
      </button>
      <button class="nav-tab" onclick="switchTab('groceries', this)">
        <span>🛒</span><span class="nav-tab-text">Groceries</span>
      </button>
      <button class="nav-tab" onclick="switchTab('tasks', this)">
        <span>✓</span><span class="nav-tab-text">Tasks</span>
      </button>
      <button class="nav-tab" onclick="switchTab('add', this)">
        <span>+</span><span class="nav-tab-text">Add</span>
      </button>
    </div>
  </nav>
  
  <main class="main-content">
    <!-- Overview Tab -->
    <div id="overview" class="tab-panel active">
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${summary.tasks_today}</div>
              <div class="stat-label">Tasks Today</div>
            </div>
            <div class="stat-icon" style="background:#dbeafe">📋</div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${todayAppointments.length}</div>
              <div class="stat-label">Appointments</div>
            </div>
            <div class="stat-icon" style="background:#fce7f3">📅</div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${summary.groceries_needed}</div>
              <div class="stat-label">Groceries</div>
            </div>
            <div class="stat-icon" style="background:#d1fae5">🛒</div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-header">
            <div>
              <div class="stat-value">${summary.overdue_tasks}</div>
              <div class="stat-label">Overdue</div>
            </div>
            <div class="stat-icon" style="background:#ffedd5">⚠️</div>
          </div>
        </div>
      </div>
      
      <div class="two-column">
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Quick Tasks</h3>
          </div>
          <div class="card-body">
            ${categories.slice(0, 3).map(cat => `
              <h4 style="font-size:14px;color:var(--gray-600);margin:16px 0 8px">${cat}</h4>
              ${tasksByCategory[cat].slice(0, 2).map(task => `
                <div class="list-item">
                  <div class="checkbox" onclick="completeTask(${task.id})"></div>
                  <div class="list-content">${task.title}</div>
                </div>
              `).join('')}
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No tasks for today!</p>'}
          </div>
        </div>
        
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Grocery List</h3>
          </div>
          <div class="card-body">
            ${groceries.slice(0, 5).map(item => `
              <div class="list-item">
                <div class="checkbox" onclick="completeGrocery(${item.id})"></div>
                <div class="list-content">${item.item}</div>
                ${item.category ? `<span class="badge">${item.category}</span>` : ''}
              </div>
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No items needed</p>'}
          </div>
        </div>
        
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Today's Appointments</h3>
          </div>
          <div class="card-body">
            ${todayAppointments.map(appt => `
              <div class="list-item">
                <div class="list-content">
                  <strong>${appt.title}</strong>
                  ${appt.appointment_time ? `<span style="color:var(--gray-500);margin-left:8px">${appt.appointment_time}</span>` : ''}
                  ${appt.person_tags ? `<div style="margin-top:4px">${appt.person_tags.split(',').map(p => `<span class="badge" style="margin-right:4px">${p}</span>`).join('')}</div>` : ''}
                </div>
              </div>
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No appointments today</p>'}
          </div>
        </div>
      </div>
    </div>
    
    <!-- Calendar Tab -->
    <div id="calendar" class="tab-panel">
      <div class="card">
        <div class="card-header" style="flex-wrap:wrap;gap:12px">
          <h3 class="card-title" id="calendarTitle">Calendar</h3>
          <div style="display:flex;gap:8px">
            <button class="btn btn-secondary" onclick="changeMonth(-1)">← Prev</button>
            <button class="btn btn-secondary" onclick="changeMonth(1)">Next →</button>
            <button class="btn btn-primary" onclick="goToToday()">Today</button>
          </div>
        </div>
        <div class="card-body">
          <div class="calendar-grid" id="calendarGrid">
            <!-- Calendar generated by JS -->
          </div>
        </div>
      </div>
    </div>
    
    <!-- Budget Tab -->
    <div id="budget" class="tab-panel">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Household Budget</h3>
        </div>
        <div class="card-body">
          <p style="background:#eef2ff;padding:16px;border-radius:12px;margin-bottom:24px">
            📧 Forward receipts to: <strong>redacted@example.com</strong>
          </p>
          <div class="two-column">
            <div>
              <h4 style="margin-bottom:16px">Add Receipt</h4>
              <input type="number" class="form-input" placeholder="Amount ($)">
              <input type="text" class="form-input" placeholder="Merchant">
              <select class="form-select">
                <option>Select category...</option>
                <option>Groceries</option>
                <option>Dining</option>
                <option>Gas</option>
                <option>Household</option>
              </select>
              <button class="btn btn-primary">Add Receipt</button>
            </div>
            <div>
              <h4 style="margin-bottom:16px">Recent</h4>
              <p style="color:var(--gray-600);text-align:center;padding:32px">No receipts yet</p>
            </div>
          </div>
        </div>
      </div>
    </div>
    
    <!-- Groceries Tab -->
    <div id="groceries" class="tab-panel">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Grocery List</h3>
        </div>
        <div class="card-body">
          <div style="display:flex;gap:12px;margin-bottom:24px">
            <input type="text" class="form-input" id="groceryInput" placeholder="Add item..." style="flex:1;margin:0">
            <button class="btn btn-primary" onclick="addGrocery()">Add</button>
          </div>
          ${groceries.map(item => `
            <div class="list-item">
              <div class="checkbox" onclick="completeGrocery(${item.id})"></div>
              <div class="list-content">${item.item}</div>
              ${item.category ? `<span class="badge">${item.category}</span>` : ''}
            </div>
          `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No items needed</p>'}
        </div>
      </div>
    </div>
    
    <!-- Tasks Tab -->
    <div id="tasks" class="tab-panel">
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">All Tasks</h3>
        </div>
        <div class="card-body">
          ${categories.map(cat => `
            <h4 style="font-size:14px;color:var(--gray-600);margin:24px 0 12px;text-transform:capitalize">${cat}</h4>
            ${tasksByCategory[cat].map(task => `
              <div class="list-item">
                <div class="checkbox" onclick="completeTask(${task.id})"></div>
                <div class="list-content">${task.title}</div>
                ${task.due_date ? `<span class="badge">${task.due_date}</span>` : ''}
              </div>
            `).join('')}
          `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No tasks yet!</p>'}
        </div>
      </div>
    </div>
    
    <!-- Add Tab -->
    <div id="add" class="tab-panel">
      <div class="two-column">
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Add Task</h3>
          </div>
          <div class="card-body">
            <input type="text" class="form-input" id="taskTitle" placeholder="What needs to be done?">
            <select class="form-select" id="taskCategory">
              <option value="">Select category...</option>
              <option value="groceries">Groceries</option>
              <option value="appointments">Appointments</option>
              <option value="home">Home</option>
              <option value="automotive">Automotive</option>
              <option value="travel">Travel</option>
              <option value="finances">Finances</option>
              <option value="childcare">Childcare</option>
              <option value="health">Health</option>
            </select>
            <input type="date" class="form-input" id="taskDate">
            <button class="btn btn-primary" onclick="addTask()">Add Task</button>
          </div>
        </div>
        
        <div class="card">
          <div class="card-header">
            <h3 class="card-title">Add Appointment</h3>
          </div>
          <div class="card-body">
            <input type="text" class="form-input" id="apptTitle" placeholder="Event title (e.g., Dentist, School play)">
            <input type="date" class="form-input" id="apptDate">
            <input type="time" class="form-input" id="apptTime">
            <input type="text" class="form-input" id="apptLocation" placeholder="Location (optional)">
            <div style="margin-bottom:16px">
              <label style="display:block;font-size:14px;color:var(--gray-600);margin-bottom:8px">Who's involved?</label>
              <div style="display:flex;gap:16px;flex-wrap:wrap">
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Jesse"> Jesse
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Sophie"> Sophie
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Rowan"> Rowan
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="appt-person" value="Baby"> Baby
                </label>
              </div>
            </div>
            <button class="btn btn-primary" onclick="addAppointment()">Add Appointment</button>
          </div>
        </div>
      </div>
    </div>
  </main>
  
  <script>
    function switchTab(tabName, btn) {
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      document.querySelectorAll('.nav-tab').forEach(t => t.classList.remove('active'));
      document.getElementById(tabName).classList.add('active');
      btn.classList.add('active');
    }
    
    async function completeTask(id) {
      await fetch('/api/complete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'task', id})
      });
      location.reload();
    }
    
    async function completeGrocery(id) {
      await fetch('/api/complete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'grocery', id})
      });
      location.reload();
    }
    
    async function addGrocery() {
      const item = document.getElementById('groceryInput').value;
      if (!item) return;
      await fetch('/api/add', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'grocery', data: {item}})
      });
      location.reload();
    }
    
    async function addTask() {
      const title = document.getElementById('taskTitle').value;
      const category = document.getElementById('taskCategory').value;
      if (!title || !category) return;
      await fetch('/api/add', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'task', data: {title, category}})
      });
      location.reload();
    }
    
    async function addAppointment() {
      const btn = event.target;
      const title = document.getElementById('apptTitle')?.value;
      const date = document.getElementById('apptDate')?.value;
      const time = document.getElementById('apptTime')?.value;
      const locationVal = document.getElementById('apptLocation')?.value;
      const personCheckboxes = document.querySelectorAll('.appt-person:checked');
      const person_tags = Array.from(personCheckboxes).map(cb => cb.value);
      
      if (!title || !date) {
        alert('Please enter a title and date');
        return;
      }
      
      btn.disabled = true;
      btn.textContent = 'Adding...';
      
      try {
        const response = await fetch('/api/appointments', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            title, 
            appointment_date: date,
            appointment_time: time,
            location: locationVal,
            person_tags: person_tags
          })
        });
        
        if (!response.ok) {
          const err = await response.text();
          alert('Error: ' + err);
          btn.disabled = false;
          btn.textContent = 'Add Appointment';
          return;
        }
        
        location.reload();
      } catch (err) {
        alert('Network error: ' + err.message);
        btn.disabled = false;
        btn.textContent = 'Add Appointment';
      }
    }
    
    // Calendar Functions
    let currentCalendarDate = new Date();
    const appointmentsData = ${JSON.stringify(appointments)};
    
    function renderCalendar() {
      const year = currentCalendarDate.getFullYear();
      const month = currentCalendarDate.getMonth();
      const firstDay = new Date(year, month, 1);
      const lastDay = new Date(year, month + 1, 0);
      const daysInMonth = lastDay.getDate();
      const startDayOfWeek = firstDay.getDay();
      
      // Update title
      const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 
                          'July', 'August', 'September', 'October', 'November', 'December'];
      document.getElementById('calendarTitle').textContent = monthNames[month] + ' ' + year;
      
      let html = '';
      
      // Day headers
      const dayHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      dayHeaders.forEach(day => {
        html += '<div class="calendar-day-header">' + day + '</div>';
      });

      // Empty cells before start of month
      for (let i = 0; i < startDayOfWeek; i++) {
        html += '<div class="calendar-day other-month"></div>';
      }

      // Days of month
      const today = new Date().toISOString().split('T')[0];
      for (let day = 1; day <= daysInMonth; day++) {
        const dateStr = year + '-' + String(month + 1).padStart(2, '0') + '-' + String(day).padStart(2, '0');
        const isToday = dateStr === today;
        const dayAppointments = appointmentsData.filter(a => a.appointment_date === dateStr);

        html += '<div class="calendar-day ' + (isToday ? 'today' : '') + '">';
        html += '<div class="calendar-day-number">' + day + '</div>';

        if (dayAppointments.length > 0) {
          dayAppointments.slice(0, 2).forEach(appt => {
            html += '<div class="calendar-event" title="' + appt.title + '">' + appt.title + '</div>';
          });
          if (dayAppointments.length > 2) {
            html += '<div style="font-size:10px;color:var(--gray-500)">+' + (dayAppointments.length - 2) + ' more</div>';
          }
        }

        html += '</div>';
      }
      
      document.getElementById('calendarGrid').innerHTML = html;
    }
    
    function changeMonth(delta) {
      currentCalendarDate.setMonth(currentCalendarDate.getMonth() + delta);
      renderCalendar();
    }
    
    function goToToday() {
      currentCalendarDate = new Date();
      renderCalendar();
    }
    
    // Initialize calendar when tab is shown
    const originalSwitchTab = switchTab;
    switchTab = function(tabName, btn) {
      originalSwitchTab(tabName, btn);
      if (tabName === 'calendar') {
        renderCalendar();
      }
    };
    
    // Also update stats on load
    document.addEventListener('DOMContentLoaded', function() {
      // Update appointments count
      const today = new Date().toISOString().split('T')[0];
      const todayApptCount = appointmentsData.filter(a => a.appointment_date === today).length;
      const apptCard = document.querySelector('.stat-card:nth-child(2) .stat-value');
      if (apptCard) apptCard.textContent = todayApptCount;
    });
  </script>
</body>
</html>`;
}

// API Routes
app.post('/api/add', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { type, data } = req.body;
    if (type === 'grocery') {
      await db.addGrocery(data.item, data.category || null, data.quantity || '1');
    } else if (type === 'task') {
      await db.addTask({...data, status: 'active'});
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/complete', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { type, id } = req.body;
    if (type === 'grocery') {
      await db.purchaseGrocery(id);
    } else if (type === 'task') {
      await db.completeTask(id);
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/data', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const summary = await db.getDailySummary(userId);
    const groceries = await db.getGroceries('needed');
    res.json({ summary, groceries });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/appointments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.appointment_date) data.appointment_date = normalizeDate(data.appointment_date);
    if (!data.group_id) {
      data.group_id = await db.getUserHouseholdId(req.session.user.id);
    }
    await db.addAppointment(data);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// === Mobile API Endpoints ===

// Tasks
app.get('/api/tasks', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.status) filters.status = req.query.status;
    if (req.query.category) filters.category = req.query.category;
    if (req.query.assigned_to) filters.assigned_to = req.query.assigned_to;
    const tasks = await db.getTasks(filters);
    res.json(tasks);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Appointments - list with filters
app.get('/api/appointments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.date_from) filters.date_from = req.query.date_from;
    if (req.query.date_to) filters.date_to = req.query.date_to;
    if (req.query.person) filters.person = req.query.person;
    const appointments = await db.getAppointments(filters, req.session.user.id);
    res.json(appointments);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Appointments - by month
app.get('/api/appointments/:year/:month', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const year = parseInt(req.params.year);
    const month = parseInt(req.params.month);
    const userId = req.session.user.id;
    const appointments = await db.getAppointmentsByMonth(year, month, userId);

    // Expand recurring events into the queried month
    const rangeStart = new Date(year, month - 1, 1);
    const rangeEnd = new Date(month === 12 ? year + 1 : year, month === 12 ? 0 : month, 1);
    const recurring = await db.getRecurringAppointments(userId);
    for (const appt of recurring) {
      const originDate = new Date(appt.appointment_date + 'T00:00:00');
      if (originDate >= rangeStart && originDate < rangeEnd) continue; // already in results
      const endDate = appt.recurrence_end ? new Date(appt.recurrence_end + 'T23:59:59') : null;
      const occurrences = expandRecurrence(appt.recurrence_rule, originDate, rangeStart, rangeEnd, endDate);
      for (const date of occurrences) {
        const dateStr = date.toISOString().slice(0, 10);
        appointments.push({ ...appt, appointment_date: dateStr, _recurring_source: appt.id });
      }
    }

    appointments.sort((a, b) => (a.appointment_date + (a.appointment_time || '')).localeCompare(b.appointment_date + (b.appointment_time || '')));
    res.json(appointments);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Appointments - delete
app.delete('/api/appointments/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteAppointment(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/appointments/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.appointment_date) data.appointment_date = normalizeDate(data.appointment_date);
    await db.updateAppointment(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Groceries
app.get('/api/groceries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const status = req.query.status || 'needed';
    const groceries = await db.getGroceries(status);
    res.json(groceries);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Receipts
app.get('/api/receipts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.month) filters.month = req.query.month;
    if (req.query.category) filters.category = req.query.category;
    const receipts = await db.getReceipts(filters);
    res.json(receipts);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Budget summary by month
app.get('/api/budget/:month', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const budget = await db.getBudgetSummary(req.params.month);
    res.json(budget);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Budget categories CRUD
app.get('/api/budget-categories', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const categories = await db.getBudgetCategories();
    res.json(categories);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/budget-categories', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { name, monthly_limit, color } = req.body;
    const result = await db.addBudgetCategory(name, monthly_limit, color);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/budget-categories/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.updateBudgetCategory(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/budget-categories/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteBudgetCategory(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Receipts - save
app.post('/api/receipts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    if (req.body.category) {
      await db.ensureBudgetCategory(req.body.category);
    }
    const data = { ...req.body };
    if (data.date) data.date = normalizeDate(data.date);
    if (!data.added_by) data.added_by = req.session.user?.username || 'jesse';
    const result = await db.addReceipt(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Receipts - scan with Claude Vision
app.post('/api/receipts/scan', requireAuth, async (req, res) => {
  try {
    const { image } = req.body;

    if (!process.env.ANTHROPIC_API_KEY) {
      // Mock scan result when no API key
      res.json({
        merchant: "Sample Store",
        date: new Date().toISOString().split('T')[0],
        total: 42.50,
        category: "Groceries",
        items: [
          { name: "Milk", price: 4.99, quantity: "1" },
          { name: "Bread", price: 3.49, quantity: "1" },
          { name: "Eggs", price: 5.99, quantity: "1" },
          { name: "Chicken Breast", price: 12.99, quantity: "1" },
          { name: "Apples", price: 6.49, quantity: "1 bag" },
          { name: "Rice", price: 8.55, quantity: "1" }
        ]
      });
      return;
    }

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1500,
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: image } },
            { type: 'text', text: 'Extract receipt data. Return ONLY valid JSON: {"merchant":"store name","date":"YYYY-MM-DD","total":0.00,"category":"Groceries|Dining Out|Gas/Transport|Household|Health|Entertainment|Kids|Other","items":[{"name":"item","price":0.00,"quantity":"1"}]}' }
          ]
        }]
      })
    });

    const data = await response.json();
    const text = data.content[0].text;
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      res.json(JSON.parse(jsonMatch[0]));
    } else {
      res.status(500).json({ error: 'Could not parse receipt' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Receipts - save scanned receipt (dual save: expenses + pantry)
app.post('/api/receipts/save', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { merchant, date, total, category, notes } = req.body;
    const username = req.session.user?.username || 'jesse';

    // Normalize date to YYYY-MM-DD for strftime compatibility
    const normalizedDate = normalizeDate(date);

    // Ensure budget category exists (auto-create if new)
    if (category) {
      await db.ensureBudgetCategory(category);
    }

    // Save receipt
    const receipt = await db.addReceipt({
      amount: total,
      merchant,
      date: normalizedDate,
      category: category || 'Other',
      notes: notes || null,
      processed_by: 'scan',
      added_by: username
    });

    res.json({ success: true, receipt_id: receipt.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/receipts/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteReceipt(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Helper: normalize date to YYYY-MM-DD for SQLite strftime
// Expand a recurrence rule into dates within [rangeStart, rangeEnd)
function expandRecurrence(rule, origin, rangeStart, rangeEnd, endDate) {
  const dates = [];
  let cursor = new Date(origin);
  const step = { daily: 1, weekly: 7, biweekly: 14 }[rule];
  for (let i = 0; i < 400; i++) {
    if (step) {
      cursor = new Date(cursor.getTime() + step * 86400000);
    } else if (rule === 'monthly') {
      cursor = new Date(cursor);
      cursor.setMonth(cursor.getMonth() + 1);
    } else if (rule === 'yearly') {
      cursor = new Date(cursor);
      cursor.setFullYear(cursor.getFullYear() + 1);
    } else {
      break;
    }
    if (endDate && cursor > endDate) break;
    if (cursor >= rangeEnd) break;
    if (cursor >= rangeStart) dates.push(new Date(cursor));
  }
  return dates;
}

function normalizeDate(dateStr) {
  if (!dateStr) return new Date().toISOString().split('T')[0];
  // Already YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return dateStr;
  // Try parsing with Date constructor
  const parsed = new Date(dateStr);
  if (!isNaN(parsed.getTime())) {
    return parsed.toISOString().split('T')[0];
  }
  // Fallback to today
  return new Date().toISOString().split('T')[0];
}

// Helper: guess pantry category from item name
function guessItemCategory(name) {
  const n = name.toLowerCase();
  if (/milk|cheese|yogurt|butter|cream/.test(n)) return 'Dairy';
  if (/chicken|beef|pork|fish|salmon|shrimp|meat/.test(n)) return 'Meat';
  if (/apple|banana|tomato|lettuce|onion|potato|carrot|fruit|vegetable/.test(n)) return 'Produce';
  if (/bread|bagel|muffin|roll|bun/.test(n)) return 'Bakery';
  if (/frozen|ice cream|pizza/.test(n)) return 'Frozen';
  if (/rice|pasta|flour|sugar|cereal|oat/.test(n)) return 'Dry Goods';
  if (/water|juice|soda|coffee|tea|beer|wine/.test(n)) return 'Beverages';
  if (/chip|cookie|cracker|candy|snack/.test(n)) return 'Snacks';
  if (/soap|detergent|paper|tissue|cleaner/.test(n)) return 'Household';
  return 'Other';
}

// Helper: guess storage location from item name
function guessLocation(name) {
  const n = name.toLowerCase();
  if (/milk|cheese|yogurt|butter|cream|chicken|beef|fish|egg|juice/.test(n)) return 'fridge';
  if (/frozen|ice cream/.test(n)) return 'freezer';
  if (/banana|apple|bread|potato|onion|tomato/.test(n)) return 'counter';
  return 'pantry';
}

// Pantry CRUD
app.get('/api/pantry', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.location) filters.location = req.query.location;
    if (req.query.category) filters.category = req.query.category;
    const items = await db.getPantry(filters);
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/pantry', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.expiry_date) data.expiry_date = normalizeDate(data.expiry_date);
    const result = await db.addPantryItem(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/pantry/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.expiry_date) data.expiry_date = normalizeDate(data.expiry_date);
    await db.updatePantryItem(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/pantry/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deletePantryItem(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Cook - recipe suggestions (requires ANTHROPIC_API_KEY env var)
app.post('/api/cook/suggest', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const pantryItems = await db.getPantry();
    const pantryList = pantryItems.map(i => i.item + ' (' + (i.quantity || 1) + (i.unit ? ' ' + i.unit : '') + ')').join(', ');
    const query = req.body.query || 'What can I make for dinner?';

    // If no API key, return mock recipes
    if (!process.env.ANTHROPIC_API_KEY) {
      res.json({
        recipes: [
          {
            name: "Quick Pasta",
            cook_time: 20,
            difficulty: "Easy",
            servings: 4,
            ingredients: pantryItems.slice(0, 4).map(i => ({ name: i.item, quantity: i.quantity, available: true }))
              .concat([{ name: "Parmesan cheese", quantity: "1/2 cup", available: false }]),
            steps: ["Boil water and cook pasta", "Sauté garlic in olive oil", "Combine and season", "Serve with parmesan"]
          },
          {
            name: "Simple Stir Fry",
            cook_time: 15,
            difficulty: "Easy",
            servings: 4,
            ingredients: pantryItems.slice(0, 3).map(i => ({ name: i.item, quantity: i.quantity, available: true }))
              .concat([{ name: "Soy sauce", quantity: "2 tbsp", available: false }]),
            steps: ["Heat oil in wok", "Add vegetables and stir fry", "Add sauce", "Serve over rice"]
          },
          {
            name: "Family Salad Bowl",
            cook_time: 10,
            difficulty: "Easy",
            servings: 4,
            ingredients: pantryItems.slice(0, 5).map(i => ({ name: i.item, quantity: i.quantity, available: true }))
              .concat([{ name: "Feta cheese", quantity: "1/4 cup", available: false }]),
            steps: ["Wash and chop vegetables", "Prepare dressing", "Toss together", "Top with cheese and serve"]
          }
        ]
      });
      return;
    }

    // Call Claude API for real suggestions
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 2000,
        messages: [{
          role: 'user',
          content: `You are a helpful cooking assistant for a family. Here is what's in their pantry: ${pantryList}

Their question: ${query}

Suggest exactly 3 recipes. Return ONLY valid JSON with this structure:
{"recipes": [{"name": "...", "cook_time": 20, "difficulty": "Easy|Medium|Hard", "servings": 4, "ingredients": [{"name": "...", "quantity": "...", "available": true/false}], "steps": ["step 1", "step 2"]}]}

Mark ingredients as available:true if they're in the pantry list, available:false if not.`
        }]
      })
    });

    const data = await response.json();
    const text = data.content[0].text;
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      res.json(JSON.parse(jsonMatch[0]));
    } else {
      res.status(500).json({ error: 'Could not parse recipe response' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Cook - deduct ingredients from pantry
app.post('/api/cook/deduct', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { ingredients } = req.body;
    const pantryItems = await db.getPantry();
    for (const name of ingredients) {
      const match = pantryItems.find(p => p.item.toLowerCase() === name.toLowerCase());
      if (match) {
        const qty = parseInt(match.quantity) || 1;
        if (qty <= 1) {
          await db.deletePantryItem(match.id);
        } else {
          await db.updatePantryItem(match.id, { quantity: String(qty - 1) });
        }
      }
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Trips
app.get('/api/trips', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const filters = {};
    if (req.query.status) filters.status = req.query.status;
    if (req.query.traveler) filters.traveler = req.query.traveler;
    const trips = await db.getTrips(filters);
    res.json(trips);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/trips', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.createTrip(req.body);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/trips/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.updateTrip(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/trips/:id/arrive', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.arriveTrip(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/trips/:id/cancel', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.cancelTrip(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Family addresses
app.get('/api/addresses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const addresses = await db.getFamilyAddresses();
    res.json(addresses);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/addresses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.addFamilyAddress(req.body);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/addresses/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { name, address, lat, lng } = req.body;
    const fields = [];
    const params = [];
    if (name) { fields.push('name = ?'); params.push(name); }
    if (address !== undefined) { fields.push('address = ?'); params.push(address); }
    if (lat !== undefined) { fields.push('lat = ?'); params.push(lat); }
    if (lng !== undefined) { fields.push('lng = ?'); params.push(lng); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await new Promise((resolve, reject) => {
      db.db.run(`UPDATE family_addresses SET ${fields.join(', ')} WHERE id = ?`, params, (err) => err ? reject(err) : resolve());
    });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/addresses/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteFamilyAddress(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Decisions
app.get('/api/decisions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const decisions = await db.getDecisions({ status: req.query.status }, req.session.user.id);
    res.json(decisions);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/decisions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    const userId = req.session.user.id;
    const senderName = req.session.user.name;
    if (!data.group_id) {
      data.group_id = await db.getUserHouseholdId(userId);
    }
    const result = await db.addDecision(data);
    res.json({ success: true, id: result.id });
    // Push to household members
    if (data.group_id) {
      push.pushToGroup(db, data.group_id, userId, `${senderName} needs your input`, data.title || 'New decision', { type: 'decision' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/decisions/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.updateDecision(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/decisions/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  const run = (sql, params) => new Promise((resolve, reject) => {
    db.db.run(sql, params, (err) => err ? reject(err) : resolve());
  });
  try {
    await run('DELETE FROM decision_reactions WHERE decision_id = ?', [req.params.id]);
    await run('DELETE FROM decision_comments WHERE decision_id = ?', [req.params.id]);
    await run('DELETE FROM decisions WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/decisions/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const reactions = await db.getDecisionReactions(req.params.id);
    res.json(reactions);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/decisions/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { member_name, reaction_type, poll_choice } = req.body;
    await db.replaceDecisionReaction(req.params.id, member_name, reaction_type, poll_choice);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/decisions/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const comments = await db.getDecisionComments(req.params.id);
    res.json(comments);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/decisions/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.addDecisionComment(req.params.id, req.body.member_name, req.body.text);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Rivalries
app.get('/api/rivalries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const rivalries = await db.getRivalries({ status: req.query.status }, req.session.user.id);
    res.json(rivalries);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/rivalries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.start_date) data.start_date = normalizeDate(data.start_date);
    if (data.end_date) data.end_date = normalizeDate(data.end_date);
    if (!data.group_id) {
      data.group_id = await db.getUserHouseholdId(req.session.user.id);
    }
    const result = await db.addRivalry(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/rivalries/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.start_date) data.start_date = normalizeDate(data.start_date);
    if (data.end_date) data.end_date = normalizeDate(data.end_date);
    await db.updateRivalry(req.params.id, data);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/rivalries/:id/entries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const entries = await db.getRivalryEntries(req.params.id);
    res.json(entries);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/rivalries/:id/entries', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const entry = { ...req.body, rivalry_id: Number(req.params.id) };
    await db.addRivalryEntry(entry);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/rivalries/leaderboard', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const rows = await db.getRivalryLeaderboard(req.session.user.id);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Gifts
app.get('/api/gifts/people', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const people = await db.getGiftPeople();
    res.json(people);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/gifts/people', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.addGiftPerson(req.body);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/gifts/ideas', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const ideas = await db.getGiftIdeas(req.query.person_id ? Number(req.query.person_id) : null);
    res.json(ideas);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/gifts/ideas', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.addGiftIdea(req.body);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/gifts/ideas/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.updateGiftIdea(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/gifts/ideas/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteGiftIdea(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/gifts/events', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const events = await db.getSpecialEvents();
    res.json(events);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/gifts/events', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const data = { ...req.body };
    if (data.date) data.date = normalizeDate(data.date);
    const result = await db.addSpecialEvent(data);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/gifts/events/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteSpecialEvent(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// ============================================
// Groups
// ============================================

app.get('/api/groups', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.json([]);
    const groups = await db.getGroupsByUser(userId);
    res.json(groups);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/groups', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const group = await db.createGroup({ ...req.body, created_by: userId });
    await db.addGroupMember(group.id, { user_id: userId, role: 'admin', added_by: userId });
    res.json({ success: true, id: group.id, invite_code: group.invite_code });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/groups/join', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const { invite_code } = req.body;
    const group = await db.getGroupByInviteCode(invite_code);
    if (!group) return res.status(404).json({ error: 'Invalid invite code' });
    await db.addGroupMember(group.id, { user_id: userId, role: 'member', added_by: userId });
    res.json({ success: true, group });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/groups/:id/leave', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const members = await db.getGroupMembers(req.params.id);
    const myMembership = members.find(m => m.user_id === userId);
    if (!myMembership) return res.status(404).json({ error: 'Not a member' });
    await db.removeGroupMember(req.params.id, myMembership.id);
    // If no members left, delete the group
    const remaining = members.filter(m => m.id !== myMembership.id);
    if (remaining.length === 0) {
      await db.deleteGroup(parseInt(req.params.id));
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/groups/:id/members', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const members = await db.getGroupMembers(req.params.id);
    res.json(members);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/groups/:id/members', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const result = await db.addGroupMember(req.params.id, { ...req.body, added_by: userId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/groups/:groupId/members/:memberId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.removeGroupMember(req.params.groupId, req.params.memberId);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/groups/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { name, description } = req.body;
    const fields = [];
    const params = [];
    if (name) { fields.push('name = ?'); params.push(name); }
    if (description !== undefined) { fields.push('description = ?'); params.push(description); }
    if (fields.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    params.push(req.params.id);
    await new Promise((resolve, reject) => {
      db.db.run(`UPDATE groups SET ${fields.join(', ')} WHERE id = ?`, params, (err) => err ? reject(err) : resolve());
    });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/groups/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteGroup(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// ============================================
// Contacts
// ============================================

app.get('/api/contacts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    if (!userId) return res.json([]);
    const contacts = await db.getContactsByUser(userId);
    res.json(contacts);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/contacts', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const result = await db.addContact({ ...req.body, added_by: userId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/contacts/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.updateContact(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/contacts/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteContact(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// ============================================
// Feed
// ============================================

app.get('/api/groups/:id/feed', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const posts = await db.getFeedPosts(req.params.id, {
      limit: parseInt(req.query.limit) || 50,
      before_id: req.query.before_id ? parseInt(req.query.before_id) : undefined
    });
    res.json(posts);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/groups/:id/feed', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const senderName = req.session.user?.name;
    const groupId = parseInt(req.params.id);
    const result = await db.addFeedPost({ ...req.body, group_id: groupId, author_id: userId });
    res.json({ success: true, id: result.id });
    // Push to group members (fire-and-forget)
    const preview = req.body.title || req.body.body || 'New post';
    push.pushToGroup(db, groupId, userId, senderName, preview, { type: 'feed', group_id: groupId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/feed/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteFeedPost(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/feed/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    await db.addFeedReaction(req.params.id, userId, req.body.reaction_type);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/feed/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    await db.removeFeedReaction(req.params.id, userId);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/feed/:id/reactions', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const reactions = await db.getFeedReactions(req.params.id);
    res.json(reactions);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/feed/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const comments = await db.getFeedComments(req.params.id);
    res.json(comments);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/feed/:id/comments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const result = await db.addFeedComment(req.params.id, userId, req.body.text);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Budget Projects
app.get('/api/projects', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const projects = await db.getProjects();
    res.json(projects);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/projects', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.addProject(req.body);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/projects/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteProject(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/projects/:id/expenses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const expenses = await db.getProjectExpenses(req.params.id);
    res.json(expenses);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/projects/:id/expenses', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.addProjectExpense(req.params.id, req.body);
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/projects/:projectId/expenses/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteProjectExpense(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Activity feed (unified home feed)
// ============================================
// Direct Messages
// ============================================

app.get('/api/messages/unread-count', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const count = await db.getUnreadCount(req.session.user.id);
    res.json({ count });
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.get('/api/messages', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const conversations = await db.getConversations(req.session.user.id);
    res.json(conversations);
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.get('/api/messages/:partnerId', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const messages = await db.getMessages(req.session.user.id, parseInt(req.params.partnerId), {
      limit: parseInt(req.query.limit) || 50,
      before_id: req.query.before_id ? parseInt(req.query.before_id) : undefined
    });
    res.json(messages);
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.get('/api/messages/:partnerId/:messageId/image', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const image = await db.getMessageImage(parseInt(req.params.messageId));
    if (!image) return res.status(404).json({ error: 'No image' });
    res.json({ image });
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.post('/api/messages', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const senderId = req.session.user.id;
    const senderName = req.session.user.name;
    const result = await db.sendMessage({
      sender_id: senderId,
      recipient_id: req.body.recipient_id,
      text: req.body.text,
      reference_type: req.body.reference_type,
      reference_id: req.body.reference_id,
      reference_title: req.body.reference_title,
      image_data: req.body.image_data
    });
    res.json({ success: true, id: result.id });
    // Push notification to recipient (fire-and-forget)
    const text = req.body.image_data ? 'Sent a photo' : (req.body.text || '');
    push.pushToUser(db, req.body.recipient_id, senderName, text, { type: 'message', sender_id: senderId });
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.post('/api/messages/:partnerId/read', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.markRead(req.session.user.id, parseInt(req.params.partnerId));
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.get('/api/activity', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const feed = await db.getActivityFeed(parseInt(req.query.limit) || 20, userId);
    res.json(feed);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// ============================================
// Admin diagnostic + manual fix
// ============================================

app.get('/api/admin/diagnostic', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const query = (sql, params = []) => new Promise((resolve, reject) => {
      db.db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
    });
    const users = await query('SELECT id, username, name FROM users');
    const groups = await query('SELECT * FROM groups');
    const members = await query(`SELECT gm.*, u.name as user_name, u.username
      FROM group_members gm LEFT JOIN users u ON u.id = gm.user_id`);
    const apptStats = await query(`SELECT group_id, COUNT(*) as count FROM appointments GROUP BY group_id`);
    const decisionStats = await query(`SELECT group_id, COUNT(*) as count FROM decisions GROUP BY group_id`);
    const totalAppts = await query('SELECT COUNT(*) as count FROM appointments');
    res.json({ users, groups, members, apptStats, decisionStats, totalAppts: totalAppts[0]?.count });
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

app.post('/api/admin/fix-household', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.runHouseholdMigrations();
    res.json({ success: true, message: 'Household migration completed' });
  } catch (err) { res.status(500).json({ error: err.message }); }
  finally { db.close(); }
});

// ============================================
// Lists
// ============================================

app.get('/api/lists', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const lists = await db.getLists(userId);
    res.json(lists);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/lists', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const result = await db.createList({ ...req.body, created_by: userId });
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.put('/api/lists/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.updateList(req.params.id, req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/lists/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteList(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/lists/:id/items', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const items = await db.getListItems(req.params.id);
    res.json(items);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/lists/:id/items', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userName = req.session.user?.name || req.session.user?.username;
    const result = await db.addListItem({ list_id: req.params.id, title: req.body.title, added_by: userName });
    res.json({ success: true, id: result.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.post('/api/lists/items/:id/toggle', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.toggleListItem(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.delete('/api/lists/items/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.deleteListItem(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// ============================================
// Coverage / Care Cascade
// ============================================

// Create a coverage request with windows and recipients
app.post('/api/coverage', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const { reason, note, windows, contact_ids } = req.body;

    // Create request
    const request = await db.createCoverageRequest({ requester_id: userId, reason, note });

    // Add windows (normalize dates)
    for (const w of (windows || [])) {
      const winData = { request_id: request.id, ...w };
      if (winData.window_date) winData.window_date = normalizeDate(winData.window_date);
      await db.addCoverageWindow(winData);
    }

    // Add recipients and generate invite tokens
    const recipients = [];
    for (const contactId of (contact_ids || [])) {
      const rec = await db.addCoverageRecipient({ request_id: request.id, contact_id: contactId });
      recipients.push(rec);
    }

    res.json({ success: true, id: request.id, recipients });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// List my coverage requests
app.get('/api/coverage', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const userId = req.session.user?.id;
    const requests = await db.getCoverageRequests(userId);
    res.json(requests);
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Get full details of a coverage request
app.get('/api/coverage/:id', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const request = await db.getCoverageRequestById(req.params.id);
    if (!request) return res.status(404).json({ error: 'Not found' });
    const windows = await db.getCoverageWindows(req.params.id);
    const recipients = await db.getCoverageRecipients(req.params.id);
    const approvals = await db.getCoverageApprovals(req.params.id);
    res.json({ ...request, windows, recipients, approvals });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Cancel a coverage request
app.post('/api/coverage/:id/cancel', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    await db.cancelCoverageRequest(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// PUBLIC: Approve coverage via invite token (no auth required — care team member uses link)
app.get('/api/coverage/approve/:token', async (req, res) => {
  const db = new FamilyDB();
  try {
    const recipient = await db.getRecipientByToken(req.params.token);
    if (!recipient) return res.status(404).json({ error: 'Invalid or expired link' });
    const windows = await db.getCoverageWindows(recipient.request_id);
    res.json({
      contact_name: recipient.contact_name,
      requester_name: recipient.requester_name,
      reason: recipient.reason,
      note: recipient.note,
      request_id: recipient.request_id,
      recipient_id: recipient.id,
      status: recipient.status,
      windows
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// PUBLIC: Submit approval (care team member confirms a window)
app.post('/api/coverage/approve/:token', async (req, res) => {
  const db = new FamilyDB();
  try {
    const recipient = await db.getRecipientByToken(req.params.token);
    if (!recipient) return res.status(404).json({ error: 'Invalid or expired link' });
    if (recipient.status === 'approved') return res.status(409).json({ error: 'Already approved' });

    const { window_id, approved_date, approved_start, approved_end, helper_note } = req.body;

    await db.approveCoverage({
      request_id: recipient.request_id,
      recipient_id: recipient.id,
      window_id,
      approved_date: approved_date ? normalizeDate(approved_date) : null,
      approved_start,
      approved_end,
      helper_note
    });

    res.json({ success: true, message: 'Coverage confirmed' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// Initialize database on startup — runs full schema.sql with proper async handling
async function initializeDatabase() {
  const db = new FamilyDB();
  try {
    await db.initSchema();
    await db.runHouseholdMigrations();
    console.log('✅ Database initialized with full schema + household isolation');
  } catch (err) {
    console.error('❌ Database init error:', err.message);
  } finally {
    db.close();
  }
}

// Start server after DB init
initializeDatabase().then(() => {
  app.listen(PORT, () => {
    console.log('Kinrows running on port', PORT);
    console.log('AI features:', process.env.ANTHROPIC_API_KEY ? 'ENABLED' : 'DISABLED (no ANTHROPIC_API_KEY)');
  });
});
