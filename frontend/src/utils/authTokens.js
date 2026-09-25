/**
 * authTokens.js
 * Single authoritative source of truth for Workforce JWT access and refresh tokens.
 * Storage strategy: sessionStorage (primary tab-scoped isolation) with localStorage fallback.
 */

const ACCESS_TOKEN_KEY = 'wf_token';
const REFRESH_TOKEN_KEY = 'wf_refresh_token';
const TAB_ID_KEY = 'wf_tab_id';

/**
 * Cross-tab storage event listener ensuring sessionStorage mirrors localStorage updates.
 */
if (typeof window !== 'undefined') {
  window.addEventListener('storage', (event) => {
    if (event.key === ACCESS_TOKEN_KEY) {
      if (event.newValue) {
        sessionStorage.setItem(ACCESS_TOKEN_KEY, event.newValue);
      } else {
        sessionStorage.removeItem(ACCESS_TOKEN_KEY);
      }
    } else if (event.key === REFRESH_TOKEN_KEY) {
      if (event.newValue) {
        sessionStorage.setItem(REFRESH_TOKEN_KEY, event.newValue);
      } else {
        sessionStorage.removeItem(REFRESH_TOKEN_KEY);
      }
    }
  });
}

/**
 * Retrieves the active access token.
 * Returns null if unauthenticated or not running in a browser environment.
 * Reconciles sessionStorage and localStorage to guarantee the freshest valid token is used.
 */
export function getAccessToken() {
  if (typeof window === 'undefined') return null;
  const sessionToken = sessionStorage.getItem(ACCESS_TOKEN_KEY);
  const localToken = localStorage.getItem(ACCESS_TOKEN_KEY);

  // If localStorage was cleared (e.g. logout in another tab), treat session as unauthenticated
  if (!localToken && sessionToken) {
    sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    return null;
  }

  // If newly opened tab or session empty, populate from localStorage
  if (!sessionToken && localToken) {
    sessionStorage.setItem(ACCESS_TOKEN_KEY, localToken);
    return localToken;
  }

  // If both exist but differ, verify expiration and select the valid/fresher token
  if (sessionToken && localToken && sessionToken !== localToken) {
    const sessionExpired = isTokenExpired(sessionToken, 0);
    const localExpired = isTokenExpired(localToken, 0);

    if (sessionExpired && !localExpired) {
      sessionStorage.setItem(ACCESS_TOKEN_KEY, localToken);
      return localToken;
    }

    const sessionDecoded = parseJwt(sessionToken);
    const localDecoded = parseJwt(localToken);
    const sessionExp = sessionDecoded?.exp || 0;
    const localExp = localDecoded?.exp || 0;

    if (localExp >= sessionExp) {
      sessionStorage.setItem(ACCESS_TOKEN_KEY, localToken);
      return localToken;
    }

    return sessionToken;
  }

  return sessionToken || localToken || null;
}

/**
 * Retrieves the active refresh token.
 * Reconciles sessionStorage and localStorage to maintain one coherent authentication state.
 */
export function getRefreshToken() {
  if (typeof window === 'undefined') return null;
  const sessionRefresh = sessionStorage.getItem(REFRESH_TOKEN_KEY);
  const localRefresh = localStorage.getItem(REFRESH_TOKEN_KEY);

  if (!localRefresh && sessionRefresh) {
    sessionStorage.removeItem(REFRESH_TOKEN_KEY);
    return null;
  }

  if (!sessionRefresh && localRefresh) {
    sessionStorage.setItem(REFRESH_TOKEN_KEY, localRefresh);
    return localRefresh;
  }

  if (sessionRefresh && localRefresh && sessionRefresh !== localRefresh) {
    sessionStorage.setItem(REFRESH_TOKEN_KEY, localRefresh);
    return localRefresh;
  }

  return sessionRefresh || localRefresh || null;
}

/**
 * Atomically stores both access and refresh tokens across session and local stores.
 */
export function setAuthTokens(accessToken, refreshToken) {
  if (typeof window === 'undefined') return;
  if (accessToken) {
    sessionStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
    localStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
  }
  if (refreshToken) {
    sessionStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
    localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
  }
  if (!sessionStorage.getItem(TAB_ID_KEY)) {
    const tabId = 'tab_' + Math.random().toString(36).substring(2, 9) + '_' + Date.now();
    sessionStorage.setItem(TAB_ID_KEY, tabId);
  }
}

/**
 * Clears all stored auth credentials and tab identifiers across both stores.
 */
export function clearAuthTokens() {
  if (typeof window === 'undefined') return;
  sessionStorage.removeItem(ACCESS_TOKEN_KEY);
  sessionStorage.removeItem(REFRESH_TOKEN_KEY);
  sessionStorage.removeItem(TAB_ID_KEY);
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

/**
 * Checks if a non-empty access token is currently present.
 */
export function hasAuthToken() {
  return Boolean(getAccessToken());
}

/**
 * Safely decodes a JWT payload without external libraries.
 */
export function parseJwt(token) {
  if (!token || typeof token !== 'string') return null;
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const base64Url = parts[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
      atob(base64)
        .split('')
        .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join('')
    );
    return JSON.parse(jsonPayload);
  } catch (_) {
    return null;
  }
}

/**
 * Checks if a JWT is expired or will expire within `bufferSeconds` (default 15s).
 */
export function isTokenExpired(token, bufferSeconds = 15) {
  if (!token) return true;
  const decoded = parseJwt(token);
  if (!decoded || !decoded.exp) return false;
  const nowInSeconds = Math.floor(Date.now() / 1000);
  return decoded.exp <= nowInSeconds + bufferSeconds;
}
