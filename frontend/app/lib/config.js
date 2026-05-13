export const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || '/api';
export const WS_URL = process.env.NEXT_PUBLIC_WS_URL || '';

function normalizeBase(base) {
  return base.endsWith('/') ? base.slice(0, -1) : base;
}

export function resolveApiBase() {
  const configured = normalizeBase(API_BASE);
  if (configured.startsWith('http://') || configured.startsWith('https://')) {
    return configured;
  }

  if (typeof window !== 'undefined') {
    return `${window.location.origin}${configured.startsWith('/') ? configured : `/${configured}`}`;
  }

  return configured;
}

export function resolveWebSocketUrl() {
  if (WS_URL) {
    return WS_URL;
  }

  if (typeof window !== 'undefined') {
    const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
    return `${scheme}://${window.location.host}/ws`;
  }

  return 'ws://localhost/ws';
}

export function apiUrl(path) {
  const normalizedBase = resolveApiBase();
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
}
