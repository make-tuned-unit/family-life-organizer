// Guided sleep-training program — the pre-built template behind a
// `sleep_training` routine. Age-banded phases from newborn to 4 years, grounded
// in AAP safe-sleep guidance and the evidence base for behavioural sleep
// interventions (graduated extinction, bedtime fading, etc.).
//
// This is educational scaffolding, NOT medical advice. Every phase leads with
// "check with your pediatrician", and formal training is gated to ~4+ months as
// the research and the AAP recommend. Content is validated against the sources
// listed in SOURCES below; keep them in sync when editing phases.

const SOURCES = [
  { title: 'NIH Safe to Sleep (NICHD) — AAP-aligned safe-sleep guidance', url: 'https://safetosleep.nichd.nih.gov/reduce-risk/reduce' },
  { title: 'AAP 2022 Safe Sleep Policy Statement (Pediatrics)', url: 'https://publications.aap.org/pediatrics/article/150/1/e2022057990/188304' },
  { title: 'AASM child sleep-duration consensus (AAP-endorsed)', url: 'https://aasm.org/advocacy/position-statements/child-sleep-duration-health-advisory/' },
  { title: 'Gradisar et al. 2016, Pediatrics — RCT: graduated extinction & bedtime fading, no adverse stress/attachment effects', url: 'https://publications.aap.org/pediatrics/article/137/6/e20151486/52401/' },
  { title: 'Price et al. 2012, Pediatrics — 5-year follow-up: no long-term harm', url: 'https://pubmed.ncbi.nlm.nih.gov/22966034/' },
  { title: 'Mindell et al. 2006 — AASM review of behavioural sleep interventions (efficacy)', url: 'https://pubmed.ncbi.nlm.nih.gov/17068979/' },
  { title: 'Mindell et al. 2015 — bedtime routine dose-response (n=10,085)', url: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC4402657/' },
  { title: 'Moore/Friman 2007 — Bedtime Pass RCT (ages 3–6)', url: 'https://pubmed.ncbi.nlm.nih.gov/16899650/' },
  { title: 'NHS — Helping your baby to sleep', url: 'https://www.nhs.uk/conditions/baby/caring-for-a-newborn/helping-your-baby-to-sleep/' },
];

// Universal safe-sleep rules — surfaced on every phase, especially the newborn one.
const SAFE_SLEEP = [
  'Always put baby to sleep on their back — every sleep, until age 1 (including preterm babies and those with reflux).',
  'Use a firm, flat, level surface (crib/bassinet/play yard) — never an incline or a soft/hammock-like surface.',
  'Bare is best: no pillows, blankets, bumpers, soft toys, pods, nests, or weighted swaddles in the sleep space.',
  'Room-share (baby in your room, own sleep surface) for at least the first 6 months — but never bed-share.',
  'Avoid overheating; keep the head uncovered and use a sleep sack instead of loose bedding (NHS suggests ~16–20°C).',
  'Offer a pacifier at sleep time once feeding is established; keep the space smoke-, vape-, and alcohol-free.',
  'Stop swaddling at the first signs of rolling; don’t use car seats/swings for routine sleep or rely on "anti-SIDS" monitors.',
];

// The named, evidence-based methods a phase can recommend.
const METHODS = {
  routine_only: {
    key: 'routine_only',
    name: 'Rhythm, not training',
    summary: 'No formal sleep training. Build day/night rhythm, watch wake windows, and put baby down drowsy-but-awake.',
    ages: '0–4 months',
  },
  bedtime_fading: {
    key: 'bedtime_fading',
    name: 'Bedtime fading',
    summary: 'Temporarily set bedtime to when baby naturally falls asleep, then move it 10–15 min earlier every few nights toward the target. Lowers bedtime resistance with little crying.',
    ages: '4+ months',
  },
  graduated_extinction: {
    key: 'graduated_extinction',
    name: 'Graduated extinction (Ferber / check-and-console)',
    summary: 'Put baby down awake; if they fuss, wait a set interval before a brief, calm check (no picking up), lengthening the interval each time. Strong evidence; usually works within 3–7 nights.',
    ages: '4–6+ months',
  },
  chair_method: {
    key: 'chair_method',
    name: 'Chair method (gradual retreat)',
    summary: 'Sit beside the crib until baby sleeps, then move the chair a little farther from the crib every few nights until you are out of the room. Gentler, slower.',
    ages: '6+ months',
  },
  pick_up_put_down: {
    key: 'pick_up_put_down',
    name: 'Pick-up / put-down',
    summary: 'When baby cries, pick up to calm, then put down awake as soon as settled; repeat as needed. Low-cry but labour-intensive; best under ~7 months.',
    ages: '4–7 months',
  },
  full_extinction: {
    key: 'full_extinction',
    name: 'Full extinction ("cry it out")',
    summary: 'After a loving routine, put baby down awake and do not return until morning (aside from scheduled feeds/safety checks). Fastest results; only if it fits your family — evidence shows no long-term harm.',
    ages: '4–6+ months',
  },
  bedtime_pass: {
    key: 'bedtime_pass',
    name: 'Bedtime pass',
    summary: 'Give your child one "pass" they can trade for a single sanctioned get-up or request after lights-out; ignore further bids, and let an unused pass earn a small morning reward. Strongest evidence for this age — extinction-level results with far less crying.',
    ages: '3+ years (works from ~2.5)',
  },
  silent_return: {
    key: 'silent_return',
    name: 'Silent return + reward chart',
    summary: 'When your child leaves the bed or calls out, calmly walk them back with no talking or eye contact, every time; pair with a sticker/reward chart for staying put. Consistency is what makes it work.',
    ages: '2+ years',
  },
};

// Age-banded phases. `minDays`/`maxDays` define the window used to pick the
// current phase from a birthdate. Copy is warm and non-judgmental.
const PHASES = [
  {
    key: 'newborn',
    title: 'Newborn — settle in',
    age_label: '0–3 months',
    minDays: 0, maxDays: 112, // ~0 to 16 weeks
    method: 'routine_only',
    description: "Newborns can't be sleep-trained yet — their sleep is driven by hunger and a still-developing body clock. The goal now is safe sleep and gently teaching the difference between day and night.",
    steps: [
      'Feed on demand, day and night — do not stretch a hungry newborn.',
      'Keep days bright and social; keep night feeds quiet, dim, and boring.',
      'Aim to put baby down drowsy-but-awake sometimes, so falling asleep starts to feel normal.',
      'Follow wake windows (~45–90 min at this age) to avoid overtiredness.',
      'Expect 14–17 hrs of sleep across many short stretches; night waking is normal and expected.',
    ],
    tips: [
      'Learn baby’s tired cues (yawns, glazed stare, fussing) and act early.',
      'A consistent wind-down (dim lights, swaddle, feed, song) plants the seed of a routine.',
      'Take care of yourself — trade night shifts if you can. This phase is survival, not training.',
    ],
  },
  {
    key: 'foundations',
    title: 'Foundations — ready to begin',
    age_label: '4–6 months',
    minDays: 113, maxDays: 182,
    method: 'bedtime_fading',
    alt_methods: ['graduated_extinction', 'pick_up_put_down'],
    description: 'Around 4 months, many babies can start learning to fall asleep independently. This is the classic window to begin gentle sleep training — after a pediatrician okays it. A predictable bedtime routine is the single most important habit.',
    steps: [
      'Set a consistent bedtime and a short, same-every-night routine (bath, book, feed, bed).',
      'Put baby down awake in the crib so they practise falling asleep on their own.',
      'Pick ONE method and give it a consistent 1–2 weeks — inconsistency is what prolongs crying.',
      'Move toward a predictable 2–3 nap rhythm during the day.',
      'The 4-month sleep regression is real — hold your routine steady through it.',
    ],
    tips: [
      'Full feeds during the day reduce hunger-driven night waking.',
      'A dark room and white noise make independent sleep easier.',
      'Consistency between caregivers matters more than which method you choose.',
    ],
  },
  {
    key: 'consolidate',
    title: 'Consolidate — night sleep & naps',
    age_label: '6–12 months',
    minDays: 183, maxDays: 365,
    method: 'graduated_extinction',
    alt_methods: ['chair_method', 'full_extinction'],
    description: 'Most babies are developmentally capable of sleeping long stretches now and no longer need night feeds (confirm with your pediatrician). Naps consolidate toward two per day. Separation anxiety can cause new waking around 8–10 months.',
    steps: [
      'Keep bedtime and the wind-down routine rock-steady.',
      'If using graduated extinction, extend check-in intervals as baby learns to self-settle.',
      'Consolidate to ~2 naps; protect a reasonable awake window before bed.',
      'For 8–10 month separation-anxiety waking, reassure briefly but keep sleep rules consistent.',
      'Introduce a lovey/comfort object if age-appropriate and safe for your baby.',
    ],
    tips: [
      'A too-late bedtime often causes overtired night waking — earlier can be better.',
      'Sudden regressions often track teething, illness, or a developmental leap — ride them out.',
      'Once night feeds are medically unnecessary, gradually reduce their volume/duration.',
    ],
  },
  {
    key: 'toddler_transition',
    title: 'Toddler — one nap & independence',
    age_label: '12–18 months',
    minDays: 366, maxDays: 547,
    method: 'chair_method',
    alt_methods: ['graduated_extinction'],
    description: 'Toddlers typically drop to one longer midday nap in this window and assert more independence at bedtime. Firm, loving consistency prevents bedtime battles.',
    steps: [
      'Transition to a single ~1.5–3 hr midday nap when two no longer fit.',
      'Keep a clear, calm bedtime routine with a defined end ("last book, then sleep").',
      'Hold consistent limits on stalling, extra requests, and crib climbing.',
      'Expect a brief 18-month regression; keep the routine steady.',
      'Total sleep ~11–14 hrs including the nap.',
    ],
    tips: [
      'Offer small, age-appropriate choices (which pajamas) to satisfy the need for control.',
      'Cap the nap if it starts pushing bedtime too late.',
      'A visual bedtime chart helps toddlers know what comes next.',
    ],
  },
  {
    key: 'preschool_routine',
    title: 'Big feelings, big boundaries',
    age_label: '18 months – 3 years',
    minDays: 548, maxDays: 1095,
    method: 'silent_return',
    alt_methods: ['bedtime_pass', 'chair_method'],
    description: 'Imagination, independence, and testing limits all bloom now. Your child is likely on one nap and may start bargaining at bedtime. Kind, consistent boundaries carry this phase.',
    steps: [
      'Keep an unhurried, predictable wind-down; screens off ~1 hr before bed.',
      'Front-load the "one more" requests (water, hug, bathroom) into the routine.',
      'For get-ups, calmly walk them back with no talking or eye contact — every time.',
      'Keep offering the single nap (~5–6 hrs after waking); dropping it early often worsens nights.',
      'Delay the big-kid bed until ~3 — crib freedom usually makes sleep worse before better.',
    ],
    tips: [
      'A comfort object and a dim red/amber nightlight help new fears of the dark.',
      'Keep wake-up time consistent, even after rough nights, to protect the body clock.',
      'Offer 2–3 controlled choices (which pajamas, which book) to satisfy the need for control.',
    ],
  },
  {
    key: 'big_kid',
    title: 'Independent sleeper',
    age_label: '3–4 years',
    minDays: 1096, maxDays: 1826,
    method: 'bedtime_pass',
    alt_methods: ['silent_return'],
    description: 'Your child is becoming a confident, mostly-independent sleeper. The last nap is often dropping. Predictable routines and gentle accountability keep bedtime smooth.',
    steps: [
      'Hold a consistent bedtime and wake time, including weekends.',
      'Keep a calm, screen-free wind-down (screens off ~1 hr before bed).',
      'If the nap is gone, move bedtime earlier to protect 10–13 hrs total sleep.',
      'Use a bedtime pass for stalling; return silently for extra get-ups.',
      'Handle nightmares with brief comfort; talk about scary dreams in daytime.',
    ],
    tips: [
      'Let your child help decorate the bedtime pass — buy-in makes it work.',
      'Fade the pass by removing one per week as bedtimes settle.',
      'A predictable, consistent bedtime is the single strongest lever for good sleep.',
    ],
  },
];

// Parse YYYY-MM-DD → [y, m0, d] or null.
function parseYMD(birthdate) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(birthdate || '').slice(0, 10));
  if (!m) return null;
  return [Number(m[1]), Number(m[2]) - 1, Number(m[3])];
}

function todayParts(today) {
  if (today) {
    const p = parseYMD(today);
    if (p) return p;
  }
  const now = new Date();
  return [now.getFullYear(), now.getMonth(), now.getDate()];
}

// Compute whole-day age from a YYYY-MM-DD birthdate using UTC midnights so the
// result doesn't wobble with server timezone. Optional `today` (YYYY-MM-DD)
// keeps tests deterministic.
function ageInDays(birthdate, today) {
  const bornParts = parseYMD(birthdate);
  if (!bornParts) return null;
  const born = Date.UTC(bornParts[0], bornParts[1], bornParts[2]);
  const t = todayParts(today);
  const todayUtc = Date.UTC(t[0], t[1], t[2]);
  if (Number.isNaN(born)) return null;
  return Math.max(0, Math.floor((todayUtc - born) / 86400000));
}

// Calendar months old (what parents mean by "turned 6 months today") — not
// mean-solar-month arithmetic, which can undercount by one on anniversary days.
function ageInMonths(birthdate, today) {
  const born = parseYMD(birthdate);
  if (!born) return null;
  const t = todayParts(today);
  let months = (t[0] - born[0]) * 12 + (t[1] - born[1]);
  if (t[2] < born[2]) months -= 1;
  return Math.max(0, months);
}

function methodInfo(key) {
  return key && METHODS[key] ? METHODS[key] : null;
}

// The full program: every phase plus the method catalog, safe-sleep rules, and
// sources. Served to the client to render the guided template.
function template() {
  return {
    id: 'sleep-training',
    title: 'Sleep training, newborn to 4 years',
    subtitle: 'A gentle, evidence-based path to independent sleep — at your family’s pace.',
    disclaimer: 'Educational guidance, not medical advice. Every baby is different — check with your pediatrician before starting, and stop if your child is unwell.',
    safe_sleep: SAFE_SLEEP,
    methods: Object.values(METHODS),
    phases: PHASES.map(p => ({
      key: p.key, title: p.title, age_label: p.age_label,
      min_days: p.minDays, max_days: p.maxDays,
      method: methodInfo(p.method),
      alt_methods: (p.alt_methods || []).map(methodInfo).filter(Boolean),
      description: p.description, steps: p.steps, tips: p.tips,
    })),
    sources: SOURCES,
  };
}

// Given a baby's birthdate, return the current phase (with its method) plus
// age, and a nudge if formal training isn't age-appropriate yet.
// Optional `today` (YYYY-MM-DD) keeps age labels deterministic in tests.
function guidanceForBirthdate(birthdate, today) {
  const days = ageInDays(birthdate, today);
  if (days == null) return null;
  const weeks = Math.floor(days / 7);
  const months = ageInMonths(birthdate, today);
  const phase = PHASES.find(p => days >= p.minDays && days <= p.maxDays) || PHASES[PHASES.length - 1];
  return {
    age_days: days,
    age_weeks: weeks,
    age_months: months,
    ready_for_training: days >= 113, // ~16 weeks / 4 months
    current_phase: {
      key: phase.key, title: phase.title, age_label: phase.age_label,
      method: methodInfo(phase.method),
      alt_methods: (phase.alt_methods || []).map(methodInfo).filter(Boolean),
      description: phase.description, steps: phase.steps, tips: phase.tips,
    },
    safe_sleep: SAFE_SLEEP,
  };
}

// Typical awake stretches between sleeps, by age, in minutes.
//
// SOURCING NOTE, deliberately different from DURATION_BANDS in sleepStats.js:
// those come from the AASM/AAP consensus statement. Wake windows have no such
// consensus — they are widely used in pediatric sleep practice and parent
// guidance (see the NHS and sleep-training sources above), but they are a rule
// of thumb, not a standard. They are presented as "typical", never as a target,
// and the app says so wherever it uses them.
const WAKE_WINDOWS = [
  { minDays: 0, maxDays: 30, min: 45, max: 60, label: 'about 45–60 minutes' },
  { minDays: 31, maxDays: 60, min: 60, max: 90, label: 'about 1–1.5 hours' },
  { minDays: 61, maxDays: 105, min: 75, max: 105, label: 'about 1.5–2 hours' },
  { minDays: 106, maxDays: 180, min: 105, max: 150, label: 'about 2–2.5 hours' },
  { minDays: 181, maxDays: 273, min: 150, max: 180, label: 'about 2.5–3 hours' },
  { minDays: 274, maxDays: 365, min: 180, max: 240, label: 'about 3–4 hours' },
  { minDays: 366, maxDays: 547, min: 240, max: 300, label: 'about 4–5 hours' },
  { minDays: 548, maxDays: 1095, min: 300, max: 360, label: 'about 5–6 hours' },
];

/// The typical awake stretch for a child of this age, or null when there's no
/// birthdate to reason from — the caller must not invent one.
function wakeWindowForBirthdate(birthdate) {
  if (!birthdate) return null;
  const days = ageInDays(birthdate);
  if (days == null || days < 0) return null;
  const band = WAKE_WINDOWS.find(w => days >= w.minDays && days <= w.maxDays);
  // Past the last band a child is on one nap or none; a wake-window nudge stops
  // being useful, so return nothing rather than extrapolating.
  if (!band) return null;
  return { min_minutes: band.min, max_minutes: band.max, label: band.label };
}

module.exports = {
  template, guidanceForBirthdate, ageInDays, ageInMonths, wakeWindowForBirthdate,
  PHASES, METHODS, SAFE_SLEEP, SOURCES, WAKE_WINDOWS,
};
