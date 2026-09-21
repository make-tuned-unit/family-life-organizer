// Only loaded explicitly by apple-signin.test.js with Node --require.
// The production server contains no fake provider endpoint or switch.
const crypto = require('node:crypto');
const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
process.env.APPLE_SIGNIN_TEAM_ID = 'TESTTEAM';
process.env.APPLE_SIGNIN_KEY_ID = 'TESTKEY';
process.env.APPLE_SIGNIN_KEY_BASE64 = Buffer.from(privateKey.export({ format: 'pem', type: 'pkcs8' })).toString('base64');
const realFetch = global.fetch;
global.fetch = async (url, opts) => {
  if (url === 'https://appleid.apple.com/auth/token') {
    const code = new URLSearchParams(opts.body).get('code');
    const fail = code.startsWith('fail-revoke:');
    return new Response(JSON.stringify({ id_token: fail ? code.slice('fail-revoke:'.length) : code, refresh_token: fail ? 'fail' : 'fixture-refresh' }));
  }
  if (url === 'https://appleid.apple.com/auth/revoke') {
    const token = new URLSearchParams(opts.body).get('token');
    return new Response(null, { status: token === 'fail' ? 503 : 200 });
  }
  return realFetch(url, opts);
};
