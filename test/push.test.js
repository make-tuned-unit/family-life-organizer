// Push helpers are fire-and-forget from HTTP handlers. Failures must log,
// not reject, so an APNs blip cannot 500 the request that already succeeded.

const { test } = require('node:test');
const assert = require('node:assert');
const push = require('../push');

test('pushToUser swallows token-lookup failures instead of throwing', async () => {
  await assert.doesNotReject(() =>
    push.pushToUser(
      { getDeviceTokens() { return Promise.reject(new Error('db down')); } },
      1, 'Title', 'Body'
    )
  );
});

test('pushToGroup swallows member-lookup failures instead of throwing', async () => {
  await assert.doesNotReject(() =>
    push.pushToGroup(
      { getGroupMembers() { return Promise.reject(new Error('db down')); } },
      1, 99, 'Title', 'Body'
    )
  );
});
