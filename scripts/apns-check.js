#!/usr/bin/env node
/**
 * APNs configuration check.
 *
 * Push is silently disabled unless APNS_KEY_ID, APNS_TEAM_ID and
 * APNS_KEY_BASE64 are all set — correct in production, maddening when you are
 * trying to find out why no notification arrived. This says out loud what the
 * server believes, and can prove the whole path end to end by sending one real
 * push through the same code real pushes use.
 *
 *   node scripts/apns-check.js                    # config only, talks to nobody
 *   node scripts/apns-check.js --token <hex>      # ...and send one test push
 *   node scripts/apns-check.js --user 1           # ...to every device of user 1
 *
 * Run it against production by exporting the same env vars the server has.
 */

const push = require('../push');

const args = process.argv.slice(2);
const argOf = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
};

const GREEN = '\x1b[32m', RED = '\x1b[31m', DIM = '\x1b[2m', YELLOW = '\x1b[33m', OFF = '\x1b[0m';
const tick = (ok) => (ok ? `${GREEN}✓${OFF}` : `${RED}✗${OFF}`);

async function tokensForUser(userId) {
  const FamilyDB = require('../database');
  const db = new FamilyDB();
  try {
    return (await db.getDeviceTokens(userId)).map(r => r.token);
  } finally {
    db.close();
  }
}

(async () => {
  const cfg = push.describeConfig();

  console.log('\nAPNs configuration');
  console.log('──────────────────');
  console.log(`  ${tick(!!cfg.keyId)} APNS_KEY_ID        ${cfg.keyId || `${DIM}(unset)${OFF}`}`);
  console.log(`  ${tick(!!cfg.teamId)} APNS_TEAM_ID       ${cfg.teamId || `${DIM}(unset)${OFF}`}`);
  console.log(`  ${tick(cfg.hasKey)} APNS_KEY_BASE64    ${cfg.hasKey ? `${DIM}set${OFF}` : `${DIM}(unset)${OFF}`}`);
  console.log(`  ${tick(cfg.keyParses)} key parses         ${cfg.keyParses ? `${DIM}valid EC private key${OFF}` : `${RED}${cfg.keyError || 'no key'}${OFF}`}`);
  console.log(`    ${DIM}apns-topic${OFF}         ${cfg.bundleId}`);
  console.log(`    ${DIM}primary host${OFF}       ${cfg.primaryHost} ${DIM}(falls back to ${cfg.alternateHost} per token)${OFF}`);

  if (!cfg.configured || !cfg.keyParses) {
    console.log(`\n${RED}Push is OFF.${OFF} The server will skip every notification without a word.`);
    console.log(`${DIM}Set the three vars above; base64 the .p8 with:${OFF}`);
    console.log(`  base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\\n'\n`);
    process.exit(1);
  }
  console.log(`\n${GREEN}Configured.${OFF} A JWT can be minted from this key.`);

  // The topic must equal the app's bundle ID or APNs rejects with DeviceTokenNotForTopic.
  if (cfg.bundleId !== 'com.kinrows.app') {
    console.log(`${YELLOW}Note:${OFF} apns-topic is "${cfg.bundleId}", not the app's bundle ID (com.kinrows.app).`);
  }

  let tokens = [];
  const token = argOf('--token');
  const user = argOf('--user');
  if (token) tokens = [token];
  else if (user) {
    tokens = await tokensForUser(parseInt(user, 10));
    if (!tokens.length) {
      console.log(`\n${YELLOW}No device tokens registered for user ${user}.${OFF} Open the app on a device and allow notifications first.\n`);
      return;
    }
  } else {
    console.log(`${DIM}\nPass --token <hex> or --user <id> to send a real test push.${OFF}\n`);
    return;
  }

  console.log(`\nSending a test push to ${tokens.length} device${tokens.length === 1 ? '' : 's'}…`);
  for (const t of tokens) {
    const short = `${t.slice(0, 8)}…`;
    const res = await push.sendTest(t, { title: 'Kinrows', body: 'Push is working.' });
    if (res.ok) {
      const note = res.fellBackFrom ? ` ${DIM}(via ${res.host} — this device is a ${res.host.includes('sandbox') ? 'debug' : 'release'} build)${OFF}` : '';
      console.log(`  ${tick(true)} ${short} delivered to APNs${note}`);
    } else {
      console.log(`  ${tick(false)} ${short} ${RED}${res.reason || res.status || 'failed'}${OFF} ${DIM}${explain(res.reason)}${OFF}`);
    }
  }
  console.log('');
})();

/// APNs reasons are terse and the fix is rarely obvious from the word alone.
function explain(reason) {
  switch (reason) {
    case 'BadDeviceToken':
    case 'BadEnvironmentKeyInToken':
      return '— token belongs to the other APNs environment, and the fallback host also refused it. Usually a stale token from the old bundle ID.';
    case 'DeviceTokenNotForTopic':
      return '— the token was minted for a different bundle ID. Reinstall the app so it registers under com.kinrows.app.';
    case 'ExpiredProviderToken':
    case 'InvalidProviderToken':
      return '— APNS_KEY_ID/APNS_TEAM_ID do not match the key, or the key was revoked. Check the key belongs to team Z58XSBM78S.';
    case 'TopicDisallowed':
      return '— either Push is not enabled on this App ID, or the key is topic-restricted to other apps. '
           + 'A key shared across a team must be scoped "Sandbox & Production", not limited to specific topics.';
    case 'Unregistered':
      return '— the app was uninstalled from this device; the server should drop this token.';
    case 'connect_error':
      return '— could not reach APNs. Network or firewall.';
    default:
      return '';
  }
}
