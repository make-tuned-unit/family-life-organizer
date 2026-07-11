// Shared rivalry-completion announcement: builds the message, posts the feed
// item, and fires the win/loss/tie pushes. Used by BOTH the REST route
// (POST /api/rivalries/:id/complete) and the concierge tool (complete_rivalry)
// so ending a rivalry either way produces the same celebration.

function fmt(n) { return Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 }); }
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

const WINNER_MESSAGES = [
  (w, l, ws, ls, ct) => `${w} absolutely CRUSHED it with ${fmt(ws)} ${ct}! ${l} managed ${fmt(ls)}... we'll pretend that didn't happen`,
  (w, l, ws, ls, ct) => `Breaking news: ${w} defeats ${l} in an EPIC ${ct} showdown! Final score: ${fmt(ws)} to ${fmt(ls)}`,
  (w, l, ws, ls, ct) => `It's official: ${w} is the ${ct} champion with ${fmt(ws)}! ${l} came in at ${fmt(ls)}`,
  (w, l, ws, ls, ct) => `${w}: ${fmt(ws)} ${ct}. ${l}: ${fmt(ls)} ${ct}. The math speaks for itself.`,
  (w, l, ws, ls, ct) => `And the crown goes to ${w}! ${fmt(ws)} vs ${fmt(ls)} ${ct}. Well played.`,
  (w, l, ws, ls, ct) => `${w} wins by ${fmt(ws - ls)} ${ct}! Rematch, ${l}?`,
];
const TIE_MESSAGES = [
  (p1, p2, total, ct) => `It's a DEAD TIE! ${p1} and ${p2} both hit ${fmt(total)} ${ct}. Respect!`,
  (p1, p2, total, ct) => `Unbelievable! ${p1} and ${p2} tied at ${fmt(total)} ${ct} each. Run it back!`,
];
const WINNER_PUSH = [
  (l) => `You won! Nicely done against ${l}`,
  (l) => `Champion status: confirmed. You came out on top over ${l}`,
];
const LOSER_PUSH = [
  (w) => `${w} took this one. Rematch?`,
  (w) => `Tough loss — ${w} came out on top. Step it up next time!`,
];

function buildMessage(result) {
  const { rivalry, initiator_total, opponent_total, winner_name, winner_team } = result;
  const ct = rivalry.challenge_type === 'steps' ? 'steps' : rivalry.challenge_type;
  const parseRoster = (s) => { try { const p = JSON.parse(s || '[]'); return Array.isArray(p) ? p.filter(Boolean) : []; } catch (_) { return []; } };
  if (!winner_name) {
    return pick(TIE_MESSAGES)(rivalry.initiator_name, rivalry.opponent_name, initiator_total, ct);
  }
  let loser, ws, ls;
  if (rivalry.rivalry_type === 'team' && winner_team) {
    loser = parseRoster(winner_team === 'a' ? rivalry.team_b : rivalry.team_a).join(' & ')
      || (winner_team === 'a' ? rivalry.opponent_name : rivalry.initiator_name);
    ws = winner_team === 'a' ? initiator_total : opponent_total;
    ls = winner_team === 'a' ? opponent_total : initiator_total;
  } else {
    loser = winner_name === rivalry.initiator_name ? rivalry.opponent_name : rivalry.initiator_name;
    ws = winner_name === rivalry.initiator_name ? initiator_total : opponent_total;
    ls = winner_name === rivalry.initiator_name ? opponent_total : initiator_total;
  }
  return pick(WINNER_MESSAGES)(winner_name, loser, ws, ls, ct);
}

// db: FamilyDB, push: the push module (push.pushToUser), result: output of
// db.completeRivalryWithTotals, authorId: who triggered completion.
// Returns the completion message. No-ops the feed/push when already completed.
async function announceRivalryCompletion(db, push, result, authorId) {
  const { rivalry, winner_name, already_completed } = result;
  const message = buildMessage(result);
  if (already_completed) return message;

  if (rivalry.group_id) {
    try {
      await db.addFeedPost({
        group_id: rivalry.group_id, author_id: authorId, post_type: 'rivalry',
        title: winner_name ? `${winner_name} wins: ${rivalry.title}` : `Tie: ${rivalry.title}`,
        body: message, reference_type: 'rivalry', reference_id: rivalry.id,
      });
    } catch (e) { console.error('Rivalry feed post error:', e.message); }
  }
  try {
    if (winner_name) {
      const loser = winner_name === rivalry.initiator_name ? rivalry.opponent_name : rivalry.initiator_name;
      const winnerId = await db.getUserIdByName(winner_name);
      const loserId = await db.getUserIdByName(loser);
      if (winnerId) push.pushToUser(db, winnerId, 'You Won!', pick(WINNER_PUSH)(loser), { type: 'rivalry', ref_id: rivalry.id });
      if (loserId) push.pushToUser(db, loserId, 'Better Luck Next Time', pick(LOSER_PUSH)(winner_name), { type: 'rivalry', ref_id: rivalry.id });
    } else {
      const id1 = await db.getUserIdByName(rivalry.initiator_name);
      const id2 = await db.getUserIdByName(rivalry.opponent_name);
      const tieMsg = `It's a tie in "${rivalry.title}"! Run it back?`;
      if (id1) push.pushToUser(db, id1, 'Rivalry Tied!', tieMsg, { type: 'rivalry', ref_id: rivalry.id });
      if (id2) push.pushToUser(db, id2, 'Rivalry Tied!', tieMsg, { type: 'rivalry', ref_id: rivalry.id });
    }
  } catch (e) { console.error('Rivalry push error:', e.message); }
  return message;
}

module.exports = { announceRivalryCompletion, buildMessage };
