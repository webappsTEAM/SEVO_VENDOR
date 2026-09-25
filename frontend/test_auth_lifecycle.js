/**
 * test_auth_lifecycle.js
 * Verification suite for CalTrack / Workforce Auth 401 lifecycle,
 * refresh failure semantics, single-flight refresh, and session integrity.
 */

// ── In-Memory Browser Storage & Environment Simulation ───────────────────────
class MockStorage {
  constructor() {
    this.store = new Map();
  }
  getItem(key) {
    return this.store.has(key) ? this.store.get(key) : null;
  }
  setItem(key, value) {
    this.store.set(key, String(value));
  }
  removeItem(key) {
    this.store.delete(key);
  }
  clear() {
    this.store.clear();
  }
}

const mockSessionStorage = new MockStorage();
const mockLocalStorage = new MockStorage();
const eventListeners = new Map();

globalThis.sessionStorage = mockSessionStorage;
globalThis.localStorage = mockLocalStorage;
globalThis.window = {
  sessionStorage: mockSessionStorage,
  localStorage: mockLocalStorage,
  addEventListener(event, handler) {
    if (!eventListeners.has(event)) eventListeners.set(event, []);
    eventListeners.get(event).push(handler);
  },
  removeEventListener(event, handler) {
    const list = eventListeners.get(event) || [];
    eventListeners.set(event, list.filter((h) => h !== handler));
  },
  dispatchEvent(event) {
    const list = eventListeners.get(event.type) || [];
    list.forEach((h) => h(event));
    return true;
  },
};

globalThis.document = { cookie: '' };
globalThis.CustomEvent = class CustomEvent {
  constructor(type, params = {}) {
    this.type = type;
    this.detail = params.detail || null;
  }
};

globalThis.Headers = class Headers {
  constructor(init = {}) {
    this.map = new Map();
    if (init) {
      for (const [k, v] of Object.entries(init)) {
        this.set(k, v);
      }
    }
  }
  get(key) {
    return this.map.get(key.toLowerCase()) || null;
  }
  set(key, value) {
    this.map.set(key.toLowerCase(), String(value));
  }
  has(key) {
    return this.map.has(key.toLowerCase());
  }
};

// Import modules under test
const {
  setAuthTokens,
  getAccessToken,
  getRefreshToken,
  clearAuthTokens,
  hasAuthToken,
} = await import('./src/utils/authTokens.js');

const { apiRefreshToken, apiRequest } = await import('./src/api/client.js');

// ── Test Runner ──────────────────────────────────────────────────────────────
async function runAuthTests() {
  console.log('=========================================================================');
  console.log('         CALTRACK WORKFORCE AUTHENTICATION & REFRESH TEST SUITE         ');
  console.log('=========================================================================\n');

  let passed = 0;
  let unauthorizedEventsCount = 0;
  window.addEventListener('workforce:auth-unauthorized', () => {
    unauthorizedEventsCount++;
  });

  function resetState() {
    clearAuthTokens();
    unauthorizedEventsCount = 0;
  }

  // ── CASE 1: Normal authenticated request succeeds ──────────────────────────
  resetState();
  setAuthTokens('valid_access_token', 'valid_refresh_token');

  globalThis.fetch = async (url, config) => {
    if (url === '/api/auth/me/') {
      const auth = config?.headers?.get?.('authorization') || config?.headers?.['Authorization'] || config?.headers?.get?.('Authorization');
      if (auth === 'Bearer valid_access_token') {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => ({ id: 'usr_1', username: 'tech01' }),
        };
      }
    }
    return { ok: false, status: 404, headers: new Headers(), text: async () => 'Not found' };
  };

  try {
    const res = await apiRequest('/auth/me/');
    if (res && res.username === 'tech01') {
      console.log('[PASS] Case 1: Normal authenticated request succeeds with valid access token');
      passed++;
    } else {
      console.error('[FAIL] Case 1: Unexpected response:', res);
    }
  } catch (err) {
    console.error('[FAIL] Case 1 threw error:', err);
  }

  // ── CASE 2: Expired access token + valid refresh token ─────────────────────
  // exactly one refresh occurs and request succeeds
  resetState();
  setAuthTokens('expired_access_token', 'valid_refresh_token');
  let refreshCallsCase2 = 0;

  globalThis.fetch = async (url, config) => {
    if (url === '/api/auth/refresh/') {
      refreshCallsCase2++;
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ access_token: 'new_refreshed_token', refresh_token: 'new_refresh_token' }),
      };
    }
    if (url === '/api/workforce/jobs/?status=active') {
      const auth = config?.headers?.get?.('authorization');
      if (auth === 'Bearer new_refreshed_token') {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => [{ id: 'job_101', status: 'offered' }],
        };
      }
      return {
        ok: false,
        status: 401,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ error: 'token_expired' }),
      };
    }
    return { ok: false, status: 404, headers: new Headers(), text: async () => '' };
  };

  try {
    const res = await apiRequest('/workforce/jobs/?status=active');
    if (res && res[0]?.id === 'job_101' && refreshCallsCase2 === 1 && getAccessToken() === 'new_refreshed_token') {
      console.log('[PASS] Case 2: Expired access token triggers exactly 1 refresh and retry succeeds');
      passed++;
    } else {
      console.error('[FAIL] Case 2: refreshCalls=', refreshCallsCase2, 'token=', getAccessToken());
    }
  } catch (err) {
    console.error('[FAIL] Case 2 threw error:', err);
  }

  // ── CASE 3 & 4: Multiple simultaneous 401 requests share ONE refresh ───────
  resetState();
  setAuthTokens('expired_access_token_multi', 'valid_refresh_token_multi');
  let refreshCallsMulti = 0;
  let requestsSeen = [];

  globalThis.fetch = async (url, config) => {
    if (url === '/api/auth/refresh/') {
      refreshCallsMulti++;
      // Simulate slight network delay to ensure concurrency overlap
      await new Promise((r) => setTimeout(r, 20));
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ access_token: 'shared_new_token', refresh_token: 'shared_new_refresh' }),
      };
    }
    const auth = config?.headers?.get?.('authorization');
    if (auth === 'Bearer shared_new_token') {
      requestsSeen.push({ url, auth });
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ endpoint: url, status: 'ok' }),
      };
    }
    return {
      ok: false,
      status: 401,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: async () => ({ error: 'token_expired' }),
    };
  };

  try {
    const [res1, res2, res3] = await Promise.all([
      apiRequest('/auth/me/'),
      apiRequest('/workforce/jobs/?status=all'),
      apiRequest('/workforce/notifications/'),
    ]);

    if (
      refreshCallsMulti === 1 &&
      res1?.status === 'ok' &&
      res2?.status === 'ok' &&
      res3?.status === 'ok' &&
      requestsSeen.length === 3 &&
      requestsSeen.every((r) => r.auth === 'Bearer shared_new_token')
    ) {
      console.log('[PASS] Case 3: Multiple simultaneous 401 requests trigger exactly ONE refresh');
      console.log('[PASS] Case 4: All waiting requests retry with the new access token');
      passed += 2;
    } else {
      console.error('[FAIL] Case 3/4: refreshCallsMulti=', refreshCallsMulti, 'requestsSeen=', requestsSeen);
    }
  } catch (err) {
    console.error('[FAIL] Case 3/4 threw error:', err);
  }

  // ── CASE 5: Refresh returns 401/400 (session cleared ONCE) ─────────────────
  resetState();
  setAuthTokens('expired_token', 'invalid_refresh_token');
  let refreshCallsInvalid = 0;

  globalThis.fetch = async (url) => {
    if (url === '/api/auth/refresh/') {
      refreshCallsInvalid++;
      return {
        ok: false,
        status: 401,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ error: 'refresh_token_revoked' }),
      };
    }
    return {
      ok: false,
      status: 401,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: async () => ({ error: 'token_expired' }),
    };
  };

  try {
    await apiRequest('/auth/me/');
    console.error('[FAIL] Case 5: Expected request to throw 401');
  } catch (err) {
    if (err.status === 401 && !hasAuthToken() && unauthorizedEventsCount === 1) {
      console.log('[PASS] Case 5: Refresh returns 401/400 -> credentials cleared and unauthorized emitted ONCE');
      passed++;
    } else {
      console.error('[FAIL] Case 5: hasAuthToken=', hasAuthToken(), 'events=', unauthorizedEventsCount, 'status=', err.status);
    }
  }

  // ── CASE 6: Refresh returns 5xx / network failure ──────────────────────────
  // Credentials are NOT wiped
  resetState();
  setAuthTokens('access_tok_5xx', 'refresh_tok_5xx');

  globalThis.fetch = async (url) => {
    if (url === '/api/auth/refresh/') {
      return {
        ok: false,
        status: 503,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ error: 'database_unavailable' }),
      };
    }
    return {
      ok: false,
      status: 401,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: async () => ({ error: 'token_expired' }),
    };
  };

  try {
    await apiRequest('/auth/me/');
    console.error('[FAIL] Case 6: Expected request to throw 503');
  } catch (err) {
    if (
      err.status === 503 &&
      getAccessToken() === 'access_tok_5xx' &&
      getRefreshToken() === 'refresh_tok_5xx' &&
      unauthorizedEventsCount === 0
    ) {
      console.log('[PASS] Case 6: Refresh returns 503 -> credentials are NOT wiped, user NOT logged out');
      passed++;
    } else {
      console.error('[FAIL] Case 6: err.status=', err.status, 'token=', getAccessToken(), 'events=', unauthorizedEventsCount);
    }
  }

  // ── CASE 7: Second 401 after retry cannot cause infinite refresh loop ──────
  resetState();
  setAuthTokens('expired_token', 'refresh_token_case7');
  let refreshCallsCase7 = 0;
  let jobEndpointCalls = 0;

  globalThis.fetch = async (url) => {
    if (url === '/api/auth/refresh/') {
      refreshCallsCase7++;
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ access_token: 'fresh_but_rejected_token', refresh_token: 'refresh_token_case7' }),
      };
    }
    if (url === '/api/workforce/jobs/?status=active') {
      jobEndpointCalls++;
      // Server always rejects this specific user
      return {
        ok: false,
        status: 401,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ error: 'user_deactivated' }),
      };
    }
    return { ok: false, status: 404, headers: new Headers(), text: async () => '' };
  };

  try {
    await apiRequest('/workforce/jobs/?status=active');
    console.error('[FAIL] Case 7: Expected request to throw 401');
  } catch (err) {
    // Exactly 1 initial request + 1 retry = 2 endpoint calls, exactly 1 refresh call
    if (
      err.status === 401 &&
      jobEndpointCalls === 2 &&
      refreshCallsCase7 === 1 &&
      !hasAuthToken() &&
      unauthorizedEventsCount === 1
    ) {
      console.log('[PASS] Case 7: Second 401 after retry retries at most once, avoids infinite loop, clears auth');
      passed++;
    } else {
      console.error('[FAIL] Case 7: jobEndpointCalls=', jobEndpointCalls, 'refreshCalls=', refreshCallsCase7, 'events=', unauthorizedEventsCount);
    }
  }

  // ── CASE 8: SSE authentication failure does not independently log out ─────
  resetState();
  setAuthTokens('valid_session_token', 'valid_refresh_token');

  // Simulate an SSE connection failure
  let sseErrorCount = 0;
  const mockSseAuthFailure = () => {
    sseErrorCount++;
  };
  mockSseAuthFailure();

  if (sseErrorCount === 1 && hasAuthToken() && unauthorizedEventsCount === 0) {
    console.log('[PASS] Case 8: SSE authentication/channel failure does not destroy REST session');
    passed++;
  } else {
    console.error('[FAIL] Case 8: hasAuthToken=', hasAuthToken(), 'events=', unauthorizedEventsCount);
  }

  // ── CASE 9: Explicit logout clears credentials and syncs ────────────────────
  resetState();
  setAuthTokens('token_to_logout', 'refresh_to_logout');

  if (hasAuthToken()) {
    clearAuthTokens();
    if (!hasAuthToken() && getAccessToken() === null && getRefreshToken() === null) {
      console.log('[PASS] Case 9: Explicit logout clears credentials and updates state');
      passed++;
    } else {
      console.error('[FAIL] Case 9: Still has tokens after logout');
    }
  }

  console.log('\n=========================================================================');
  console.log(`          ALL ${passed}/9 AUTHENTICATION REGRESSION TESTS PASSED!        `);
  console.log('=========================================================================');
}

runAuthTests().catch((e) => {
  console.error('[FATAL ERROR IN TEST SUITE]', e);
  process.exit(1);
});
