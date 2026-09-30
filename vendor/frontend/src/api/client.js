/**
 * workforce-app/frontend/src/api/client.js
 * Universal fetch client handling Bearer tokens, CSRF tokens, silent refresh deduplication, and JSON errors.
 */

import {
  getAccessToken,
  getRefreshToken,
  setAuthTokens,
  clearAuthTokens,
} from '../utils/authTokens.js';
import { classifyApiError } from '../utils/apiErrors.js';
import { captureUnexpectedApiError } from '../utils/sentry.js';

let inFlightRefreshPromise = null;
let lastRefreshFailure = null;

function getCookie(name) {
  if (typeof document === 'undefined' || !document.cookie) return null;
  const cookies = document.cookie.split(';');
  for (let i = 0; i < cookies.length; i++) {
    const cookie = cookies[i].trim();
    if (cookie.substring(0, name.length + 1) === name + '=') {
      return decodeURIComponent(cookie.substring(name.length + 1));
    }
  }
  return null;
}

/**
 * Performs a silent token refresh using the existing /api/auth/refresh/ endpoint.
 * Deduplicates multiple concurrent refresh requests.
 */
export async function apiRefreshToken() {
  if (inFlightRefreshPromise) {
    return inFlightRefreshPromise;
  }

  const refreshToken = getRefreshToken();
  if (!refreshToken) {
    lastRefreshFailure = {
      type: 'AUTH_INVALID',
      status: 401,
      message: 'No refresh token available.',
    };
    clearAuthTokens();
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('workforce:auth-unauthorized'));
    }
    return null;
  }

  inFlightRefreshPromise = (async () => {
    try {
      const res = await fetch('/api/auth/refresh/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });

      if (res.ok) {
        const data = await res.json();
        const newToken = data.access_token || data.token;
        const newRefreshToken = data.refresh_token || data.refresh || refreshToken;
        if (newToken) {
          setAuthTokens(newToken, newRefreshToken);
          lastRefreshFailure = null;
          return newToken;
        }
      }

      if (res.status === 401 || res.status === 400) {
        // Refresh rejected by server (invalid/expired refresh token)
        lastRefreshFailure = {
          type: 'AUTH_INVALID',
          status: res.status,
          message: 'Session expired. Please log in again.',
        };
        clearAuthTokens();
        if (typeof window !== 'undefined') {
          window.dispatchEvent(new CustomEvent('workforce:auth-unauthorized'));
        }
      } else {
        // For 503 (DB connection pool exhaustion) or 5xx, do NOT clear tokens
        lastRefreshFailure = {
          type: 'SERVER_ERROR',
          status: res.status,
          message: `Authentication service temporarily unavailable (${res.status}).`,
        };
      }
      return null;
    } catch (err) {
      lastRefreshFailure = {
        type: 'NETWORK_ERROR',
        status: 0,
        message: 'Network error during token refresh.',
      };
      return null;
    } finally {
      inFlightRefreshPromise = null;
    }
  })();

  return inFlightRefreshPromise;
}

export async function apiRequest(path, options = {}) {
  const headers = new Headers(options.headers || {});

  if (!options.isFormData && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  const csrfToken = getCookie('csrftoken');
  if (csrfToken && !headers.has('X-CSRFToken')) {
    headers.set('X-CSRFToken', csrfToken);
  }

  // Attach tab-scoped or stored Bearer token (never attach to unauthenticated login/signup endpoints)
  const isAuthEndpoint = path.includes('/auth/login') || path.includes('/auth/signup');
  const token = getAccessToken();
  if (token && !headers.has('Authorization') && !isAuthEndpoint) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const config = {
    method: options.method || 'GET',
    headers,
    credentials: 'include',
    ...options,
  };

  if (options.json) {
    config.body = JSON.stringify(options.json);
  }

  const url = path.startsWith('http') ? path : `/api${path.startsWith('/') ? path : '/' + path}`;

  let response;
  try {
    response = await fetch(url, config);
  } catch (netErr) {
    const error = new Error('Network error. Please check your connection.');
    error.status = 0;
    error.code = 'NETWORK_ERROR';
    error.originalError = netErr;
    captureUnexpectedApiError(error, { path, method: config.method, status: 0 });
    throw error;
  }

  // Auto-refresh token on 401 for authenticated endpoints (excluding login/refresh)
  if (response.status === 401 && !path.includes('/auth/login') && !path.includes('/auth/refresh')) {
    if (!options._isRetry) {
      const newToken = await apiRefreshToken();
      if (newToken) {
        headers.set('Authorization', `Bearer ${newToken}`);
        const retryConfig = { ...config, headers, _isRetry: true };
        try {
          response = await fetch(url, retryConfig);
        } catch (retryNetErr) {
          const error = new Error('Network error during retry.');
          error.status = 0;
          error.code = 'NETWORK_ERROR';
          error.originalError = retryNetErr;
          throw error;
        }

        // If the retried request STILL returns 401, the fresh token was rejected.
        // Clear authentication and dispatch unauthorized event once.
        if (response.status === 401) {
          clearAuthTokens();
          if (typeof window !== 'undefined') {
            window.dispatchEvent(new CustomEvent('workforce:auth-unauthorized'));
          }
        }
      } else {
        // Refresh did not yield a new token.
        // If refresh failed temporarily (5xx or network error):
        if (lastRefreshFailure && lastRefreshFailure.type !== 'AUTH_INVALID') {
          // DO NOT clear tokens. DO NOT dispatch auth-unauthorized.
          const error = new Error(lastRefreshFailure.message || 'Authentication service temporarily unavailable.');
          error.status = lastRefreshFailure.status || 503;
          error.code = lastRefreshFailure.type === 'NETWORK_ERROR' ? 'NETWORK_ERROR' : 'AUTH_SERVICE_UNAVAILABLE';
          throw error;
        }
        // If AUTH_INVALID, apiRefreshToken() has already called clearAuthTokens()
        // and dispatched workforce:auth-unauthorized once. We do not repeat it here.
      }
    } else {
      // The request was already a retry (_isRetry: true) and returned 401.
      clearAuthTokens();
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new CustomEvent('workforce:auth-unauthorized'));
      }
    }
  }

  if (response.status === 204) {
    return null;
  }

  const contentType = response.headers.get('content-type');
  const isJson = contentType && contentType.includes('application/json');
  const data = isJson ? await response.json() : await response.text();

  if (!response.ok) {
    let rawError =
      (data && data.message && (data.error === 'ONBOARDING_VALIDATION_FAILED' || data.error === 'ONBOARDING_STEP_SKIPPED') ? data.message : null) ||
      (data && data.error) ||
      (data && data.message) ||
      (data && data.detail) ||
      (data && typeof data === 'object' ? JSON.stringify(data) : 'Request failed');

    if (Array.isArray(rawError)) {
      rawError = rawError[0] || 'Request failed';
    }
    if (typeof rawError === 'object' && rawError !== null) {
      try {
        rawError = rawError.detail || rawError.message || rawError.string || JSON.stringify(rawError);
      } catch (_) {
        rawError = 'Request failed';
      }
    }
    let errorMsg = String(rawError || 'Request failed');
    if (errorMsg.includes('ErrorDetail')) {
      const match = errorMsg.match(/string=['"]([^'"]+)['"]/);
      if (match && match[1]) {
        errorMsg = match[1];
      }
    }
    errorMsg = errorMsg.replace(/^\[['"]?|['"]?\]$/g, '').trim();

    const error = new Error(errorMsg);
    error.status = response.status;
    error.code = (data && data.code) || classifyApiError(response.status, data);
    error.data = data;
    if (data && data.fields) {
      error.fields = data.fields;
    }
    if (response.status >= 500) {
      captureUnexpectedApiError(error, { path, method: config.method, status: response.status });
    }
    throw error;
  }

  return data;
}
