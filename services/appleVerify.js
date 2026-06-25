// Verifies a StoreKit 2 signed transaction (JWSTransaction).
//
// A JWSTransaction is a JWS (header.payload.signature) signed with ES256 by an
// Apple-issued certificate, whose chain is carried in the header `x5c`. We:
//   1. verify the signature with the leaf certificate's public key, and
//   2. (when an Apple root cert is configured) verify the x5c chain up to it.
// Then we return the decoded transaction payload.
//
// The Apple Root CA - G3 trust anchor is embedded below, so the full chain is
// always enforced. Override it with APPLE_ROOT_CA_BASE64 if Apple rotates roots.

const crypto = require('crypto');

// Apple Root CA - G3 (the StoreKit JWS trust anchor), base64 DER. Embedded so
// chain verification works out of the box; override with APPLE_ROOT_CA_BASE64.
const APPLE_ROOT_CA_G3 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==';

function b64urlToBuffer(str) {
  return Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function decodeSegment(seg) {
  return JSON.parse(b64urlToBuffer(seg).toString('utf8'));
}

function certFromX5c(b64der) {
  return new crypto.X509Certificate(Buffer.from(b64der, 'base64'));
}

// Reject a cert that is not currently within its validity window.
function assertNotExpired(cert) {
  const now = Date.now();
  const from = Date.parse(cert.validFrom);
  const to = Date.parse(cert.validTo);
  if (!Number.isNaN(from) && now < from) throw new Error('Certificate not yet valid');
  if (!Number.isNaN(to) && now > to) throw new Error('Certificate has expired');
}

// Verify each cert in the chain is signed by the next, the top is the root, and
// every cert is within its validity window (Node's verify() checks signatures
// only, not expiry).
function verifyChain(x5c, rootCertBase64) {
  const root = certFromX5c(rootCertBase64);
  const chain = x5c.map(certFromX5c);
  for (const cert of chain) assertNotExpired(cert);
  for (let i = 0; i < chain.length - 1; i++) {
    if (!chain[i].verify(chain[i + 1].publicKey)) {
      throw new Error('Certificate chain verification failed');
    }
  }
  const top = chain[chain.length - 1];
  if (top.fingerprint256 !== root.fingerprint256 && !top.verify(root.publicKey)) {
    throw new Error('Certificate chain does not terminate at the Apple root');
  }
}

// Verify a JWS and return its decoded payload. Throws on any failure.
function verifyTransaction(jws, { bundleId, rootCertBase64 = process.env.APPLE_ROOT_CA_BASE64 || APPLE_ROOT_CA_G3 } = {}) {
  if (typeof jws !== 'string') throw new Error('Transaction must be a JWS string');
  const [h, p, s] = jws.split('.');
  if (!h || !p || !s) throw new Error('Malformed transaction JWS');

  const header = decodeSegment(h);
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length === 0) throw new Error('Missing x5c certificate chain');

  // 1. Signature: ES256 over `header.payload` using the leaf cert's public key.
  const leaf = certFromX5c(x5c[0]);
  const signatureOk = crypto.verify(
    'sha256',
    Buffer.from(`${h}.${p}`),
    { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' },
    b64urlToBuffer(s)
  );
  if (!signatureOk) throw new Error('Invalid transaction signature');

  // 2. Chain to the Apple root (when configured).
  verifyChain(x5c, rootCertBase64);

  const payload = decodeSegment(p);
  if (bundleId && payload.bundleId && payload.bundleId !== bundleId) {
    throw new Error('Transaction bundle id does not match');
  }
  return payload;
}

module.exports = { verifyTransaction };
