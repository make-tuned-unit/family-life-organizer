#!/usr/bin/env node
/**
 * Family Life Organizer - Email Receipt Processor
 * Polls Gmail for receipt emails and extracts data
 */

const imaps = require('imap-simple');
const path = require('path');
const fs = require('fs');
const FamilyDB = require('./database');

// Gmail credentials (from env — no hardcoded fallback)
const GMAIL_USER = process.env.GMAIL_USER;
const GMAIL_PASS = process.env.GMAIL_APP_PASSWORD;

// Only ingest receipts from trusted senders. Comma-separated substrings matched
// against the email's From header (e.g. "receipts@amazon.com,@apple.com").
// If unset, NOTHING is ingested — anyone can email the inbox, so an allowlist is
// required to stop forged receipts being written into the family's budget.
const SENDER_ALLOWLIST = (process.env.RECEIPT_SENDER_ALLOWLIST || '')
  .split(',').map(s => s.trim().toLowerCase()).filter(Boolean);

const MAX_RECEIPT_AMOUNT = 100000; // reject implausible amounts

// IMAP config
const imapConfig = {
  imap: {
    user: GMAIL_USER,
    password: GMAIL_PASS,
    host: 'imap.gmail.com',
    port: 993,
    tls: true,
    // Verify Gmail's TLS certificate (Node trusts public CAs by default).
    tlsOptions: { rejectUnauthorized: true, servername: 'imap.gmail.com' },
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
  pharmacy: /pharmacy|shoppers|rexall|drug/i,
  household: /home\s?depot|lowes|ikea|canadian tire|dollar|hardware/i,
  pets: /pet|vet|veterinar|petsmart|petcetera|animal hospital/i,
  entertainment: /cinema|movie|theatre|theater|netflix|spotify|ticket|concert|amusement/i,
  kids: /toy|school|daycare|childcare|children|youth/i
};

function guessCategory(text) {
  const lower = text.toLowerCase();
  if (patterns.grocery.test(lower)) return 'Groceries';
  if (patterns.dining.test(lower)) return 'Dining Out';
  if (patterns.gas.test(lower)) return 'Gas/Transport';
  if (patterns.pharmacy.test(lower)) return 'Health';
  if (patterns.household.test(lower)) return 'Household';
  if (patterns.pets.test(lower)) return 'Pets';
  if (patterns.entertainment.test(lower)) return 'Entertainment';
  if (patterns.kids.test(lower)) return 'Kids';
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
        const mNum = parseInt(month, 10), dNum = parseInt(day, 10);
        if (mNum >= 1 && mNum <= 12 && dNum >= 1 && dNum <= 31) {
          return `${year}-${month}-${day}`;
        }
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

// Strip control characters and cap length before the merchant string is stored
// and later rendered (defense against stored-XSS / log injection).
function sanitizeMerchant(name) {
  return String(name || 'Unknown')
    .replace(/[\x00-\x1f<>]/g, ' ')
    .trim()
    .slice(0, 80) || 'Unknown';
}

async function processReceiptEmails() {
  if (!GMAIL_USER || !GMAIL_PASS) {
    console.error('GMAIL_USER and GMAIL_APP_PASSWORD must be set');
    return;
  }
  if (SENDER_ALLOWLIST.length === 0) {
    console.error('RECEIPT_SENDER_ALLOWLIST not set — refusing to ingest unverified email. Aborting.');
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
    // Email receipts have no user session — attribute to the primary household
    // (the inbox owner's), matching the backfill's default assignment.
    const householdId = await new Promise((resolve) => {
      db.db.get(`SELECT g.id FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        JOIN users u ON u.id = gm.user_id AND u.username = 'jesse'
        WHERE g.group_type = 'household' LIMIT 1`, (e, r) => resolve(r?.id || null));
    });

    for (const message of messages) {
      try {
        const header = message.parts.find(p => p.which === 'HEADER').body;
        const text = message.parts.find(p => p.which === 'TEXT').body;
        
        const subject = header.subject?.[0] || 'Unknown';
        const from = header.from?.[0] || 'Unknown';
        const emailId = message.attributes.uid;

        // Reject senders not on the allowlist — the From header is the only thing
        // standing between a forged email and a fabricated budget entry.
        const fromLower = from.toLowerCase();
        if (!SENDER_ALLOWLIST.some(s => fromLower.includes(s))) {
          console.log(`✗ Skipping untrusted sender (uid ${emailId})`);
          await connection.addFlags(emailId, ['\\Seen']);
          continue;
        }

        console.log(`Processing uid ${emailId}`);

        // Extract receipt data
        const fullText = subject + ' ' + text;
        const amount = extractAmount(fullText);
        const merchant = sanitizeMerchant(extractMerchant(text, subject));
        const date = extractDate(fullText);
        const category = guessCategory(fullText);

        if (amount && amount > 0 && amount < MAX_RECEIPT_AMOUNT) {
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
            added_by: 'email',
            group_id: householdId
          });
          
          console.log(`✓ Logged receipt (uid ${emailId}, ${category})`);

          // Mark as read
          await connection.addFlags(emailId, ['\\Seen']);
        } else {
          console.log(`✗ Could not extract a valid amount (uid ${emailId})`);
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
