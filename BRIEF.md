# Family Life Organizer — Project Brief

**Status:** Active Development  
**Priority:** High  
**Type:** Personal/Household Management System

---

## Overview

The Family Life Organizer is a unified personal and household management system powered by Henry. It enables Jesse and his wife to manage all aspects of family life through natural language texting via Slack, iMessage, or WhatsApp.

Henry captures, categorizes, schedules, reminds, and analyzes all inputs, acting as a proactive household operations assistant.

---

## Core Use Cases

- Life reminders
- Appointments (medical, personal, school, daycare)
- Groceries
- Home repair & maintenance
- Bills & financial reminders
- Car maintenance & service history
- Travel & trip planning
- Date nights & family scheduling
- Childcare coordination
- Recipes & meal planning
- Health & wellness tracking
- Family-related information management

---

## System Inputs

Text messages sent to Henry such as:

- "Add eggs, yogurt, and blueberries to groceries."
- "Remind me about car tire rotation in March."
- "Book a dentist appointment for Liam in April."
- "Collect trip ideas for May long weekend."
- "Track my steps and hydration this week."

**Workflow:** Henry parses messages → creates structured entries → files them into the correct category.

---

## Categories

1. **Appointments**
2. **Groceries**
3. **Home**
4. **Automotive**
5. **Travel**
6. **Finances / Bills**
7. **Recipes**
8. **Childcare**
9. **Dates & Family Time**
10. **Health**
11. **Family**
12. **General Reminders**

---

## Smart Features

### 1. Contextual Understanding

Henry infers:
- Priority
- Deadlines
- Location relevance
- Recurrence
- Links between items (e.g., "oil change" + "trip to Cape Breton")

### 2. Automated Scheduling

Henry proactively:
- Suggests times for tasks
- Detects conflicts
- Identifies optimal days for errands based on routines

### 3. Intelligent Reminders

Dynamic reminders based on:
- Proximity (geo-based optional)
- Habit patterns
- Weather (e.g., lawn care, car washing)
- Dependencies ("Buy paint before the weekend so you can fix the wall")

### 4. Multi-User Support

Both Jesse and his wife can:
- Add tasks
- Assign tasks to each other
- Share access to all categories or select ones
- Receive joint reminders

### 5. Insights Dashboard

Henry generates a private dashboard with:
- Weekly household summary
- Upcoming appointments
- Pending tasks by category
- Spending-related reminders (bills, renewals)
- Health metrics (sleep, steps, workouts, hydration)
- Family activity trends

**Suggestions for:**
- Decluttering overdue tasks
- Planning family time
- Optimizing routines (e.g., "Most of your errands cluster on Thursdays — want me to group them?")

**Dashboard formats:**
- PDF weekly digest
- Web dashboard (future)
- Daily Slack/iMessage summary

### 6. Knowledge Memory

Henry remembers:
- Car service history
- Appliance purchase dates + warranty expiry
- Kids' shoe sizes, preferences, allergies
- Recurring grocery patterns
- Travel preferences

### 7. Automations

Examples:
- "Every Sunday at 6pm, send us the meal plan for the week."
- "Every month, remind me to check furnace filter."
- "Every payday, remind us about savings transfers."

---

## Technical Requirements

- NLP parsing pipeline
- Syncable database with multi-user access
- Scheduler with flexible recurring patterns
- Secure identity separation

**Optional integrations:**
- Calendar (Google/Apple)
- Grocery APIs
- Health trackers (Apple Health, Oura, Garmin, etc.)
- Finance apps

---

## Output Formats

Henry can output:
- Weekly PDF dashboards
- Daily summaries
- Structured lists by category
- Exportable CSVs for budgeting or health tracking

---

## Vision

A fully automated family operations system that:
- Reduces mental load
- Eliminates forgotten tasks
- Enhances communication
- Strengthens family routines
- Creates a shared sense of order and clarity

**Henry becomes the family's Chief of Staff** — always listening, organizing, reminding, and making life easier.

---

## Implementation Phases

### Phase 1: Core Task Management (MVP)
- Basic text parsing and categorization
- 12 category support
- Simple reminders
- Daily/weekly summaries

### Phase 2: Smart Features
- Contextual understanding
- Automated scheduling
- Intelligent reminders
- Multi-user support

### Phase 3: Dashboard & Analytics
- PDF dashboards
- Insights and suggestions
- Knowledge memory
- Automations

### Phase 4: Integrations
- Calendar sync
- Health trackers
- Finance apps
- Grocery APIs

---

## Database Schema (Proposed)

```
tasks/
  - id
  - category
  - title
  - description
  - due_date
  - priority
  - assigned_to
  - created_by
  - status
  - recurrence_pattern
  - tags
  - created_at
  - updated_at

memory/
  - id
  - type (car, appliance, child_preference, etc.)
  - key
  - value
  - expires_at (for warranties)
  
health/
  - date
  - metric_type (steps, sleep, hydration, etc.)
  - value
  - source

automations/
  - id
  - trigger_pattern
  - action
  - schedule
  - enabled
```

---

## Success Metrics

- Tasks captured per week
- Reminders acknowledged
- Dashboard engagement
- Reduced missed appointments/tasks
- User satisfaction

---

*Project brief created from PDF by Henry*
