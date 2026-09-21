// Local text checks keep private family content off third-party moderation APIs.
// This is a conservative baseline, not a substitute for reviewing reports or
// image moderation. Do not log the rejected content.
function assertAcceptableText(...values) {
  const text = values.filter(x => typeof x === 'string').join(' ').normalize('NFKC').replace(/[\u200b-\u200f\ufeff]/g, '').toLowerCase();
  const prohibited = [
    /\b(?:i(?:'m| am)? (?:going to |will )?(?:kill|murder|rape) you|you should kill yourself)\b/,
    /\b(?:child|childrens?|underage)\s+(?:porn|pornography)\b/,
  ];
  if (prohibited.some(rule => rule.test(text))) {
    const e = new Error('This content cannot be posted. Please remove threats or prohibited sexual content.');
    e.code = 'CONTENT_REJECTED';
    throw e;
  }
}
// Both columns are internal SQL expressions; userId is always validated.
function visibleAuthor(author, userId) {
  const uid = Number(userId);
  if (!Number.isSafeInteger(uid) || uid < 1) throw new Error('Viewer is required');
  return `NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE (ub.blocker_id = ${uid} AND ub.blocked_id = ${author}) OR (ub.blocked_id = ${uid} AND ub.blocker_id = ${author}))`;
}
module.exports = { assertAcceptableText, visibleAuthor };
