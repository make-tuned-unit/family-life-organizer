#!/usr/bin/env node
/**
 * Family Life Organizer - NLP Parser
 * Rule-based natural language processing (no API calls)
 */

const FamilyDB = require('./database');

class MessageParser {
  constructor() {
    this.db = new FamilyDB();
    
    // Category patterns
    this.categories = {
      groceries: ['grocery', 'groceries', 'buy', 'shopping', 'food', 'eggs', 'milk', 'bread', 'fruit', 'vegetable'],
      appointments: ['appointment', 'dentist', 'doctor', 'meeting', 'schedule', 'book', 'reserve'],
      home: ['home', 'repair', 'fix', 'clean', 'maintenance', 'yard', 'lawn', 'paint'],
      automotive: ['car', 'oil', 'tire', 'service', 'automotive', 'vehicle', 'maintenance'],
      travel: ['trip', 'travel', 'vacation', 'flight', 'hotel', 'booking'],
      finances: ['bill', 'pay', 'finance', 'money', 'budget', 'expense', 'renewal'],
      recipes: ['recipe', 'cook', 'meal', 'dinner', 'lunch', 'breakfast', 'food'],
      childcare: ['child', 'kids', 'liam', 'school', 'daycare', 'babysitter'],
      dates: ['date', 'dinner date', 'movie', 'night out', 'anniversary'],
      health: ['health', 'steps', 'sleep', 'hydration', 'water', 'workout', 'exercise', 'run'],
      family: ['family', 'parents', 'in-laws', 'relatives'],
      reminders: ['remind', 'remember', 'don\'t forget', 'note']
    };

    // Action patterns
    this.actions = {
      add: ['add', 'create', 'new', 'put', 'need', 'want'],
      complete: ['done', 'completed', 'finished', 'did', 'bought', 'purchased'],
      delete: ['delete', 'remove', 'cancel', 'clear'],
      list: ['list', 'show', 'what', 'get', 'display'],
      remind: ['remind', 'remember'],
      schedule: ['schedule', 'book', 'appointment', 'reserve']
    };

    // Time patterns
    this.timePatterns = {
      today: /\btoday\b/i,
      tomorrow: /\btomorrow\b/i,
      next_week: /\bnext week\b/i,
      this_weekend: /\bthis weekend\b/i,
      next_month: /\bnext month\b/i,
      in_days: /\bin (\d+) days?\b/i,
      date_specific: /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]* (\d{1,2})\b/i
    };

    // Recurrence patterns
    this.recurrencePatterns = {
      daily: /\bevery day\b|\bdaily\b/i,
      weekly: /\bevery week\b|\bweekly\b|\bevery (mon|tues|wed|thurs|fri|sat|sun)\b/i,
      monthly: /\bevery month\b|\bmonthly\b/i,
      yearly: /\bevery year\b|\bannually\b|\bannual\b/i
    };
  }

  parse(message, user = 'jesse') {
    const lowerMsg = message.toLowerCase();
    
    // Detect action
    const action = this.detectAction(lowerMsg);
    
    // Detect category
    const category = this.detectCategory(lowerMsg);
    
    // Extract title (main content)
    const title = this.extractTitle(message);
    
    // Parse dates
    const dates = this.parseDates(lowerMsg);
    
    // Detect priority
    const priority = this.detectPriority(lowerMsg);
    
    // Detect recurrence
    const recurrence = this.detectRecurrence(lowerMsg);
    
    // Detect assignee
    const assignedTo = this.detectAssignee(lowerMsg);

    const result = {
      action,
      category,
      title,
      priority,
      due_date: dates.date,
      due_time: dates.time,
      recurrence,
      assigned_to: assignedTo,
      raw_message: message,
      parsed_at: new Date().toISOString()
    };

    return result;
  }

  detectAction(message) {
    for (const [action, patterns] of Object.entries(this.actions)) {
      for (const pattern of patterns) {
        if (message.includes(pattern)) {
          return action;
        }
      }
    }
    return 'add'; // Default action
  }

  detectCategory(message) {
    const scores = {};
    
    for (const [category, patterns] of Object.entries(this.categories)) {
      scores[category] = 0;
      for (const pattern of patterns) {
        if (message.includes(pattern)) {
          scores[category]++;
        }
      }
    }
    
    // Find highest scoring category
    let bestCategory = 'reminders';
    let bestScore = 0;
    
    for (const [cat, score] of Object.entries(scores)) {
      if (score > bestScore) {
        bestScore = score;
        bestCategory = cat;
      }
    }
    
    return bestCategory;
  }

  extractTitle(message) {
    // Remove common prefixes
    let title = message
      .replace(/^add\s+/i, '')
      .replace(/^remind me\s+(to\s+)?/i, '')
      .replace(/^remember\s+(to\s+)?/i, '')
      .replace(/^create\s+/i, '')
      .replace(/^new\s+/i, '');
    
    // Remove time references for cleaner title
    title = title
      .replace(/\btoday\b/gi, '')
      .replace(/\btomorrow\b/gi, '')
      .replace(/\bnext week\b/gi, '')
      .replace(/\bin \d+ days?\b/gi, '')
      .replace(/\bevery \w+\b/gi, '');
    
    return title.trim();
  }

  parseDates(message) {
    const today = new Date();
    let date = null;
    let time = null;

    // Check for today
    if (this.timePatterns.today.test(message)) {
      date = today.toISOString().split('T')[0];
    }
    // Check for tomorrow
    else if (this.timePatterns.tomorrow.test(message)) {
      const tomorrow = new Date(today);
      tomorrow.setDate(tomorrow.getDate() + 1);
      date = tomorrow.toISOString().split('T')[0];
    }
    // Check for next week
    else if (this.timePatterns.next_week.test(message)) {
      const nextWeek = new Date(today);
      nextWeek.setDate(nextWeek.getDate() + 7);
      date = nextWeek.toISOString().split('T')[0];
    }
    // Check for "in X days"
    else {
      const daysMatch = message.match(this.timePatterns.in_days);
      if (daysMatch) {
        const days = parseInt(daysMatch[1]);
        const future = new Date(today);
        future.setDate(future.getDate() + days);
        date = future.toISOString().split('T')[0];
      }
    }

    // Check for month names
    const monthMatch = message.match(this.timePatterns.date_specific);
    if (monthMatch) {
      const monthNames = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
      const month = monthNames.findIndex(m => monthMatch[1].toLowerCase().startsWith(m));
      if (month !== -1) {
        const day = parseInt(monthMatch[2]);
        const year = today.getFullYear();
        date = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
      }
    }

    // Extract time (e.g., "at 3pm", "at 14:00")
    const timeMatch = message.match(/\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
    if (timeMatch) {
      let hours = parseInt(timeMatch[1]);
      const minutes = timeMatch[2] || '00';
      const ampm = timeMatch[3];
      
      if (ampm === 'pm' && hours < 12) hours += 12;
      if (ampm === 'am' && hours === 12) hours = 0;
      
      time = `${String(hours).padStart(2, '0')}:${minutes}`;
    }

    return { date, time };
  }

  detectPriority(message) {
    if (/\burgent\b|\basap\b|\bemergency\b/i.test(message)) return 'high';
    if (/\bimportant\b|\bpriority\b/i.test(message)) return 'medium';
    return 'low';
  }

  detectRecurrence(message) {
    for (const [pattern, regex] of Object.entries(this.recurrencePatterns)) {
      if (regex.test(message)) {
        return pattern;
      }
    }
    return null;
  }

  detectAssignee(message) {
    const wifeNames = ['wife', 'sarah', 'jessica', 'kate', 'lisa', 'marie', 'ann'];
    
    for (const name of wifeNames) {
      if (message.includes(name)) {
        return 'wife';
      }
    }
    
    if (message.includes('me') || message.includes('my')) {
      return 'jesse';
    }
    
    return null;
  }

  // Process and store the parsed message
  async process(message, user = 'jesse') {
    const parsed = this.parse(message, user);
    
    // Log the message
    await this.db.logMessage(message, parsed.category, parsed.action);
    
    // Execute based on action and category
    let result;
    
    switch (parsed.action) {
      case 'add':
        result = await this.handleAdd(parsed);
        break;
      case 'complete':
        result = await this.handleComplete(parsed);
        break;
      case 'list':
        result = await this.handleList(parsed);
        break;
      case 'delete':
        result = await this.handleDelete(parsed);
        break;
      default:
        result = { status: 'unknown_action', parsed };
    }
    
    return { parsed, result };
  }

  async handleAdd(parsed) {
    if (parsed.category === 'groceries') {
      // Extract individual items from grocery list
      const items = this.extractGroceryItems(parsed.title);
      const added = [];
      for (const item of items) {
        const result = await this.db.addGrocery(item, parsed.category);
        added.push(result);
      }
      return { action: 'added_groceries', items: added };
    }
    
    // Add as task
    const task = await this.db.addTask({
      category: parsed.category,
      title: parsed.title,
      priority: parsed.priority,
      due_date: parsed.due_date,
      due_time: parsed.due_time,
      assigned_to: parsed.assigned_to,
      recurrence: parsed.recurrence
    });
    
    return { action: 'added_task', task };
  }

  extractGroceryItems(text) {
    // Split by common delimiters
    const items = text
      .replace(/^(add|buy|get|need)\s+/i, '')
      .split(/,\s*|\s+and\s+/)
      .map(i => i.trim())
      .filter(i => i.length > 0);
    
    return items;
  }

  async handleComplete(parsed) {
    // Find matching task and complete it
    const tasks = await this.db.getTasks({ status: 'active' });
    const matching = tasks.find(t => 
      parsed.title.toLowerCase().includes(t.title.toLowerCase()) ||
      t.title.toLowerCase().includes(parsed.title.toLowerCase())
    );
    
    if (matching) {
      await this.db.completeTask(matching.id);
      return { action: 'completed_task', task: matching };
    }
    
    return { action: 'no_match_found', title: parsed.title };
  }

  async handleList(parsed) {
    if (parsed.category === 'groceries') {
      const items = await this.db.getGroceries('needed');
      return { action: 'list_groceries', items };
    }
    
    const tasks = await this.db.getTasks({ 
      category: parsed.category,
      status: 'active'
    });
    
    return { action: 'list_tasks', category: parsed.category, tasks };
  }

  async handleDelete(parsed) {
    // Find and delete matching task
    const tasks = await this.db.getTasks({ status: 'active' });
    const matching = tasks.find(t => 
      parsed.title.toLowerCase().includes(t.title.toLowerCase())
    );
    
    if (matching) {
      // Soft delete by marking as cancelled
      await this.db.completeTask(matching.id); // Reuse complete for now
      return { action: 'deleted_task', task: matching };
    }
    
    return { action: 'no_match_found', title: parsed.title };
  }

  close() {
    this.db.close();
  }
}

module.exports = MessageParser;

// CLI usage for testing
if (require.main === module) {
  const parser = new MessageParser();
  
  const testMessages = [
    "Add eggs, milk, and bread to groceries",
    "Remind me about car tire rotation in March",
    "Book a dentist appointment for Liam in April",
    "Collect trip ideas for May long weekend",
    "Track my steps and hydration this week",
    "Schedule date night for Friday at 7pm"
  ];
  
  console.log('Testing Family Life Organizer Parser:\n');
  
  for (const msg of testMessages) {
    const parsed = parser.parse(msg);
    console.log(`Message: "${msg}"`);
    console.log(`  → Action: ${parsed.action}`);
    console.log(`  → Category: ${parsed.category}`);
    console.log(`  → Title: ${parsed.title}`);
    console.log(`  → Due: ${parsed.due_date || 'no date'}${parsed.due_time ? ' at ' + parsed.due_time : ''}`);
    console.log(`  → Priority: ${parsed.priority}`);
    console.log('');
  }
  
  parser.close();
}
