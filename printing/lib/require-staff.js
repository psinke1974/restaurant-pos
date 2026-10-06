'use strict';

/**
 * Express middleware that only lets signed-in POS staff through.
 *
 * The POS frontend sends the SurrealDB session token it got at login as
 * `Authorization: Bearer <token>`. We ask SurrealDB whose token it is
 * (`RETURN $auth`), so expired tokens and deleted users are rejected by the
 * database itself. Results are cached briefly to keep this off the hot path.
 *
 * Env:
 *   POS_AUTH_DB_URL     SurrealDB URL (ws://, wss://, http:// or https://, /rpc optional).
 *                       Falls back to SURREAL_URL.
 *   POS_AUTH_DISABLED   "true" skips the check (only for an isolated machine).
 *
 * Keep the copies in api/, payments/, printing/ and tracking-api/ identical.
 */

const CACHE_MS = 60 * 1000;
const MAX_CACHE_ENTRIES = 500;
const cache = new Map();

function authDbBaseUrl() {
  const raw = String(process.env.POS_AUTH_DB_URL || process.env.SURREAL_URL || '').trim();
  if (!raw) {
    return '';
  }
  return raw
    .replace(/^ws(s?):\/\//, 'http$1://')
    .replace(/\/rpc\/?$/, '')
    .replace(/\/$/, '');
}

function bearerToken(req) {
  const header = req.get('authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

async function lookupStaffUser(baseUrl, token) {
  const res = await fetch(`${baseUrl}/sql`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    body: 'RETURN $auth',
  });
  if (res.status === 401 || res.status === 403) {
    return null;
  }
  if (!res.ok) {
    throw new Error(`SurrealDB answered ${res.status}`);
  }
  const [first] = await res.json();
  return first && first.status === 'OK' && first.result ? String(first.result) : null;
}

function rememberUser(token, user) {
  if (cache.size >= MAX_CACHE_ENTRIES) {
    const now = Date.now();
    for (const [key, entry] of cache) {
      if (entry.expires <= now) cache.delete(key);
    }
    if (cache.size >= MAX_CACHE_ENTRIES) cache.clear();
  }
  cache.set(token, { user, expires: Date.now() + CACHE_MS });
}

function requireStaff(req, res, next) {
  if (process.env.POS_AUTH_DISABLED === 'true') {
    return next();
  }

  const baseUrl = authDbBaseUrl();
  if (!baseUrl) {
    return res.status(503).json({
      success: false,
      error: 'Staff authentication is not configured: set POS_AUTH_DB_URL',
    });
  }

  const token = bearerToken(req);
  if (!token) {
    return res.status(401).json({ success: false, error: 'Sign in to the POS first' });
  }

  const cached = cache.get(token);
  if (cached && cached.expires > Date.now()) {
    req.staffUserId = cached.user;
    return next();
  }

  lookupStaffUser(baseUrl, token)
    .then((user) => {
      if (!user) {
        cache.delete(token);
        return res.status(401).json({ success: false, error: 'Session expired, sign in again' });
      }
      rememberUser(token, user);
      req.staffUserId = user;
      return next();
    })
    .catch((err) => {
      console.error('Staff authentication check failed:', err && err.message ? err.message : err);
      res.status(503).json({ success: false, error: 'Could not verify the POS session' });
    });
}

module.exports = { requireStaff };
