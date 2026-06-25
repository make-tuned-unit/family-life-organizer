// One-off: seed a curated "William" demo household for marketing screenshots.
// Idempotent-ish: removes any prior William user/group first. LOCAL DB only.
const bcrypt = require('bcryptjs');
const FamilyDB = require('../database.js');

const TODAY = new Date().toLocaleDateString('en-CA'); // YYYY-MM
const MONTH = TODAY.slice(0, 7);
function plus(days) {
  const d = new Date(TODAY + 'T00:00:00');
  d.setDate(d.getDate() + days);
  return d.toLocaleDateString('en-CA');
}

(async () => {
  const db = new FamilyDB();
  const run = (sql, p = []) => new Promise((res, rej) => db.db.run(sql, p, function (e) { e ? rej(e) : res(this); }));
  const get = (sql, p = []) => new Promise((res, rej) => db.db.get(sql, p, (e, r) => e ? rej(e) : res(r)));

  // Clean any prior William
  const prev = await get(`SELECT id FROM users WHERE username='william'`);
  if (prev) {
    const g = await get(`SELECT g.id FROM groups g JOIN group_members gm ON gm.group_id=g.id WHERE gm.user_id=? AND g.group_type='household'`, [prev.id]);
    if (g) {
      for (const t of ['receipts','budget_categories','appointments','tasks','pantry','decisions']) {
        await run(`DELETE FROM ${t} WHERE group_id=?`, [g.id]).catch(() => {});
      }
      await run(`DELETE FROM group_members WHERE group_id=?`, [g.id]);
      await run(`DELETE FROM groups WHERE id=?`, [g.id]);
    }
    await run(`DELETE FROM users WHERE id=?`, [prev.id]);
  }

  // User + household
  const hash = await bcrypt.hash('demo1234', 10);
  const user = await db.createUser({ username: 'william', password_hash: hash, name: 'William', email: 'william@kinrows.app' });
  const group = await db.createGroup({ name: 'The Hales', group_type: 'household', created_by: user.id });
  await db.addGroupMember(group.id, { user_id: user.id, role: 'admin', added_by: user.id });
  const gid = group.id;

  // Budget categories + receipts to drive over-limit % (spent = sum of receipts by category/month)
  const cats = [
    { name: 'Kids', limit: 300, spent: 477, color: '#E2725B' },     // 159%
    { name: 'Groceries', limit: 800, spent: 944, color: '#7A8B6F' }, // 118%
    { name: 'Pets', limit: 150, spent: 159, color: '#D4A24E' },      // 106%
    { name: 'Home', limit: 600, spent: 280, color: '#9C8FB0' },      // under
  ];
  for (const c of cats) {
    await db.addBudgetCategory(c.name, c.limit, c.color, gid);
    await db.addReceipt({ amount: c.spent, merchant: c.name + ' (month total)', date: plus(-3), category: c.name, added_by: 'william', group_id: gid });
  }

  // Appointments this week
  await db.addAppointment({ title: 'Ferry to PEI', appointment_date: plus(1), appointment_time: '11:45', location: 'Caribou Ferry, Pictou', group_id: gid });
  await db.addAppointment({ title: 'Brewery visit', appointment_date: plus(2), appointment_time: '14:00', location: 'Tatamagouche Brewing', group_id: gid });
  await db.addAppointment({ title: 'Baseball game', appointment_date: plus(2), appointment_time: '18:30', location: 'Memorial Field', group_id: gid });

  // Decision
  await db.addDecision({ title: 'Which summer camp for the kids?', decision_type: 'poll', creator_name: 'William', status: 'active', group_id: gid, poll_options: ['Adventure camp', 'Arts camp'] });

  // Pantry expiring soon
  await db.addPantryItem({ item: 'Greek yogurt', category: 'Dairy', expiry_date: plus(1), added_by: 'william', group_id: gid });
  await db.addPantryItem({ item: 'Baby spinach', category: 'Produce', expiry_date: TODAY, added_by: 'william', group_id: gid });

  console.log(`Seeded William (user ${user.id}, group ${gid}), month ${MONTH}, login william / demo1234`);
  db.close();
})().catch(e => { console.error(e); process.exit(1); });
