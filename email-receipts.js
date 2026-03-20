#!/usr/bin/env node
/**
 * Family Life Organizer - Email Receipt Processor
 * Polls Gmail for receipt emails and extracts data
 */

const imaps = require('imap-simple');
const path = require('path');
const fs = require('fs');
const FamilyDB = require('./database');

// Gmail credentials (from env)
const GMAIL_USER = process.env.GMAIL_USER || 'jhenrymalcolm@gmail.com';
const GMAIL_PASS = process.env.GMAIL_APP_PASSWORD;

// IMAP config
const imapConfig = {
  imap: {
    user: GMAIL_USER,
    password: GMAIL_PASS,
    host: 'imap.gmail.com',
    port: 993,
    tls: true,
    tlsOptions: { rejectUnauthorized: false },
    authTimeout: 3000
  }
};

// Simple regex patterns for receipt extraction
const patterns = {
  amount: /[$€£]\s*([\d,]+\.?\d{0,2})/,
  total: /total[:\s]*[$€£]?\s*([\d,]+\.?\d{0,2})/i,
  merchant: /(?:from|at|merchant)[:\s]*([A-Za-z0-9\s&]+)/i,
  date: /(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})/,
  grocery: /grocery|supermarket|walmart|target|costco|loblaws|sobeys/i,
  dining: /restaurant|cafe|coffee|mcdonalds|starbucks|tim hortons/i,
  gas: /gas|petro|shell|esso|ultramar/i,
  pharmacy: /pharmacy|shoppers|rexall|drug/i
};

function guessCategory(text) {
  const lower = text.toLowerCase();
  if (patterns.grocery.test(lower)) return 'Groceries';
  if (patterns.dining.test(lower)) return 'Dining Out';
  if (patterns.gas.test(lower)) return 'Gas/Transport';
  if (patterns.pharmacy.test(lower)) return 'Health';
  return 'Other';
}

function extractAmount(text) {
  // Look for total first, then any amount
  const totalMatch = text.match(patterns.total);
  if (totalMatch) return parseFloat(totalMatch[1].replace(',', ''));
  
  const amountMatch = text.match(patterns.amount);
  if (amountMatch) return parseFloat(amountMatch[1].replace(',', ''));
  
  return null;
}

function extractDate(text) {
  const match = text.match(patterns.date);
  if (match) {
    // Try to parse and format as YYYY-MM-DD
    try {
      const parts = match[1].split(/[\/\-\.]/);
      if (parts.length === 3) {
        const year = parts[2].length === 2 ? '20' + parts[2] : parts[2];
        const month = parts[0].padStart(2, '0');
        const day = parts[1].padStart(2, '0');
        return `${year}-${month}-${day}`;
      }
    } catch (e) {}
  }
  return new Date().toISOString().split('T')[0];
}

function extractMerchant(text, subject) {
  // Try subject first, then body
  const sources = [subject, text];
  for (const source of sources) {
    const match = source.match(patterns.merchant);
    if (match) return match[1].trim();
  }
  
  // Fallback: first line of subject
  return subject.split('\n')[0].substring(0, 50);
}

async function processReceiptEmails() {
  if (!GMAIL_PASS) {
    console.error('GMAIL_APP_PASSWORD not set');
    return;
  }
  
  try {
    const connection = await imaps.connect(imapConfig);
    await connection.openBox('INBOX');
    
    // Search for unread emails with attachments or receipt keywords
    const searchCriteria = [
      'UNSEEN',
      ['OR', 
        ['SUBJECT', 'receipt'],
        ['SUBJECT', 'purchase'],
        ['SUBJECT', 'order'],
        ['SUBJECT', 'payment'],
        ['FROM', 'receipt'],
        ['FROM', 'no-reply']
      ]
    ];
    
    const fetchOptions = { bodies: ['HEADER', 'TEXT'], struct: true };
    const messages = await connection.search(searchCriteria, fetchOptions);
    
    console.log(`Found ${messages.length} potential receipt emails`);
    
    const db = new FamilyDB();
    
    for (const message of messages) {
      try {
        const header = message.parts.find(p => p.which === 'HEADER').body;
        const text = message.parts.find(p => p.which === 'TEXT').body;
        
        const subject = header.subject?.[0] || 'Unknown';
        const from = header.from?.[0] || 'Unknown';
        const emailId = message.attributes.uid;
        
        console.log(`Processing: ${subject}`);
        
        // Extract receipt data
        const fullText = subject + ' ' + text;
        const amount = extractAmount(fullText);
        const merchant = extractMerchant(text, subject);
        const date = extractDate(fullText);
        const category = guessCategory(fullText);
        
        if (amount && amount > 0) {
          // Save to database
          await db.addReceipt({
            amount,
            merchant,
            date,
            category,
            payment_method: 'Unknown',
            notes: `From email: ${subject}`,
            processed_by: 'email',
            email_id: emailId.toString(),
            added_by: 'email'
          });
          
          console.log(`✓ Logged: $${amount} at ${merchant} (${category})`);
          
          // Mark as read
          await connection.addFlags(emailId, ['\\Seen']);
        } else {
          console.log(`✗ Could not extract amount from: ${subject}`);
        }
      } catch (err) {
        console.error('Error processing message:', err.message);
      }
    }
    
    db.close();
    await connection.end();
    
  } catch (err) {
    console.error('IMAP Error:', err.message);
  }
}

// Run every 5 minutes if called directly
if (require.main === module) {
  console.log('Receipt Email Processor starting...');
  processReceiptEmails().then(() => {
    console.log('Done');
    process.exit(0);
  });
}

module.exports = { processReceiptEmails };
