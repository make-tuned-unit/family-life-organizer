#!/usr/bin/env node
/**
 * Family Life Organizer - CLI
 * Command-line interface for household management
 */

const MessageParser = require('./parser');
const FamilyDB = require('./database');

class FamilyCLI {
  constructor() {
    this.parser = new MessageParser();
  }

  async processCommand(input) {
    const result = await this.parser.process(input);
    return this.formatResponse(result);
  }

  formatResponse(result) {
    const { parsed, result: actionResult } = result;
    
    switch (actionResult.action) {
      case 'added_task':
        return `✅ Added to ${parsed.category}: "${actionResult.task.title}"`;
      
      case 'added_groceries':
        const items = actionResult.items.map(i => i.item).join(', ');
        return `✅ Added to groceries: ${items}`;
      
      case 'list_groceries':
        if (actionResult.items.length === 0) {
          return '🛒 Grocery list is empty';
        }
        const groceryList = actionResult.items.map(i => `  • ${i.item}${i.quantity !== '1' ? ` (${i.quantity})` : ''}`).join('\n');
        return `🛒 Grocery list:\n${groceryList}`;
      
      case 'list_tasks':
        if (actionResult.tasks.length === 0) {
          return `📋 No ${actionResult.category} tasks`;
        }
        const taskList = actionResult.tasks.map(t => `  • ${t.title}${t.due_date ? ` (due ${t.due_date})` : ''}`).join('\n');
        return `📋 ${actionResult.category} tasks:\n${taskList}`;
      
      case 'completed_task':
        return `✅ Completed: "${actionResult.task.title}"`;
      
      case 'no_match_found':
        return `❌ Couldn't find matching item for: "${actionResult.title}"`;
      
      default:
        return `📝 Parsed: ${parsed.action} ${parsed.category} - "${parsed.title}"`;
    }
  }

  async getDailySummary() {
    const summary = await this.parser.db.getDailySummary();
    
    let text = '📊 **Daily Summary**\n\n';
    text += `• ${summary.tasks_today} tasks due today\n`;
    text += `• ${summary.appointments_today} appointments today\n`;
    text += `• ${summary.groceries_needed} items on grocery list\n`;
    text += `• ${summary.overdue_tasks} overdue tasks\n`;
    
    return text;
  }

  close() {
    this.parser.close();
  }
}

// CLI usage
if (require.main === module) {
  const cli = new FamilyCLI();
  const args = process.argv.slice(2);
  
  if (args.length === 0) {
    console.log('Family Life Organizer CLI\n');
    console.log('Usage:');
    console.log('  node cli.js "Add milk to groceries"');
    console.log('  node cli.js "Remind me about dentist tomorrow"');
    console.log('  node cli.js --summary');
    console.log('  node cli.js --list groceries');
    cli.close();
    process.exit(0);
  }
  
  if (args[0] === '--summary') {
    cli.getDailySummary().then(summary => {
      console.log(summary);
      cli.close();
    });
  } else if (args[0] === '--list' && args[1]) {
    cli.processCommand(`list ${args[1]}`).then(response => {
      console.log(response);
      cli.close();
    });
  } else {
    const input = args.join(' ');
    cli.processCommand(input).then(response => {
      console.log(response);
      cli.close();
    });
  }
}

module.exports = FamilyCLI;
