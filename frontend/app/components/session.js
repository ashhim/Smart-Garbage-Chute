'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';

import { apiUrl } from '../lib/config';

async function parseResponse(response) {
  const payload = await response
    .json()
    .catch(() => (response.status === 204 ? null : {}));

  if (!response.ok) {
    throw new Error(payload?.detail || `Request failed: ${response.status}`);
  }

  return payload;
}

export function usePortalSession(requiredRoles = []) {
  const [token, setToken] = useState(null);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [authError, setAuthError] = useState('');

  const logout = useCallback(() => {
    sessionStorage.removeItem('sgc_token');
    setToken(null);
    setUser(null);
    setAuthError('');
  }, []);

  const fetchMe = useCallback(async (activeToken) => {
    const response = await fetch(apiUrl('/auth/me'), {
      headers: {
        Authorization: `Bearer ${activeToken}`,
      },
      cache: 'no-store',
    });
    return parseResponse(response);
  }, []);

  useEffect(() => {
    const cachedToken = sessionStorage.getItem('sgc_token');
    if (!cachedToken) {
      setLoading(false);
      return;
    }

    let cancelled = false;

    const restore = async () => {
      try {
        const currentUser = await fetchMe(cachedToken);
        if (cancelled) return;
        setToken(cachedToken);
        setUser(currentUser);
      } catch (error) {
        if (cancelled) return;
        console.error(error);
        logout();
        setAuthError('Stored session expired. Sign in again.');
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    };

    restore();

    return () => {
      cancelled = true;
    };
  }, [fetchMe, logout]);

  const login = useCallback(
    async ({ email, password }) => {
      setAuthError('');
      const response = await fetch(apiUrl('/auth/login'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      const payload = await parseResponse(response);
      if (!payload?.access_token) {
        throw new Error('Login response did not include an access token.');
      }

      const currentUser = await fetchMe(payload.access_token);
      sessionStorage.setItem('sgc_token', payload.access_token);
      setToken(payload.access_token);
      setUser(currentUser);
      return currentUser;
    },
    [fetchMe]
  );

  const request = useCallback(
    async (path, options = {}) => {
      if (!token) {
        throw new Error('Missing active session.');
      }

      const { method = 'GET', body, headers = {} } = options;
      const response = await fetch(apiUrl(path), {
        method,
        headers: {
          ...(body ? { 'Content-Type': 'application/json' } : {}),
          Authorization: `Bearer ${token}`,
          ...headers,
        },
        body: body ? JSON.stringify(body) : undefined,
      });

      return parseResponse(response);
    },
    [token]
  );

  const fetcher = useCallback(
    async (url) => {
      if (!token) return null;

      const response = await fetch(url, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
        cache: 'no-store',
      });

      return parseResponse(response);
    },
    [token]
  );

  const authorized = useMemo(() => {
    if (!user) return false;
    if (!requiredRoles.length) return true;
    return requiredRoles.includes(user.role);
  }, [requiredRoles, user]);

  return {
    token,
    user,
    loading,
    authError,
    authorized,
    login,
    logout,
    request,
    fetcher,
    setAuthError,
  };
}
