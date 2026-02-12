# Family Life Organizer

**Status:** MVP Built ✅  
**Cost:** Local processing only (no API calls)  
**Database:** SQLite (file-based, zero config)

---

## What It Does

Turns natural language texts into organized household data:

```
"Add eggs, milk, and bread to groceries"
→ ✅ Added to groceries: eggs, milk, bread

"Remind me about car tire rotation in March"  
→ ✅ Added to automotive: car tire rotation (due March)

"Book dentist appointment for Liam in April"
→ ✅ Added to appointments: dentist appointment for Liam
```

---

## Components Built

### 1. Database (`database.js`)
SQLite database with tables for:
- **tasks** — All to-dos with categories, due dates, priorities
- **groceries** — Shopping lists with categories
- **appointments** — Scheduled events with reminders
- **memory** — Long-term knowledge (car history, warranties, preferences)
- **health** — Metrics tracking (steps, sleep, hydration)
- **automations** — Recurring tasks and schedules
- **message_log** — History of all parsed messages

### 2. NLP Parser (`parser.js`)
Rule-based parser (no API calls) that detects:
- **12 categories:** groceries, appointments, home, automotive, travel, finances, recipes, childcare, dates, health, family, reminders
- **Actions:** add, complete, list, delete, remind, schedule
- **Dates:** today, tomorrow, next week, in X days, month names
- **Times:** at 3pm, at 14:00
- **Priority:** urgent → high, important → medium
- **Recurrence:** daily, weekly, monthly, yearly
- **Assignee:** wife, me

### 3. CLI (`cli.js`)
Command-line interface:
```bash
node cli.js "Add milk to groceries"
node cli.js "List groceries"
node cli.js --summary
```

### 4. Web Dashboard (`dashboard.js`)
Interactive web interface for both users:
```bash
node dashboard.js
```
Then open http://localhost:3456

**Features:**
- Login for Jesse and wife (separate accounts)
- Overview with summary cards
- Grocery list with add/complete
- Task management by category
- Add new items via web form
- Mobile-responsive design
- Real-time updates

---

## Usage Examples

### Groceries
```bash
node cli.js "Add eggs, yogurt, and blueberries to groceries"
node cli.js "Buy milk and bread"
node cli.js --list groceries
```

### Tasks & Reminders
```bash
node cli.js "Remind me about tire rotation in March"
node cli.js "Schedule dentist appointment for Liam in April"
node cli.js "Clean the garage this weekend"
```

### Daily Summary
```bash
node cli.js --summary
```

### Web Dashboard
```bash
node dashboard.js
# Open http://localhost:3456
# Login: jesse / REDACTED-PASSWORD  or  wife / REDACTED-PASSWORD
```

**Dashboard Tabs:**
- 📊 **Overview** — Summary cards and tasks by category
- 🛒 **Groceries** — Full shopping list, add items, categorize
- 📋 **Tasks** — All tasks organized by category
- ➕ **Add New** — Create new tasks with categories and due dates

---

## Database Location

```
~/.openclaw/workspace/vault/family-life/family.db
```

---

## Next Features to Add

1. **Cron reminders** — Daily check for due tasks
2. **Slack/WhatsApp integration** — Respond to DMs
3. **Health tracking** — Log steps, sleep, water
4. **Knowledge base** — Store car service history, warranties
5. **Automations** — "Every Sunday send meal plan"
6. **Shared calendar view** — Visual calendar of appointments

---

## Testing

```bash
cd projects/family-life-organizer
node parser.js  # Run parser tests
node cli.js "your message here"  # Process a message
node cli.js --summary  # Get daily summary
node dashboard.js  # Start web dashboard
```

---

*Built by Henry — local, fast, budget-friendly*
