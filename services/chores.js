// Chores for kids — the engine behind a `chores` routine.
//
// One routine per child. `config` holds the child's chore list, the allowance
// rules, and any behaviour bonuses; `routine_entries` hold what actually
// happened (a chore slot done, a bonus earned, a payout made). This module turns
// those into the week the app shows — a check-off grid, a streak, what's earned,
// what's been paid — and into age-based guidance, in the same shape as the
// sleep-training program: a static, sourced template plus `guidanceForBirthdate`.
//
// Design choices, and the evidence they lean on (see SOURCES; keep in sync):
//  * Chores are framed as CONTRIBUTION, not jobs — kids who do chores from 3–4
//    do better decades later (Rossmann 2002), and even kindergarten chores
//    predict competence at grade 3 (White et al. 2019).
//  * A small fixed weekly allowance is fine, but pay is NOT docked per missed
//    chore. Contingent money undermines young children's spontaneous helping
//    (Warneken & Tomasello 2008; Deci, Koestner & Ryan 1999 meta-analysis), so
//    the app never turns a 3-year-old's dog-feeding into piecework.
//  * Cumulative counts are the primary "reward"; a streak is shown only as a
//    secondary encouragement and never as a punishment (see routineAchievements).
//  * Guidance is age-banded and gated: a 3-year-old gets one or two anchored
//    chores; the "add a second chore" nudge waits for the 4th birthday AND a
//    consistent record, not just a date.

const SOURCES = [
  { key: 'rossmann', title: 'Rossmann 2002 (Univ. of Minnesota) — longitudinal: chores begun at 3–4 predict adult success', url: 'https://ghk.h-cdn.co/assets/cm/15/12/550e21d3ea06e_-_Involving-children-in-household-tasks-U-of-M.pdf' },
  { key: 'white2019', title: 'White, Gemmill et al. 2019, J Dev Behav Pediatr — kindergarten chores predict competence & self-efficacy at grade 3 (n≈9,971)', url: 'https://pubmed.ncbi.nlm.nih.gov/30985390/' },
  { key: 'warneken', title: 'Warneken & Tomasello 2008, Dev Psychol — rewards undermine 20-month-olds\' helping', url: 'https://pubmed.ncbi.nlm.nih.gov/18999339/' },
  { key: 'deci1999', title: 'Deci, Koestner & Ryan 1999, Psych Bulletin — meta-analysis: contingent rewards reduce intrinsic motivation', url: 'https://pubmed.ncbi.nlm.nih.gov/10589297/' },
  { key: 'lally', title: 'Lally et al. 2010, Eur J Soc Psychol — habits form over ~66 days (18–254) of same-context repetition', url: 'https://onlinelibrary.wiley.com/doi/10.1002/ejsp.674' },
  { key: 'dweck', title: 'Mueller & Dweck 1998 — process praise ("you fed him every day") beats person praise', url: 'https://pubmed.ncbi.nlm.nih.gov/9686450/' },
  { key: 'aap', title: 'AAP HealthyChildren.org — chores and responsibility by age', url: 'https://www.healthychildren.org/English/family-life/family-dynamics/communication-discipline/Pages/Chores-and-Responsibility.aspx' },
  { key: 'lieber', title: 'Ron Lieber, The Opposite of Spoiled (2015) — allowance as a teaching tool, separate from chores', url: 'https://www.ronlieber.com/books/the-opposite-of-spoiled/' },
  { key: 'trowe', title: 'T. Rowe Price Parents, Kids & Money survey — allowance prevalence and amounts by age', url: 'https://www.troweprice.com/personal-investing/resources/insights/parents-kids-money-survey.html' },
  { key: 'coppens', title: 'Coppens, Alcalá, Mejía-Arauz & Rogoff 2014 — "acomedido": children who help without being asked', url: 'https://pubmed.ncbi.nlm.nih.gov/25016183/' },
];

// Age bands. `minYears`/`maxYears` are inclusive-exclusive. Each band carries
// the chores that are developmentally reasonable, how many to run at once,
// how to reward, and the "ready for the next band" cue.
const BANDS = [
  {
    key: 'toddler',
    title: 'Little helper',
    age_label: '2–3 years',
    minYears: 2, maxYears: 4,
    chore_count: '1–2 chores, done together',
    description: 'At this age the chore is the togetherness. Toddlers want to help (Warneken & Tomasello showed helping emerges before age two) — pick something visible, physical, and tied to a moment in the day, and expect to do it alongside them for months.',
    suggested: [
      { title: 'Feed the pet', icon: 'pawprint.fill', slots: ['morning', 'evening'], note: 'Scoop-and-pour with you beside them; you handle portions and the pantry.' },
      { title: 'Put toys in the bin', icon: 'shippingbox.fill', slots: ['evening'], note: 'One bin, one category — "all the blocks".' },
      { title: 'Carry plate to the counter', icon: 'fork.knife', slots: ['evening'] },
      { title: 'Put clothes in the hamper', icon: 'basket.fill', slots: ['evening'] },
      { title: 'Water a plant', icon: 'leaf.fill', slots: ['morning'], note: 'A small cup; overflows are fine.' },
      { title: 'Help wipe the table', icon: 'sparkles', slots: ['evening'] },
    ],
    steps: [
      'Anchor each chore to something that already happens — "after breakfast, we feed the dog". Same time, same order, every day.',
      'Do it WITH them for as long as it takes; the goal is participation, not a finished job.',
      'Use a picture chart, not words: a photo of the dog bowl they can tap or tick.',
      'Praise the doing, not the child: "you filled the bowl right to the line" rather than "good boy".',
      'Keep allowance (if any) tiny and separate from whether the chore got done. Never dock it.',
    ],
    tips: [
      'A missed day is not a failure — just start again tomorrow. Consistency over months is what builds the habit (Lally et al.).',
      'Expect helping to be slower than doing it yourself. That is the investment.',
    ],
    allowance: {
      label: 'Optional. $1–3/week is typical if you start now.',
      note: 'Research on allowance for 3-year-olds is thin; most experts (Lieber, AAP) see a small fixed amount as a chance to practise counting and saving, not as wages. Keep it fixed and keep the chore "because we all help".',
    },
    next_band: 'Around the 4th birthday, once the first chore has been steady for a few weeks, add a second chore they can start doing on their own.',
  },
  {
    key: 'preschool',
    title: 'Growing independence',
    age_label: '4–5 years',
    minYears: 4, maxYears: 6,
    chore_count: '2–3 chores, some done alone',
    description: 'Preschoolers can follow a two- or three-step chore and begin to own one without a parent beside them. This is the age Rossmann found matters most: children who began regular chores at 3–4 were the most likely to thrive as young adults.',
    suggested: [
      { title: 'Feed the pet', icon: 'pawprint.fill', slots: ['morning', 'evening'] },
      { title: 'Make the bed', icon: 'bed.double.fill', slots: ['morning'], note: 'Pull up the duvet — "made" means tried.' },
      { title: 'Set the table', icon: 'fork.knife', slots: ['evening'], note: 'Napkins and forks first; plates when you trust the hands.' },
      { title: 'Clear their own plate', icon: 'takeoutbag.and.cup.and.straw.fill', slots: ['evening'] },
      { title: 'Match socks / sort laundry', icon: 'tshirt.fill', slots: ['anytime'] },
      { title: 'Water plants', icon: 'leaf.fill', slots: ['morning'] },
      { title: 'Put away groceries (low shelves)', icon: 'cart.fill', slots: ['anytime'] },
      { title: 'Tidy toys before bed', icon: 'shippingbox.fill', slots: ['evening'] },
    ],
    steps: [
      'Add ONE new chore at a time and keep the old one running — stacking on an existing habit is far easier than starting fresh.',
      'Show, do together, then step back: the "I do, we do, you do" sequence.',
      'Let them choose the second chore from a short list. Choice is the cheapest motivator there is (self-determination theory).',
      'Keep the chart visual and let them mark it themselves.',
    ],
    tips: [
      'Quality will be uneven. Resist redoing it in front of them.',
      'A small behaviour bonus (a good bedtime, teeth without a fight) works better as a weekly "did we mostly manage it?" than a nightly pass/fail.',
    ],
    allowance: {
      label: '$2–5/week is typical (roughly $0.50–1 per year of age).',
      note: 'Introduce three jars — spend, save, give — so the money teaches something. Keep it fixed; use praise and the chart, not pay, to drive the chores.',
    },
    next_band: 'By 6 they can take real responsibility for a chore that has consequences if skipped — an unfed pet, an unset table. That is when "it\'s yours" starts to mean something.',
  },
  {
    key: 'early_school',
    title: 'Real responsibility',
    age_label: '6–8 years',
    minYears: 6, maxYears: 9,
    chore_count: '3–4 chores, mostly independent',
    description: 'School-age kids can own a chore end to end, remember it with a light prompt, and start doing chores that serve the whole family rather than only their own things.',
    suggested: [
      { title: 'Feed and water the pet', icon: 'pawprint.fill', slots: ['morning', 'evening'] },
      { title: 'Make the bed', icon: 'bed.double.fill', slots: ['morning'] },
      { title: 'Empty the dishwasher (unbreakables)', icon: 'dishwasher.fill', slots: ['anytime'] },
      { title: 'Take out recycling', icon: 'arrow.3.trianglepath', slots: ['anytime'] },
      { title: 'Pack their school bag', icon: 'backpack.fill', slots: ['evening'] },
      { title: 'Fold and put away own laundry', icon: 'tshirt.fill', slots: ['anytime'] },
      { title: 'Sweep the kitchen floor', icon: 'wind', slots: ['evening'] },
      { title: 'Help with dinner prep', icon: 'fork.knife', slots: ['evening'] },
    ],
    steps: [
      'Split chores into "yours" (your room, your bag) and "ours" (the kitchen, the pet) so helping the family is visible.',
      'Move the reminder from you to the chart or the app — the aim is that nobody has to nag.',
      'Rotate one "ours" chore between siblings weekly so nobody is stuck with the worst one.',
    ],
    tips: [
      'Let natural consequences teach where safe: a bag not packed is a bag missing a thing.',
      'Talk about the money on payday — what they\'ll save for is the lesson.',
    ],
    allowance: {
      label: '$4–8/week is typical.',
      note: 'Many families now pay a base allowance for money practice plus optional "extra jobs" a child can opt into for more — that keeps everyday contribution unpaid while still teaching that effort earns.',
    },
    next_band: 'From 9 or 10 they can run a chore that takes planning — laundry start to finish, a simple meal — and can manage part of their own money.',
  },
  {
    key: 'tween',
    title: 'Running things',
    age_label: '9–12 years',
    minYears: 9, maxYears: 13,
    chore_count: '4–6 chores, fully independent',
    description: 'Tweens can plan multi-step chores, cook simple meals, and take on chores with a weekly rhythm. This is where a chart becomes a shared household system rather than a parent-run one.',
    suggested: [
      { title: 'Cook a simple meal', icon: 'fork.knife', slots: ['evening'] },
      { title: 'Laundry start to finish', icon: 'washer.fill', slots: ['anytime'] },
      { title: 'Vacuum a room', icon: 'wind', slots: ['anytime'] },
      { title: 'Walk the dog', icon: 'pawprint.fill', slots: ['morning', 'evening'] },
      { title: 'Take bins to the kerb', icon: 'trash.fill', slots: ['evening'] },
      { title: 'Clean the bathroom sink & mirror', icon: 'sparkles', slots: ['anytime'] },
      { title: 'Wash the car', icon: 'car.fill', slots: ['anytime'] },
    ],
    steps: [
      'Agree the list together at a family meeting; let them trade chores with siblings.',
      'Give a weekly deadline rather than a daily one for the bigger jobs.',
      'Pay allowance into something they manage — a jar, a savings account, a card.',
    ],
    tips: ['Standards matter now — agree what "done" looks like before, not after.'],
    allowance: {
      label: '$8–12/week is typical.',
      note: 'A fixed allowance plus paid "extra jobs" is the most common expert-endorsed structure at this age.',
    },
    next_band: 'Teenagers can take a full domain — dinner on Tuesdays, the lawn — and their own budget.',
  },
  {
    key: 'teen',
    title: 'Owning a domain',
    age_label: '13+ years',
    minYears: 13, maxYears: 99,
    chore_count: 'A few big, owned responsibilities',
    description: 'Teens do best owning whole domains — a night of dinners, the lawn, the family laundry — with the money side moving toward a real budget.',
    suggested: [
      { title: 'Dinner one night a week', icon: 'fork.knife', slots: ['evening'] },
      { title: 'Mow the lawn', icon: 'leaf.fill', slots: ['anytime'] },
      { title: 'Family laundry', icon: 'washer.fill', slots: ['anytime'] },
      { title: 'Clean the kitchen after dinner', icon: 'sparkles', slots: ['evening'] },
      { title: 'Grocery run', icon: 'cart.fill', slots: ['anytime'] },
      { title: 'Babysit a sibling', icon: 'figure.2.and.child.holdinghands', slots: ['anytime'] },
    ],
    steps: [
      'Negotiate, don\'t assign. Teens who help choose comply more and resent less.',
      'Shift money from allowance to a budget they run for clothes, phone, or outings.',
    ],
    tips: ['Paid extras (bigger jobs) are a fine way to bridge to a first job.'],
    allowance: {
      label: '$12–20+/week, often as a managed budget.',
      note: 'The goal is practice at managing money before the stakes are real.',
    },
    next_band: null,
  },
];

function ageInYears(birthdate, today) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(birthdate || ''));
  if (!m) return null;
  const t = parseISO(today || todayISO());
  const y = Number(m[1]), mo = Number(m[2]) - 1, d = Number(m[3]);
  let years = t.getFullYear() - y;
  if (t.getMonth() < mo || (t.getMonth() === mo && t.getDate() < d)) years--;
  return years;
}

function bandForYears(years) {
  if (years == null || years < 0) return null;
  return BANDS.find(b => years >= b.minYears && years < b.maxYears) || BANDS[0];
}

function template() {
  return {
    id: 'chores',
    title: 'Chores that stick, ages 2 to teen',
    subtitle: 'Age-by-age chores, how to reward them, and what the research actually says.',
    disclaimer: 'Every child is different — treat the ages as a guide, not a test. Supervise anything involving animals, heat, sharp things, or heights.',
    principles: [
      'Contribution over compliance: frame chores as "how our family works", not as jobs for pay.',
      'Anchor to the day: tie each chore to a moment that already happens (after breakfast, before bed).',
      'One new chore at a time, stacked on one that already sticks.',
      'Pictures for pre-readers, a checklist for readers — and let them mark it.',
      'Praise the process. Never dock pay for a missed chore.',
      'Fixed, small allowance for money practice; optional paid extras for the big stuff later.',
    ],
    bands: BANDS.map(b => ({ ...b, min_years: b.minYears, max_years: b.maxYears, minYears: undefined, maxYears: undefined })),
    sources: SOURCES,
  };
}

// ---- Week engine -----------------------------------------------------------

const SLOT_ORDER = ['morning', 'afternoon', 'evening', 'anytime'];

function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function parseISO(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(s || ''));
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(NaN);
}
function fmt(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function addDays(iso, n) { const d = parseISO(iso); d.setDate(d.getDate() + n); return fmt(d); }

// Week starting on `weekStart` (0=Sun … 6=Sat; default Monday) containing `iso`.
function weekStartOf(iso, weekStart = 1) {
  const d = parseISO(iso);
  const diff = (d.getDay() - weekStart + 7) % 7;
  d.setDate(d.getDate() - diff);
  return fmt(d);
}

function parseConfig(config) {
  let c = config;
  if (typeof c === 'string') { try { c = JSON.parse(c); } catch { c = {}; } }
  c = c && typeof c === 'object' ? c : {};
  const chores = Array.isArray(c.chores) ? c.chores.filter(x => x && x.title).map((x, i) => ({
    id: String(x.id || `c${i + 1}`),
    title: String(x.title).trim(),
    icon: x.icon || 'checkmark.circle.fill',
    slots: Array.isArray(x.slots) && x.slots.length ? x.slots.filter(s => SLOT_ORDER.includes(s)) : ['anytime'],
    // JS weekday numbers the chore applies on; empty/absent = every day.
    days: Array.isArray(x.days) && x.days.length ? x.days.map(Number).filter(n => n >= 0 && n <= 6) : null,
    active: x.active !== false,
    started_on: x.started_on || null,
  })) : [];
  const allowance = c.allowance && typeof c.allowance === 'object' ? c.allowance : {};
  const bonuses = Array.isArray(c.bonuses) ? c.bonuses.filter(b => b && b.title).map((b, i) => ({
    id: String(b.id || `b${i + 1}`),
    title: String(b.title).trim(),
    amount: money(b.amount),
    icon: b.icon || 'star.fill',
  })) : [];
  return {
    chores,
    bonuses,
    allowance: {
      weekly_amount: money(allowance.weekly_amount),
      currency: allowance.currency || 'USD',
      // 0=Sun … 6=Sat. Payday defaults to the last day of the week.
      payday: Number.isInteger(allowance.payday) ? allowance.payday : 0,
    },
    week_start: Number.isInteger(c.week_start) ? c.week_start : 1,
  };
}

function money(v) {
  const n = typeof v === 'number' ? v : parseFloat(String(v ?? '').replace(/[^0-9.\-]/g, ''));
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
}

function parseValue(e) {
  if (!e || e.value == null) return {};
  if (typeof e.value === 'object') return e.value;
  try { return JSON.parse(e.value) || {}; } catch { return {}; }
}

// entries: routine_entries rows for this routine (any order).
function compute(entries, config, { today, birthdate } = {}) {
  const cfg = parseConfig(config);
  const day = today || todayISO();
  const weekStart = weekStartOf(day, cfg.week_start);
  const weekEnd = addDays(weekStart, 6);

  const done = new Map();       // `${date}|${chore}|${slot}` -> entry id
  const bonusDays = new Map();  // bonusId -> Map(date -> entry id)
  const payouts = [];
  for (const e of entries || []) {
    if (!e || !/^\d{4}-\d{2}-\d{2}/.test(String(e.entry_date || ''))) continue;
    const date = String(e.entry_date).slice(0, 10);
    const v = parseValue(e);
    if (e.entry_type === 'chore_done' && v.chore_id) {
      done.set(`${date}|${v.chore_id}|${v.slot || 'anytime'}`, e.id);
    } else if (e.entry_type === 'bonus_earned' && v.bonus_id) {
      if (!bonusDays.has(v.bonus_id)) bonusDays.set(v.bonus_id, new Map());
      bonusDays.get(v.bonus_id).set(date, e.id);
    } else if (e.entry_type === 'payout') {
      payouts.push({ id: e.id, date, amount: money(v.amount), week_start: v.week_start || weekStartOf(date, cfg.week_start) });
    }
  }

  const dates = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
  const chores = cfg.chores.filter(c => c.active).map(c => {
    const days = dates.map(date => {
      const applies = !c.days || c.days.includes(parseISO(date).getDay());
      const started = !c.started_on || date >= c.started_on;
      const slots = c.slots.map(slot => ({
        slot, done: done.has(`${date}|${c.id}|${slot}`), entry_id: done.get(`${date}|${c.id}|${slot}`) || null,
      }));
      return { date, applies: applies && started, past: date < day, today: date === day, slots };
    });
    const expected = days.filter(d => d.applies && d.date <= day).reduce((n, d) => n + d.slots.length, 0);
    const doneCount = days.reduce((n, d) => n + d.slots.filter(s => s.done).length, 0);
    const lifetime = [...done.keys()].filter(k => k.split('|')[1] === c.id).length;
    return { ...c, days, done_count: doneCount, expected_count: expected, lifetime_count: lifetime };
  });

  const expectedTotal = chores.reduce((n, c) => n + c.expected_count, 0);
  const doneTotal = chores.reduce((n, c) => n + c.done_count, 0);
  const completion = expectedTotal ? Math.round((doneTotal / expectedTotal) * 100) : null;

  // Streak: consecutive days, ending today or yesterday, where every expected
  // slot was done. Today counts once fully done; an unfinished today doesn't
  // break a streak that ran through yesterday.
  const fullDay = (date) => {
    let expectedSlots = 0, doneSlots = 0;
    for (const c of cfg.chores) {
      if (!c.active) continue;
      if (c.days && !c.days.includes(parseISO(date).getDay())) continue;
      if (c.started_on && date < c.started_on) continue;
      for (const slot of c.slots) { expectedSlots++; if (done.has(`${date}|${c.id}|${slot}`)) doneSlots++; }
    }
    return expectedSlots > 0 && doneSlots === expectedSlots;
  };
  let streak = 0;
  if (cfg.chores.some(c => c.active)) {
    let cursor = fullDay(day) ? day : addDays(day, -1);
    for (let i = 0; i < 400; i++) {
      if (!fullDay(cursor)) break;
      streak++; cursor = addDays(cursor, -1);
    }
  }

  const bonuses = cfg.bonuses.map(b => {
    const map = bonusDays.get(b.id) || new Map();
    const earnedDates = dates.filter(d => map.has(d)).map(d => ({ date: d, entry_id: map.get(d) }));
    return { ...b, earned_dates: earnedDates, earned_this_week: earnedDates.length > 0 };
  });

  const bonusTotal = bonuses.filter(b => b.earned_this_week).reduce((n, b) => n + b.amount, 0);
  const allowance = cfg.allowance.weekly_amount;
  const weekTotal = Math.round((allowance + bonusTotal) * 100) / 100;
  const paidThisWeek = payouts.filter(p => p.week_start === weekStart);

  // Ledger: every week since the first entry (or the routine's start) that has
  // no payout recorded, oldest first. Only weeks that have ENDED are owed —
  // the current week is still being earned.
  const firstDate = [...done.keys()].map(k => k.split('|')[0]).concat([...bonusDays.values()].flatMap(m => [...m.keys()])).sort()[0] || null;
  const unpaidWeeks = [];
  if (firstDate && (allowance > 0 || cfg.bonuses.length)) {
    let ws = weekStartOf(firstDate, cfg.week_start);
    while (ws < weekStart) {
      if (!payouts.some(p => p.week_start === ws)) {
        const wDates = Array.from({ length: 7 }, (_, i) => addDays(ws, i));
        const wBonus = cfg.bonuses.filter(b => wDates.some(d => (bonusDays.get(b.id) || new Map()).has(d)))
          .reduce((n, b) => n + b.amount, 0);
        unpaidWeeks.push({ week_start: ws, week_end: addDays(ws, 6), amount: Math.round((allowance + wBonus) * 100) / 100 });
      }
      ws = addDays(ws, 7);
    }
  }

  const years = ageInYears(birthdate, day);
  const band = bandForYears(years);
  const guidance = band ? {
    age_years: years,
    band_key: band.key,
    band_title: band.title,
    age_label: band.age_label,
    chore_count: band.chore_count,
    allowance_label: band.allowance.label,
    next_band: band.next_band,
    suggested: band.suggested.filter(s => !cfg.chores.some(c => c.title.toLowerCase() === s.title.toLowerCase())),
    nudge: nextChoreNudge({ years, band, chores: cfg.chores, chorePayload: chores, streak, birthdate, today: day }),
  } : null;

  return {
    today: day,
    week_start: weekStart,
    week_end: weekEnd,
    week_start_day: cfg.week_start,
    chores,
    completion_pct: completion,
    done_total: doneTotal,
    expected_total: expectedTotal,
    streak_days: streak,
    lifetime_done: done.size,
    bonuses,
    earnings: {
      currency: cfg.allowance.currency,
      allowance,
      bonus: Math.round(bonusTotal * 100) / 100,
      total: weekTotal,
      payday: cfg.allowance.payday,
      paid: paidThisWeek.length > 0,
      paid_amount: Math.round(paidThisWeek.reduce((n, p) => n + p.amount, 0) * 100) / 100,
      payout_entry_id: paidThisWeek[0]?.id || null,
    },
    ledger: {
      unpaid_weeks: unpaidWeeks,
      owed: Math.round(unpaidWeeks.reduce((n, w) => n + w.amount, 0) * 100) / 100,
      lifetime_paid: Math.round(payouts.reduce((n, p) => n + p.amount, 0) * 100) / 100,
    },
    guidance,
  };
}

// The one forward-looking sentence: when to add a chore, or why not yet. Age
// alone never triggers it — the record has to be steady too, because a second
// chore stacked on a shaky first one usually sinks both.
function nextChoreNudge({ years, band, chores, chorePayload, streak, birthdate, today }) {
  const active = chores.filter(c => c.active);
  if (!active.length) return { kind: 'start', text: `Start with one chore from the ${band.age_label} list — something anchored to a moment in the day.` };
  const target = { toddler: 2, preschool: 3, early_school: 4, tween: 5, teen: 4 }[band.key] || 3;
  if (years != null && band.key === 'toddler' && birthdate) {
    // Days until the 4th birthday.
    const b = parseISO(birthdate); const fourth = new Date(b.getFullYear() + 4, b.getMonth(), b.getDate());
    const daysTo = Math.round((fourth - parseISO(today)) / 86400000);
    if (daysTo > 0 && daysTo <= 60) return { kind: 'soon', text: `Turning 4 in ${daysTo} day${daysTo === 1 ? '' : 's'} — a good moment to let them pick a second chore.` };
  }
  if (active.length < target && streak >= 14) {
    return { kind: 'add', text: `${streak} days steady — ready to add a chore. Keep the current one running and stack the new one on it.` };
  }
  if (active.length < target && streak < 14) {
    return { kind: 'hold', text: 'Keep going with what\'s there — two steady weeks before adding the next one.' };
  }
  return { kind: 'steady', text: `${active.length} chore${active.length === 1 ? '' : 's'} is plenty for ${band.age_label}. Consistency beats quantity.` };
}

function guidanceForBirthdate(birthdate, today) {
  const years = ageInYears(birthdate, today);
  const band = bandForYears(years);
  if (!band) return null;
  return { age_years: years, band: { ...band, min_years: band.minYears, max_years: band.maxYears, minYears: undefined, maxYears: undefined } };
}

module.exports = { template, compute, parseConfig, guidanceForBirthdate, ageInYears, weekStartOf, BANDS, SOURCES, SLOT_ORDER };
