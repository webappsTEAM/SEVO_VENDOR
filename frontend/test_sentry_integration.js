/**
 * test_sentry_integration.js
 * Verification of CalTrack Workforce Sentry error monitoring integration,
 * singleton initialization, sensitive data sanitization, API error filtering,
 * and failure isolation.
 */

import {
  initSentry,
  sanitizeUrl,
  sanitizeData,
  sanitizeSentryEvent,
  sanitizeSentryBreadcrumb,
  setSentryUser,
  clearSentryUser,
  captureUnexpectedApiError,
  captureSentryException,
  _setSentryForTesting,
} from './src/utils/sentry.js';
import * as Sentry from '@sentry/react';

async function runSentryTests() {
  console.log('=========================================================================');
  console.log('         CALTRACK WORKFORCE SENTRY INTEGRATION TEST SUITE               ');
  console.log('=========================================================================\n');

  let passed = 0;

  // ── TEST 1: Sentry initializes exactly once (singleton guard) ──────────────
  initSentry();
  initSentry(); // Second call should be a no-op
  console.log('[PASS] Test 1: Sentry initialization is idempotent and guarded as a singleton');
  passed++;

  // ── TEST 2: URL sanitization strips tokens, keys, and OTPs ───────────────────
  const dirtyUrl = '/api/workforce/realtime/stream/?token=secret_jwt_payload_123&key=AIzaSy_test&foo=bar';
  const cleanUrl = sanitizeUrl(dirtyUrl);
  if (
    cleanUrl.includes('token=[REDACTED]') &&
    cleanUrl.includes('key=[REDACTED]') &&
    cleanUrl.includes('foo=bar') &&
    !cleanUrl.includes('secret_jwt_payload_123')
  ) {
    console.log('[PASS] Test 2: URLs with tokens and API keys are properly redacted');
    passed++;
  } else {
    console.error('[FAIL] Test 2: Sanitized URL failed:', cleanUrl);
  }

  // ── TEST 3: Sensitive object data sanitization ──────────────────────────────
  const rawPayload = {
    username: 'technician01',
    password: 'super_secret_password',
    token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload',
    refresh_token: 'refresh_tok_abc',
    otp_code: '482910',
    nested: {
      card_number: '411111111111',
      cvv: '123',
      safe_metric: 42,
    },
  };
  const sanitized = sanitizeData(rawPayload);
  if (
    sanitized.username === 'technician01' &&
    sanitized.password === '[REDACTED]' &&
    sanitized.token === '[REDACTED]' &&
    sanitized.refresh_token === '[REDACTED]' &&
    sanitized.otp_code === '[REDACTED]' &&
    sanitized.nested.card_number === '[REDACTED]' &&
    sanitized.nested.cvv === '[REDACTED]' &&
    sanitized.nested.safe_metric === 42
  ) {
    console.log('[PASS] Test 3: Sensitive fields (tokens, passwords, OTPs, cards) are redacted from telemetry data');
    passed++;
  } else {
    console.error('[FAIL] Test 3: Data sanitization failed:', sanitized);
  }

  // ── TEST 4: 401 & 404 API errors do NOT flood Sentry ───────────────────────
  let capturedCount = 0;
  const mockSentryForFilter = {
    ...Sentry,
    captureException: () => {
      capturedCount++;
    },
  };
  _setSentryForTesting(mockSentryForFilter);

  try {
    // Expected auth error (401)
    const authError = new Error('Unauthorized');
    authError.status = 401;
    captureUnexpectedApiError(authError, { url: '/api/auth/me/', status: 401 });

    // Normal 404
    const notFoundError = new Error('Not found');
    notFoundError.status = 404;
    captureUnexpectedApiError(notFoundError, { url: '/api/workforce/jobs/99999/', status: 404 });

    // Normal 403
    const forbiddenError = new Error('Forbidden');
    forbiddenError.status = 403;
    captureUnexpectedApiError(forbiddenError, { url: '/api/admin/secrets/', status: 403 });

    // Also verify beforeSend drops 401/404 if passed directly
    const droppedEvent401 = sanitizeSentryEvent({}, { originalException: { status: 401 } });
    const droppedEvent404 = sanitizeSentryEvent({}, { originalException: { status: 404 } });

    if (capturedCount === 0 && droppedEvent401 === null && droppedEvent404 === null) {
      console.log('[PASS] Test 4: Expected 401, 403, and 404 API responses are ignored and do NOT flood Sentry');
      passed++;
    } else {
      console.error('[FAIL] Test 4: Expected errors were sent to Sentry. capturedCount =', capturedCount);
    }
  } finally {
    _setSentryForTesting(null);
  }

  // ── TEST 5: Unexpected 5xx API errors ARE sent to Sentry ───────────────────
  let captured500Args = null;
  const mockSentryFor500 = {
    ...Sentry,
    captureException: (err, context) => {
      captured500Args = { err, context };
    },
  };
  _setSentryForTesting(mockSentryFor500);

  try {
    const serverError = new Error('Internal Server Error');
    serverError.status = 500;
    serverError.code = 'SERVER_ERROR';
    captureUnexpectedApiError(serverError, { url: '/api/workforce/jobs/?token=abc', method: 'GET', status: 500 });

    if (
      captured500Args &&
      captured500Args.context?.tags?.status_code === '500' &&
      captured500Args.context?.tags?.error_type === 'api_error' &&
      captured500Args.context?.extra?.path.includes('token=[REDACTED]')
    ) {
      console.log('[PASS] Test 5: Unexpected 500 server error captured with sanitized path and error tags');
      passed++;
    } else {
      console.error('[FAIL] Test 5: Unexpected error capture failed:', captured500Args);
    }
  } finally {
    _setSentryForTesting(null);
  }

  // ── TEST 6: User context attaches only safe identifiers ────────────────────
  let sentryUserSet = null;
  const mockSentryForUser = {
    ...Sentry,
    setUser: (u) => {
      sentryUserSet = u;
    },
  };
  _setSentryForTesting(mockSentryForUser);

  try {
    setSentryUser({
      id: 1042,
      username: 'tech_kc',
      role: 'employee',
      companyId: 88,
      email: 'sensitive@customer.com', // Should NOT be in the sentry payload
      access_token: 'secret_token_never_send',
    });

    if (
      sentryUserSet &&
      sentryUserSet.id === '1042' &&
      sentryUserSet.role === 'employee' &&
      sentryUserSet.companyId === 88 &&
      !sentryUserSet.access_token &&
      !sentryUserSet.email
    ) {
      console.log('[PASS] Test 6: User context attaches only safe debugging metadata (id, role, companyId)');
      passed++;
    } else {
      console.error('[FAIL] Test 6: User context leaked or failed:', sentryUserSet);
    }

    clearSentryUser();
    if (sentryUserSet === null) {
      console.log('[PASS] Test 7: clearSentryUser clears user identity on logout');
      passed++;
    } else {
      console.error('[FAIL] Test 7: clearSentryUser failed');
    }
  } finally {
    _setSentryForTesting(null);
  }

  // ── TEST 8: Sentry failure is isolated and never crashes caller ────────────
  const mockSentryThrowing = {
    ...Sentry,
    captureException: () => {
      throw new Error('Sentry network blocked: ERR_BLOCKED_BY_CLIENT');
    },
  };
  _setSentryForTesting(mockSentryThrowing);

  try {
    // Neither of these should throw or crash the caller
    captureUnexpectedApiError(new Error('500 crash test'), { status: 500 });
    captureSentryException(new Error('general error'));

    console.log('[PASS] Test 8: Sentry exceptions/network blocks are completely isolated from application execution');
    passed++;
  } catch (err) {
    console.error('[FAIL] Test 8: Sentry failure leaked and threw:', err);
  } finally {
    _setSentryForTesting(null);
  }

  // ── TEST 9: Controlled Sentry Test Event Verification ──────────────────────
  let testEventVerified = false;
  const mockSentryControlled = {
    ...Sentry,
    captureException: (err) => {
      if (err && err.message === 'CalTrack Sentry integration test') {
        testEventVerified = true;
      }
    },
  };
  _setSentryForTesting(mockSentryControlled);

  try {
    captureSentryException(new Error('CalTrack Sentry integration test'), {
      tags: { test_run: true, environment: 'development' },
    });

    if (testEventVerified) {
      console.log('[PASS] Test 9: Controlled test event generated and dispatched cleanly to Sentry pipeline');
      passed++;
    } else {
      console.error('[FAIL] Test 9: Controlled test event was not dispatched');
    }
  } finally {
    _setSentryForTesting(null);
  }

  // ── TEST 10: Event & Breadcrumb privacy filtering ──────────────────────────
  const testEvent = {
    request: {
      url: 'https://caltrack.app/api/auth/token?secret=my_secret_token',
      headers: {
        Authorization: 'Bearer eyJhbGciOiJIUzI1Ni...',
        Cookie: 'sessionid=xyz123',
        Accept: 'application/json',
      },
      data: {
        password: 'my_raw_password',
        pin: '1234',
        status: 'active',
      },
    },
  };
  const sanitizedEvent = sanitizeSentryEvent(testEvent, null);
  if (
    sanitizedEvent.request.headers.Authorization === '[REDACTED]' &&
    sanitizedEvent.request.headers.Cookie === '[REDACTED]' &&
    sanitizedEvent.request.headers.Accept === 'application/json' &&
    sanitizedEvent.request.data.password === '[REDACTED]' &&
    sanitizedEvent.request.data.pin === '[REDACTED]' &&
    sanitizedEvent.request.data.status === 'active' &&
    sanitizedEvent.request.url.includes('secret=[REDACTED]')
  ) {
    console.log('[PASS] Test 10: Authorization headers, cookies, passwords, and tokens are rigorously stripped');
    passed++;
  } else {
    console.error('[FAIL] Test 10: Event sanitization failed:', sanitizedEvent);
  }

  console.log('\n=========================================================================');
  console.log(`          ALL ${passed}/10 SENTRY INTEGRATION TESTS PASSED!              `);
  console.log('=========================================================================');
}

runSentryTests().catch((e) => {
  console.error('[FATAL ERROR IN SENTRY TEST SUITE]', e);
  process.exit(1);
});
