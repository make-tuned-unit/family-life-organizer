const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const path = require('path');
const FamilyDB = require('./database');

const app = express();
const PORT = process.env.PORT || 3456;

// Simple auth middleware
const USERS = {
  'jesse': { password: 'lauft2024', name: 'Jesse' },
  'wife': { password: 'family2024', name: 'Wife' }
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

// Static files
app.use(express.static(path.join(__dirname, 'public')));

// Auth middleware
function requireAuth(req, res, next) {
  if (req.session.user) {
    next();
  } else {
    res.redirect('/login');
  }
}

// Routes

// Login page
app.get('/login', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Family Life Organizer - Login</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .login-box {
          background: white;
          padding: 40px;
          border-radius: 16px;
          box-shadow: 0 20px 60px rgba(0,0,0,0.3);
          width: 100%;
          max-width: 400px;
        }
        h1 { color: #333; margin-bottom: 8px; font-size: 28px; }
        p.subtitle { color: #666; margin-bottom: 30px; }
        .form-group { margin-bottom: 20px; }
        label { display: block; margin-bottom: 8px; color: #555; font-weight: 500; }
        input {
          width: 100%;
          padding: 12px;
          border: 2px solid #e0e0e0;
          border-radius: 8px;
          font-size: 16px;
          transition: border-color 0.3s;
        }
        input:focus { outline: none; border-color: #667eea; }
        button {
          width: 100%;
          padding: 14px;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          border: none;
          border-radius: 8px;
          font-size: 16px;
          font-weight: 600;
          cursor: pointer;
          transition: transform 0.2s;
        }
        button:hover { transform: translateY(-2px); }
        .error {
          color: #e74c3c;
          margin-top: 15px;
          text-align: center;
        }
      </style>
    </head>
    <body>
      <div class="login-box">
        <h1>🏠 Family Life</h1>
        <p class="subtitle">Organize your household together</p>
        <form method="POST" action="/login">
          <div class="form-group">
            <label>Username</label>
            <input type="text" name="username" placeholder="jesse or wife" required>
          </div>
          <div class="form-group">
            <label>Password</label>
            <input type="password" name="password" placeholder="Enter password" required>
          </div>
          <button type="submit">Sign In</button>
        </form>
        ${req.query.error ? '<p class="error">Invalid credentials</p>' : ''}
      </div>
    </body>
    </html>
  `);
});

// Login POST
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  const user = USERS[username];
  
  if (user && user.password === password) {
    req.session.user = { username, name: user.name };
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

// Main dashboard
app.get('/', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  
  try {
    const summary = await db.getDailySummary();
    const groceries = await db.getGroceries('needed');
    const tasks = await db.getTasks({ status: 'active' });
    
    // Group tasks by category
    const tasksByCategory = {};
    for (const task of tasks) {
      if (!tasksByCategory[task.category]) {
        tasksByCategory[task.category] = [];
      }
      tasksByCategory[task.category].push(task);
    }
    
    res.send(renderDashboard(req.session.user, summary, groceries, tasksByCategory));
  } catch (err) {
    console.error(err);
    res.status(500).send('Error loading dashboard');
  } finally {
    db.close();
  }
});

// API: Add item
app.post('/api/add', requireAuth, async (req, res) => {
  const { type, data } = req.body;
  const db = new FamilyDB();
  
  try {
    let result;
    if (type === 'grocery') {
      result = await db.addGrocery(data.item, data.category, data.quantity);
    } else if (type === 'task') {
      result = await db.addTask(data);
    }
    res.json({ success: true, result });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  } finally {
    db.close();
  }
});

// API: Complete item
app.post('/api/complete', requireAuth, async (req, res) => {
  const { type, id } = req.body;
  const db = new FamilyDB();
  
  try {
    if (type === 'task') {
      await db.completeTask(id);
    } else if (type === 'grocery') {
      await db.purchaseGrocery(id);
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  } finally {
    db.close();
  }
});

// API: Get data
app.get('/api/data', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  
  try {
    const [summary, groceries, tasks] = await Promise.all([
      db.getDailySummary(),
      db.getGroceries('needed'),
      db.getTasks({ status: 'active' })
    ]);
    
    res.json({ summary, groceries, tasks });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

// API: Appointments
app.post('/api/appointments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const result = await db.addAppointment(req.body);
    res.json({ success: true, result });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  } finally {
    db.close();
  }
});

app.get('/api/appointments', requireAuth, async (req, res) => {
  const db = new FamilyDB();
  try {
    const { year, month, person } = req.query;
    let appointments;
    if (year && month) {
      appointments = await db.getAppointmentsByMonth(parseInt(year), parseInt(month));
    } else if (person) {
      appointments = await db.getAppointments({ person });
    } else {
      appointments = await db.getAppointments();
    }
    res.json({ success: true, appointments });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    db.close();
  }
});

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

function renderDashboard(user, summary, groceries, tasksByCategory) {
  const categories = Object.keys(tasksByCategory).sort();
  
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <meta name="theme-color" content="#667eea">
      <meta name="apple-mobile-web-app-capable" content="yes">
      <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
      <meta name="apple-mobile-web-app-title" content="FamilyLife">
      <meta name="description" content="Organize your household together">
      <link rel="manifest" href="/manifest.json">
      <link rel="apple-touch-icon" href="/icon-192x192.png">
      <title>Family Life Organizer</title>
      <script>
        // Register Service Worker
        if ('serviceWorker' in navigator) {
          window.addEventListener('load', () => {
            navigator.serviceWorker.register('/sw.js')
              .then((registration) => {
                console.log('SW registered:', registration.scope);
              })
              .catch((error) => {
                console.log('SW registration failed:', error);
              });
          });
        }
      </script>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: #f5f7fa;
          color: #333;
          line-height: 1.6;
        }
        .header {
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          padding: 20px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header-content {
          max-width: 1200px;
          margin: 0 auto;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .header h1 { font-size: 24px; }
        .header .user { opacity: 0.9; }
        .header a { color: white; text-decoration: none; margin-left: 20px; }
        
        .container {
          max-width: 1200px;
          margin: 0 auto;
          padding: 20px;
        }
        
        .summary-cards {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 20px;
          margin-bottom: 30px;
        }
        .card {
          background: white;
          padding: 20px;
          border-radius: 12px;
          box-shadow: 0 2px 8px rgba(0,0,0,0.08);
          text-align: center;
        }
        .card-number {
          font-size: 36px;
          font-weight: bold;
          color: #667eea;
        }
        .card-label {
          color: #666;
          font-size: 14px;
          margin-top: 5px;
        }
        
        .section {
          background: white;
          border-radius: 12px;
          padding: 20px;
          margin-bottom: 20px;
          box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }
        .section h2 {
          font-size: 20px;
          margin-bottom: 15px;
          color: #333;
        }
        
        .add-form {
          display: flex;
          gap: 10px;
          margin-bottom: 20px;
        }
        .add-form input, .add-form select {
          padding: 10px;
          border: 2px solid #e0e0e0;
          border-radius: 8px;
          font-size: 14px;
        }
        .add-form input { flex: 1; }
        .add-form button {
          padding: 10px 20px;
          background: #667eea;
          color: white;
          border: none;
          border-radius: 8px;
          cursor: pointer;
        }
        
        .item-list {
          list-style: none;
        }
        .item {
          display: flex;
          align-items: center;
          padding: 12px;
          border-bottom: 1px solid #f0f0f0;
          transition: background 0.2s;
        }
        .item:hover { background: #f9f9f9; }
        .item:last-child { border-bottom: none; }
        .item-checkbox {
          width: 20px;
          height: 20px;
          margin-right: 12px;
          cursor: pointer;
        }
        .item-text { flex: 1; }
        .item-category {
          font-size: 12px;
          color: #666;
          background: #f0f0f0;
          padding: 4px 10px;
          border-radius: 20px;
          margin-left: 10px;
        }
        
        .category-section {
          margin-bottom: 30px;
        }
        .category-title {
          font-size: 18px;
          color: #667eea;
          margin-bottom: 10px;
          text-transform: capitalize;
        }
        
        .tabs {
          display: flex;
          gap: 10px;
          margin-bottom: 20px;
          border-bottom: 2px solid #e0e0e0;
        }
        .tab {
          padding: 10px 20px;
          cursor: pointer;
          border-bottom: 2px solid transparent;
          margin-bottom: -2px;
        }
        .tab.active {
          border-bottom-color: #667eea;
          color: #667eea;
        }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        
        /* Calendar Styles */
        .calendar-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 20px;
        }
        .calendar-nav {
          display: flex;
          gap: 10px;
          align-items: center;
        }
        .calendar-nav button {
          padding: 8px 16px;
          background: #667eea;
          color: white;
          border: none;
          border-radius: 6px;
          cursor: pointer;
        }
        .calendar-grid {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 1px;
          background: #e0e0e0;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          overflow: hidden;
        }
        .calendar-day-header {
          background: #f5f5f5;
          padding: 10px;
          text-align: center;
          font-weight: 600;
          font-size: 12px;
          text-transform: uppercase;
        }
        .calendar-day {
          background: white;
          min-height: 100px;
          padding: 8px;
          position: relative;
        }
        .calendar-day.other-month {
          background: #fafafa;
          color: #999;
        }
        .calendar-day-number {
          font-weight: 600;
          margin-bottom: 4px;
        }
        .calendar-day.today .calendar-day-number {
          background: #667eea;
          color: white;
          width: 28px;
          height: 28px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .calendar-event {
          font-size: 11px;
          padding: 2px 6px;
          margin: 2px 0;
          border-radius: 4px;
          cursor: pointer;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .person-tag {
          display: inline-block;
          width: 8px;
          height: 8px;
          border-radius: 50%;
          margin-right: 4px;
        }
        .person-jesse { background: #667eea; }
        .person-sophie { background: #f093fb; }
        .person-rowan { background: #4facfe; }
        .person-baby { background: #43e97b; }
        .person-filter {
          display: flex;
          gap: 15px;
          margin-bottom: 20px;
          flex-wrap: wrap;
        }
        .person-filter label {
          display: flex;
          align-items: center;
          gap: 6px;
          cursor: pointer;
        }
        .appointment-form {
          background: #f9f9f9;
          padding: 20px;
          border-radius: 8px;
          margin-bottom: 20px;
        }
        
        @media (max-width: 768px) {
          .summary-cards { grid-template-columns: repeat(2, 1fr); }
          .add-form { flex-direction: column; }
          .calendar-day { min-height: 60px; font-size: 12px; }
          .calendar-event { font-size: 9px; }
        }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="header-content">
          <div>
            <h1>🏠 Family Life Organizer</h1>
            <span class="user">Welcome, ${user.name}</span>
          </div>
          <div>
            <a href="/">Dashboard</a>
            <a href="/logout">Logout</a>
          </div>
        </div>
      </div>
      
      <div class="container">
        <div class="summary-cards">
          <div class="card">
            <div class="card-number">${summary.tasks_today}</div>
            <div class="card-label">Tasks Today</div>
          </div>
          <div class="card">
            <div class="card-number">${summary.appointments_today}</div>
            <div class="card-label">Appointments</div>
          </div>
          <div class="card">
            <div class="card-number">${summary.groceries_needed}</div>
            <div class="card-label">Groceries Needed</div>
          </div>
          <div class="card">
            <div class="card-number">${summary.overdue_tasks}</div>
            <div class="card-label">Overdue</div>
          </div>
        </div>
        
        <div class="tabs">
          <div class="tab active" onclick="showTab('overview')">Overview</div>
          <div class="tab" onclick="showTab('calendar')">📅 Calendar</div>
          <div class="tab" onclick="showTab('groceries')">🛒 Groceries</div>
          <div class="tab" onclick="showTab('tasks')">📋 Tasks</div>
          <div class="tab" onclick="showTab('add')">➕ Add New</div>
        </div>
        
        <div id="overview" class="tab-content active">
          <div class="section">
            <h2>Your Household at a Glance</h2>
            <p style="color: #666; margin-bottom: 20px;">
              ${summary.tasks_today === 0 && summary.groceries_needed === 0 
                ? "Great job! You're all caught up. 🎉" 
                : "Here's what needs attention today."}
            </p>
            
            ${categories.map(cat => `
              <div class="category-section">
                <h3 class="category-title">${cat}</h3>
                <ul class="item-list">
                  ${tasksByCategory[cat].slice(0, 3).map(task => `
                    <li class="item">
                      <input type="checkbox" class="item-checkbox" onchange="completeTask(${task.id})">
                      <span class="item-text">${task.title}</span>
                      ${task.due_date ? `<span style="color: #999; font-size: 12px;">Due: ${task.due_date}</span>` : ''}
                    </li>
                  `).join('')}
                  ${tasksByCategory[cat].length > 3 ? `<li style="padding: 10px; color: #667eea; cursor: pointer;">+ ${tasksByCategory[cat].length - 3} more...</li>` : ''}
                </ul>
              </div>
            `).join('')}
          </div>
        </div>
        
        <div id="calendar" class="tab-content">
          <div class="section">
            <h2>📅 Family Calendar</h2>
            
            <div class="appointment-form">
              <h3>Add Appointment/Event</h3>
              <div class="add-form" style="flex-direction: column;">
                <input type="text" id="apptTitle" placeholder="Event title (e.g., Dentist, School play)">
                <input type="date" id="apptDate">
                <input type="time" id="apptTime">
                <input type="text" id="apptLocation" placeholder="Location (optional)">
                <div style="display: flex; gap: 15px; flex-wrap: wrap;">
                  <label><input type="checkbox" class="person-check" value="Jesse"> <span class="person-tag person-jesse"></span>Jesse</label>
                  <label><input type="checkbox" class="person-check" value="Sophie"> <span class="person-tag person-sophie"></span>Sophie</label>
                  <label><input type="checkbox" class="person-check" value="Rowan"> <span class="person-tag person-rowan"></span>Rowan</label>
                  <label><input type="checkbox" class="person-check" value="Baby"> <span class="person-tag person-baby"></span>Baby</label>
                </div>
                <button onclick="addAppointment()">Add to Calendar</button>
              </div>
            </div>
            
            <div class="person-filter">
              <label><input type="checkbox" id="filter-all" checked onchange="loadCalendar()"> Show All</label>
              <label><input type="checkbox" class="filter-person" value="Jesse" onchange="loadCalendar()"> <span class="person-tag person-jesse"></span>Jesse</label>
              <label><input type="checkbox" class="filter-person" value="Sophie" onchange="loadCalendar()"> <span class="person-tag person-sophie"></span>Sophie</label>
              <label><input type="checkbox" class="filter-person" value="Rowan" onchange="loadCalendar()"> <span class="person-tag person-rowan"></span>Rowan</label>
              <label><input type="checkbox" class="filter-person" value="Baby" onchange="loadCalendar()"> <span class="person-tag person-baby"></span>Baby</label>
            </div>
            
            <div class="calendar-header">
              <div class="calendar-nav">
                <button onclick="changeMonth(-1)">← Prev</button>
                <h3 id="calendarMonthYear">Loading...</h3>
                <button onclick="changeMonth(1)">Next →</button>
              </div>
              <button onclick="goToToday()">Today</button>
            </div>
            
            <div class="calendar-grid" id="calendarGrid">
              <!-- Calendar generated by JS -->
            </div>
          </div>
        </div>
        
        <div id="groceries" class="tab-content">
          <div class="section">
            <h2>🛒 Grocery List</h2>
            <div class="add-form">
              <input type="text" id="groceryInput" placeholder="Add item (e.g., eggs, milk)...">
              <select id="groceryCategory">
                <option value="">Category</option>
                <option value="produce">Produce</option>
                <option value="dairy">Dairy</option>
                <option value="meat">Meat</option>
                <option value="pantry">Pantry</option>
                <option value="frozen">Frozen</option>
                <option value="other">Other</option>
              </select>
              <button onclick="addGrocery()">Add</button>
            </div>
            <ul class="item-list" id="groceryList">
              ${groceries.map(item => `
                <li class="item">
                  <input type="checkbox" class="item-checkbox" onchange="completeGrocery(${item.id})">
                  <span class="item-text">${item.item}</span>
                  ${item.category ? `<span class="item-category">${item.category}</span>` : ''}
                </li>
              `).join('')}
              ${groceries.length === 0 ? '<li style="padding: 20px; color: #999; text-align: center;">No items needed</li>' : ''}
            </ul>
          </div>
        </div>
        
        <div id="tasks" class="tab-content">
          <div class="section">
            <h2>📋 All Tasks</h2>
            ${categories.map(cat => `
              <div class="category-section">
                <h3 class="category-title">${cat}</h3>
                <ul class="item-list">
                  ${tasksByCategory[cat].map(task => `
                    <li class="item">
                      <input type="checkbox" class="item-checkbox" onchange="completeTask(${task.id})">
                      <span class="item-text">${task.title}</span>
                      ${task.due_date ? `<span style="color: #999; font-size: 12px; margin-left: 10px;">${task.due_date}</span>` : ''}
                    </li>
                  `).join('')}
                </ul>
              </div>
            `).join('')}
          </div>
        </div>
        
        <div id="add" class="tab-content">
          <div class="section">
            <h2>➕ Add New Item</h2>
            <div class="add-form" style="flex-direction: column;">
              <input type="text" id="newTaskTitle" placeholder="What needs to be done?">
              <select id="newTaskCategory">
                <option value="">Select category...</option>
                <option value="groceries">Groceries</option>
                <option value="appointments">Appointments</option>
                <option value="home">Home</option>
                <option value="automotive">Automotive</option>
                <option value="travel">Travel</option>
                <option value="finances">Finances</option>
                <option value="childcare">Childcare</option>
                <option value="dates">Dates</option>
                <option value="health">Health</option>
                <option value="family">Family</option>
                <option value="reminders">Reminders</option>
              </select>
              <input type="date" id="newTaskDate">
              <button onclick="addTask()">Add Task</button>
            </div>
          </div>
        </div>
      </div>
      
      <script>
        function showTab(tabName) {
          document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
          document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
          event.target.classList.add('active');
          document.getElementById(tabName).classList.add('active');
          if (tabName === 'calendar') {
            loadCalendar();
          }
        }
        
        function showError(message) {
          alert('Error: ' + message);
        }
        
        async function addGrocery() {
          const input = document.getElementById('groceryInput');
          const category = document.getElementById('groceryCategory');
          const item = input.value.trim();
          const btn = event.target;
          
          if (!item) {
            showError('Please enter an item');
            return;
          }
          
          btn.disabled = true;
          btn.textContent = 'Adding...';
          
          try {
            const response = await fetch('/api/add', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                type: 'grocery',
                data: { item, category: category.value }
              })
            });
            
            if (response.ok) {
              input.value = '';
              category.value = '';
              btn.disabled = false;
              btn.textContent = 'Add';
              await refreshGroceryList();
            } else {
              const err = await response.text();
              showError('Failed to add: ' + err);
              btn.disabled = false;
              btn.textContent = 'Add';
            }
          } catch (err) {
            showError('Network error: ' + err.message);
            btn.disabled = false;
            btn.textContent = 'Add';
          }
        }
        
        async function refreshGroceryList() {
          try {
            const response = await fetch('/api/data');
            const data = await response.json();
            
            const list = document.getElementById('groceryList');
            if (data.groceries.length === 0) {
              list.innerHTML = '<li style="padding: 20px; color: #999; text-align: center;">No items needed</li>';
            } else {
              list.innerHTML = data.groceries.map(item => 
                '<li class="item">' +
                  '<input type="checkbox" class="item-checkbox" onchange="completeGrocery(' + item.id + ')">' +
                  '<span class="item-text">' + item.item + '</span>' +
                  (item.category ? '<span class="item-category">' + item.category + '</span>' : '') +
                '</li>'
              ).join('');
            }
            
            // Update summary card
            const summaryCards = document.querySelectorAll('.card-number');
            if (summaryCards[2]) {
              summaryCards[2].textContent = data.summary.groceries_needed;
            }
          } catch (err) {
            showError('Failed to refresh list: ' + err.message);
          }
        }
        
        async function completeGrocery(id) {
          try {
            await fetch('/api/complete', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ type: 'grocery', id })
            });
            await refreshGroceryList();
          } catch (err) {
            showError('Failed to complete: ' + err.message);
          }
        }
        
        async function addTask() {
          const title = document.getElementById('newTaskTitle').value;
          const category = document.getElementById('newTaskCategory').value;
          const due_date = document.getElementById('newTaskDate').value;
          const btn = event.target;
          
          if (!title) {
            showError('Please enter a title');
            return;
          }
          if (!category) {
            showError('Please select a category');
            return;
          }
          
          btn.disabled = true;
          btn.textContent = 'Adding...';
          
          try {
            const response = await fetch('/api/add', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                type: 'task',
                data: { title, category, due_date }
              })
            });
            
            if (response.ok) {
              location.reload();
            } else {
              const err = await response.text();
              showError('Failed to add: ' + err);
              btn.disabled = false;
              btn.textContent = 'Add Task';
            }
          } catch (err) {
            showError('Network error: ' + err.message);
            btn.disabled = false;
            btn.textContent = 'Add Task';
          }
        }
        
        async function completeTask(id) {
          try {
            await fetch('/api/complete', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ type: 'task', id })
            });
            location.reload();
          } catch (err) {
            showError('Failed to complete: ' + err.message);
          }
        }
        
        // Calendar functions
        let currentCalendarDate = new Date();
        let calendarAppointments = [];
        
        function getMonthName(month) {
          const names = ['January', 'February', 'March', 'April', 'May', 'June',
                         'July', 'August', 'September', 'October', 'November', 'December'];
          return names[month];
        }
        
        function getDayName(day) {
          const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
          return names[day];
        }
        
        async function loadCalendar() {
          const year = currentCalendarDate.getFullYear();
          const month = currentCalendarDate.getMonth();
          
          document.getElementById('calendarMonthYear').textContent = 
            getMonthName(month) + ' ' + year;
          
          try {
            const response = await fetch('/api/appointments?year=' + year + '&month=' + (month + 1));
            const data = await response.json();
            calendarAppointments = data.appointments || [];
            renderCalendar(year, month);
          } catch (err) {
            showError('Failed to load calendar: ' + err.message);
          }
        }
        
        function renderCalendar(year, month) {
          const firstDay = new Date(year, month, 1);
          const lastDay = new Date(year, month + 1, 0);
          const startPadding = firstDay.getDay();
          const daysInMonth = lastDay.getDate();
          
          const prevMonthLastDay = new Date(year, month, 0).getDate();
          const today = new Date();
          
          // Get selected filters
          const showAll = document.getElementById('filter-all').checked;
          const selectedPersons = showAll ? [] : 
            Array.from(document.querySelectorAll('.filter-person:checked')).map(cb => cb.value);
          
          let html = '';
          
          // Day headers
          for (let i = 0; i < 7; i++) {
            html += '<div class="calendar-day-header">' + getDayName(i) + '</div>';
          }
          
          // Previous month padding
          for (let i = startPadding - 1; i >= 0; i--) {
            html += '<div class="calendar-day other-month">' + (prevMonthLastDay - i) + '</div>';
          }
          
          // Current month days
          for (let day = 1; day <= daysInMonth; day++) {
            const dateStr = year + '-' + String(month + 1).padStart(2, '0') + '-' + String(day).padStart(2, '0');
            const isToday = today.getFullYear() === year && today.getMonth() === month && today.getDate() === day;
            
            // Find appointments for this day
            let dayEvents = calendarAppointments.filter(a => a.appointment_date === dateStr);
            
            // Filter by person if needed
            if (selectedPersons.length > 0) {
              dayEvents = dayEvents.filter(a => {
                if (!a.person_tags) return false;
                return selectedPersons.some(p => a.person_tags.includes(p));
              });
            }
            
            html += '<div class="calendar-day' + (isToday ? ' today' : '') + '">';
            html += '<div class="calendar-day-number">' + day + '</div>';
            
            dayEvents.slice(0, 3).forEach(event => {
              const time = event.appointment_time ? event.appointment_time.substring(0, 5) + ' ' : '';
              let tagsHtml = '';
              if (event.person_tags) {
                event.person_tags.split(',').forEach(tag => {
                  const colorClass = 'person-' + tag.toLowerCase();
                  tagsHtml += '<span class="person-tag ' + colorClass + '"></span>';
                });
              }
              html += '<div class="calendar-event" style="background: #e8f0fe;" onclick="deleteAppointment(' + event.id + ')">';
              html += tagsHtml + time + event.title;
              html += '</div>';
            });
            
            if (dayEvents.length > 3) {
              html += '<div style="font-size: 10px; color: #999;">+' + (dayEvents.length - 3) + ' more</div>';
            }
            
            html += '</div>';
          }
          
          // Next month padding
          const endPadding = (7 - ((startPadding + daysInMonth) % 7)) % 7;
          for (let i = 1; i <= endPadding; i++) {
            html += '<div class="calendar-day other-month">' + i + '</div>';
          }
          
          document.getElementById('calendarGrid').innerHTML = html;
        }
        
        function changeMonth(delta) {
          currentCalendarDate.setMonth(currentCalendarDate.getMonth() + delta);
          loadCalendar();
        }
        
        function goToToday() {
          currentCalendarDate = new Date();
          loadCalendar();
        }
        
        async function addAppointment() {
          const title = document.getElementById('apptTitle').value;
          const date = document.getElementById('apptDate').value;
          const time = document.getElementById('apptTime').value;
          const location = document.getElementById('apptLocation').value;
          
          if (!title || !date) {
            showError('Please enter a title and date');
            return;
          }
          
          const persons = Array.from(document.querySelectorAll('.person-check:checked')).map(cb => cb.value);
          
          try {
            const response = await fetch('/api/appointments', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                title,
                appointment_date: date,
                appointment_time: time || null,
                location: location || null,
                person_tags: persons
              })
            });
            
            if (response.ok) {
              document.getElementById('apptTitle').value = '';
              document.getElementById('apptDate').value = '';
              document.getElementById('apptTime').value = '';
              document.getElementById('apptLocation').value = '';
              document.querySelectorAll('.person-check').forEach(cb => cb.checked = false);
              await loadCalendar();
            } else {
              showError('Failed to add appointment');
            }
          } catch (err) {
            showError('Error adding appointment: ' + err.message);
          }
        }
        
        async function deleteAppointment(id) {
          if (!confirm('Delete this appointment?')) return;
          
          try {
            await fetch('/api/appointments/' + id, { method: 'DELETE' });
            await loadCalendar();
          } catch (err) {
            showError('Failed to delete: ' + err.message);
          }
        }
        
        // Load calendar when tab is shown
        document.addEventListener('DOMContentLoaded', function() {
          // Check if we're on calendar tab
          const calendarTab = document.querySelector('[onclick="showTab(\'calendar\')"]');
          if (calendarTab && calendarTab.classList.contains('active')) {
            loadCalendar();
          }
        });
      </script>
    </body>
    </html>
  `;
}

app.listen(PORT, () => {
  console.log(`Family Life Organizer dashboard running at http://localhost:${PORT}`);
  console.log('Login with: jesse / lauft2024  or  wife / family2024');
});
