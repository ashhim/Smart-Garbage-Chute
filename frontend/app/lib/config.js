export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost/api';
export const WS_URL = process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost/ws';

export function apiUrl(path) {
  const normalizedBase = API_BASE.endsWith('/')
    ? API_BASE.slice(0, -1)
    : API_BASE;
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
}
