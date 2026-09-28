/**
 * sentry.js
 * Centralized, production-grade Sentry integration for CalTrack Workforce.
 *
 * Requirements:
 * 1. Initialized exactly once at the bootstrap level.
 * 2. Environment-configured (development, staging, production) via Vite.
 * 3. Never sends tokens, passwords, OTPs, or payment credentials.
 * 4. Filters out expected auth flows (401, token refresh, normal 404).
 * 5. Isolated: Sentry telemetry failure (e.g. ERR_BLOCKED_BY_CLIENT) never affects app operations.
 */

import React from 'react';
import * as Sentry from '@sentry/react';

let isInitialized = false;
let sentryClient = Sentry;

export function _setSentryForTesting(mock) {
  sentryClient = mock || Sentry;
}

// Sensitive keys to redact from any context, headers, or breadcrumbs
const SENSITIVE_KEY_REGEX = /(token|jwt|auth|password|secret|bearer|otp|credential|card|cvv|pan|pin|api_?key|key)/i;

/**
 * Sanitizes URLs to strip access tokens, keys, or OTPs from query strings.
 */
export function sanitizeUrl(url) {
  if (!url || typeof url !== 'string') return '';
  try {
    const parsed = new URL(url, 'http://localhost');
    const searchParams = new URLSearchParams(parsed.search);
    for (const [key] of searchParams.entries()) {
      if (SENSITIVE_KEY_REGEX.test(key)) {
        searchParams.set(key, '[REDACTED]');
      }
    }
    const cleanSearch = decodeURIComponent(searchParams.toString());
    return parsed.pathname + (cleanSearch ? `?${cleanSearch}` : '');
  } catch (_) {
    return url.replace(/([?&])(token|key|secret|auth)=[^&]+/gi, '$1$2=[REDACTED]');
  }
}

/**
 * Recursively redacts sensitive keys from objects.
 */
export function sanitizeData(data, depth = 0) {
  if (depth > 4 || !data || typeof data !== 'object') return data;
  if (Array.isArray(data)) {
    return data.map((item) => sanitizeData(item, depth + 1));
  }
  const sanitized = {};
  for (const [key, value] of Object.entries(data)) {
    if (SENSITIVE_KEY_REGEX.test(key)) {
      sanitized[key] = '[REDACTED]';
    } else if (typeof value === 'object' && value !== null) {
      sanitized[key] = sanitizeData(value, depth + 1);
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

/**
 * Filters and sanitizes events before they leave the browser.
 */
export function sanitizeSentryEvent(event, hint) {
  try {
    // 1. Filter out expected non-error states
    const error = hint?.originalException;
    if (error) {
      const status = error.status || error.statusCode || (error.response && error.response.status);
      // Never report expected authentication challenges or standard 404s
      if (status === 401 || status === 404 || status === 403) {
        return null;
      }
      if (error.code === 'AUTHENTICATION_REQUIRED' || error.name === 'AbortError') {
        return null;
      }
    }

    // 2. Sanitize request information if present
    if (event.request) {
      if (event.request.url) {
        event.request.url = sanitizeUrl(event.request.url);
      }
      if (event.request.headers) {
        const headers = { ...event.request.headers };
        for (const key of Object.keys(headers)) {
          if (SENSITIVE_KEY_REGEX.test(key) || key.toLowerCase() === 'authorization' || key.toLowerCase() === 'cookie') {
            headers[key] = '[REDACTED]';
          }
        }
        event.request.headers = headers;
      }
      if (event.request.data) {
        event.request.data = sanitizeData(event.request.data);
      }
    }

    // 3. Sanitize breadcrumbs
    if (Array.isArray(event.breadcrumbs)) {
      event.breadcrumbs = event.breadcrumbs.map((b) => sanitizeSentryBreadcrumb(b, null)).filter(Boolean);
    }

    // 4. Sanitize extra data
    if (event.extra) {
      event.extra = sanitizeData(event.extra);
    }

    return event;
  } catch (_) {
    return event;
  }
}

/**
 * Sanitizes breadcrumbs to prevent logging auth tokens or sensitive request payloads.
 */
export function sanitizeSentryBreadcrumb(breadcrumb) {
  try {
    if (!breadcrumb) return null;

    if (breadcrumb.data) {
      if (breadcrumb.data.url) {
        breadcrumb.data.url = sanitizeUrl(breadcrumb.data.url);
      }
      breadcrumb.data = sanitizeData(breadcrumb.data);
    }

    // If an API breadcrumb reports 401 (normal refresh flow), keep it as info but sanitized
    if (breadcrumb.category === 'fetch' || breadcrumb.category === 'xhr') {
      if (breadcrumb.data?.status_code === 401) {
        breadcrumb.level = 'info';
      }
    }

    return breadcrumb;
  } catch (_) {
    return breadcrumb;
  }
}

/**
 * Single Authoritative Sentry Initialization.
 * Invoked once at application bootstrap before ReactDOM renders.
 */
export function initSentry() {
  if (isInitialized) {
    return;
  }
  isInitialized = true;

  const env = (typeof import.meta !== 'undefined' && import.meta?.env) || (typeof process !== 'undefined' && process?.env) || {};
  const dsn = env.VITE_SENTRY_DSN || '';
  const environment = env.MODE || (env.PROD ? 'production' : (env.NODE_ENV || 'development'));
  const release = env.VITE_APP_VERSION || 'caltrack-workforce@1.0.0';

  if (!dsn) {
    console.info('[Sentry] Telemetry initialized in inactive mode (VITE_SENTRY_DSN not configured).');
  }

  try {
    sentryClient.init({
      dsn: dsn || undefined,
      enabled: Boolean(dsn),
      environment,
      release,
      tracesSampleRate: env.PROD ? 0.1 : 1.0,
      initialScope: {
        tags: {
          application: 'workforce',
          environment,
        },
      },
      beforeSend: sanitizeSentryEvent,
      beforeBreadcrumb: sanitizeSentryBreadcrumb,
    });
  } catch (err) {
    // Sentry init failure must never block application bootstrap
    console.warn('[Sentry] Failed to initialize Sentry:', err);
  }
}

/**
 * Associates safe, non-sensitive user identity with error reports.
 */
export function setSentryUser(user) {
  try {
    if (user && (user.id || user.username)) {
      sentryClient.setUser({
        id: String(user.id || user.username),
        role: user.role || (user.isAdmin ? 'admin' : 'employee'),
        companyId: user.companyId || user.company || undefined,
      });
    } else {
      sentryClient.setUser(null);
    }
  } catch (_) {}
}

/**
 * Clears user identity from Sentry on logout.
 */
export function clearSentryUser() {
  try {
    sentryClient.setUser(null);
  } catch (_) {}
}

/**
 * Safely captures unexpected API errors (e.g. 5xx, repeated network drops)
 * while ignoring expected auth failures (401, 404, refresh transitions).
 */
export function captureUnexpectedApiError(error, context = {}) {
  try {
    const status = error.status || context.status;

    // Do NOT capture expected authentication flows or normal 404s
    if (status === 401 || status === 404 || status === 403) {
      return;
    }

    const cleanPath = sanitizeUrl(context.path || context.url || '');

    sentryClient.captureException(error, {
      tags: {
        error_type: 'api_error',
        status_code: String(status || '0'),
        api_method: context.method || 'GET',
      },
      extra: {
        path: cleanPath,
        errorCode: error.code || 'UNKNOWN',
      },
    });
  } catch (_) {}
}

/**
 * Adds an informational or diagnostic breadcrumb for non-error milestones.
 */
export function addSentryBreadcrumb(breadcrumb) {
  try {
    sentryClient.addBreadcrumb(breadcrumb);
  } catch (_) {}
}

/**
 * Safely captures an unexpected exception with custom tags and context.
 */
export function captureSentryException(error, context = {}) {
  try {
    sentryClient.captureException(error, context);
  } catch (_) {}
}

/**
 * React Error Boundary component with CalTrack fallback UI.
 */
export function SentryErrorBoundary({ children }) {
  return React.createElement(
    sentryClient.ErrorBoundary,
    {
      fallback: ({ resetError }) =>
        React.createElement(
          'div',
          { className: 'min-h-screen bg-slate-900 text-slate-100 flex items-center justify-center p-6' },
          React.createElement(
            'div',
            { className: 'max-w-md w-full bg-slate-800 rounded-2xl p-6 border border-slate-700 shadow-2xl text-center space-y-4' },
            React.createElement(
              'div',
              { className: 'w-12 h-12 rounded-full bg-rose-500/20 text-rose-400 mx-auto flex items-center justify-center' },
              React.createElement(
                'svg',
                { className: 'w-6 h-6', fill: 'none', viewBox: '0 0 24 24', stroke: 'currentColor' },
                React.createElement('path', {
                  strokeLinecap: 'round',
                  strokeLinejoin: 'round',
                  strokeWidth: 2,
                  d: 'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z'
                })
              )
            ),
            React.createElement('h2', { className: 'text-lg font-bold text-white' }, 'Application Notice'),
            React.createElement(
              'p',
              { className: 'text-xs text-slate-400' },
              'An unexpected interface error occurred. The incident has been recorded for diagnostics.'
            ),
            React.createElement(
              'div',
              { className: 'pt-2 flex justify-center gap-3' },
              React.createElement(
                'button',
                {
                  type: 'button',
                  onClick: () => {
                    resetError();
                    window.location.reload();
                  },
                  className: 'px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-semibold transition-colors cursor-pointer'
                },
                'Reload Application'
              )
            )
          )
        )
    },
    children
  );
}
