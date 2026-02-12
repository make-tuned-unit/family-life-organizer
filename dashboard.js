const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const path = require('path');
const FamilyDB = require('./database');

const app = express();
const PORT = process.env.PORT || 3456;

// Users config
const USERS = {
  'jesse': { password: 'lauft2024', name: 'Jesse', avatar: '👨‍💼' },
  'sophie': { password: 'family2024', name: 'Sophie', avatar: '👩‍⚕️' }
};

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(session({
  secret: 'family-life-secret-key',
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
    res.redirect('/login');
  }
}

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

// Login POST
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  const user = USERS[username];
  if (user && user.password === password) {
    req.session.user = { username, name: user.name, avatar: user.avatar };
    res.redirect('/');
  } else {
    res.redirect('/login?error=1');
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
    const summary = await db.getDailySummary();
    const groceries = await db.getGroceries('needed');
    const tasks = await db.getTasks({ status: 'active' });
    const appointments = await db.getAppointments();
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
              <div class="stat-value">${summary.appointments_today}</div>
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
        <div class="card-header">
          <h3 class="card-title">Upcoming Appointments</h3>
        </div>
        <div class="card-body">
          ${appointments
            .filter(a => a.appointment_date >= today)
            .sort((a, b) => a.appointment_date.localeCompare(b.appointment_date))
            .slice(0, 10)
            .map(appt => `
              <div class="list-item">
                <div class="list-content">
                  <strong>${appt.title}</strong>
                  <div style="color:var(--gray-500);font-size:13px;margin-top:2px">
                    ${appt.appointment_date} ${appt.appointment_time ? 'at ' + appt.appointment_time : ''}
                    ${appt.location ? '• ' + appt.location : ''}
                  </div>
                  ${appt.person_tags ? `<div style="margin-top:6px">${appt.person_tags.split(',').map(p => `<span class="badge" style="margin-right:4px">${p}</span>`).join('')}</div>` : ''}
                </div>
              </div>
            `).join('') || '<p style="color:var(--gray-600);text-align:center;padding:32px">No upcoming appointments</p>'}
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
            📧 Forward receipts to: <strong>jhenrymalcolm@gmail.com</strong>
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
      const title = document.getElementById('apptTitle').value;
      const date = document.getElementById('apptDate').value;
      const time = document.getElementById('apptTime').value;
      const location = document.getElementById('apptLocation').value;
      const personCheckboxes = document.querySelectorAll('.appt-person:checked');
      const person_tags = Array.from(personCheckboxes).map(cb => cb.value);
      
      if (!title || !date) {
        alert('Please enter a title and date');
        return;
      }
      
      await fetch('/api/appointments', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          title, 
          appointment_date: date,
          appointment_time: time,
          location: location,
          person_tags: person_tags
        })
      });
      location.reload();
    }
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
      await db.addGrocery(data);
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
      await db.completeGrocery(id);
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
    const summary = await db.getDailySummary();
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
    await db.addAppointment(req.body);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

app.listen(PORT, () => {
  console.log('Family Life Organizer running on port', PORT);
});