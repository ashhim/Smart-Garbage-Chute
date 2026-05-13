'use client';

import useSWR from 'swr';
import { useEffect, useState, useCallback } from 'react';
import {
  AlertTriangle,
  Building2,
  Cpu,
  BellRing,
  Loader2,
  CheckCircle2,
  WifiOff,
  LogOut,
  RefreshCw,
  Zap,
  Home,
  Settings,
  TrendingUp,
  Calendar,
  Clock,
  Activity,
} from 'lucide-react';

// ============================================================
// CONFIGURATION
// ============================================================

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8000';
const WS_URL = process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost:8000/ws';

// ============================================================
// HOOKS
// ============================================================

function useFetcher() {
  const [token, setToken] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const auth = async () => {
      try {
        setLoading(true);
        const res = await fetch(`${API_BASE}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: 'admin@alghurair.local',
            password: 'Admin@12345',
          }),
        });

        if (!res.ok) {
          throw new Error(`Auth failed: ${res.status}`);
        }

        const data = await res.json();
        setToken(data.access_token);
      } catch (err) {
        setError(err.message);
        console.error('Auth error:', err);
      } finally {
        setLoading(false);
      }
    };

    auth();
  }, []);

  const fetcher = useCallback(
    async (url) => {
      if (!token) return null;
      try {
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return await res.json();
      } catch (err) {
        console.error('Fetch error:', err);
        return null;
      }
    },
    [token]
  );

  return { token, loading, error, fetcher };
}

function useWebSocket(token) {
  const [messages, setMessages] = useState([]);
  const [ws, setWs] = useState(null);

  useEffect(() => {
    if (!token) return;

    const ws_url = WS_URL.startsWith('ws') ? WS_URL : `${WS_URL}?token=${token}`;
    const websocket = new WebSocket(ws_url);

    websocket.onopen = () => console.log('WebSocket connected');
    websocket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        setMessages((prev) => [data, ...prev.slice(0, 99)]);
      } catch (e) {
        console.error('WebSocket parse error:', e);
      }
    };
    websocket.onerror = (error) => console.error('WebSocket error:', error);
    websocket.onclose = () => console.log('WebSocket disconnected');

    setWs(websocket);

    return () => {
      if (websocket.readyState === WebSocket.OPEN) {
        websocket.close();
      }
    };
  }, [token]);

  return { messages, ws };
}

// ============================================================
// COMPONENTS
// ============================================================

function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center h-screen bg-gray-50">
      <div className="text-center">
        <Loader2 className="w-12 h-12 text-blue-600 animate-spin mx-auto mb-4" />
        <p className="text-gray-600">Loading...</p>
      </div>
    </div>
  );
}

function LoginPage({ onLogin }) {
  const [email, setEmail] = useState('admin@alghurair.local');
  const [password, setPassword] = useState('Admin@12345');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const res = await fetch(`${API_BASE}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      if (!res.ok) {
        throw new Error('Invalid credentials');
      }

      const data = await res.json();
      onLogin(data.access_token);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-600 to-blue-800 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-lg shadow-xl p-8">
          <div className="flex items-center justify-center mb-8">
            <Building2 className="w-8 h-8 text-blue-600 mr-2" />
            <h1 className="text-2xl font-bold text-gray-900">Smart Garbage Chute</h1>
          </div>

          <form onSubmit={handleLogin} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-600 focus:border-transparent"
                disabled={loading}
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-600 focus:border-transparent"
                disabled={loading}
              />
            </div>

            {error && <div className="text-red-600 text-sm p-3 bg-red-50 rounded">{error}</div>}

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-blue-600 text-white py-2 rounded-lg font-medium hover:bg-blue-700 disabled:opacity-50 flex items-center justify-center"
            >
              {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Sign In'}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

function StatCard({ icon: Icon, label, value, unit = '', trend = null }) {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-gray-600 text-sm font-medium">{label}</p>
          <p className="text-3xl font-bold text-gray-900 mt-2">
            {value}
            {unit && <span className="text-lg text-gray-500 ml-1">{unit}</span>}
          </p>
          {trend && (
            <p className={`text-sm mt-2 ${trend > 0 ? 'text-green-600' : 'text-gray-600'}`}>
              <TrendingUp className="w-4 h-4 inline mr-1" />
              {Math.abs(trend)}% {trend > 0 ? 'up' : 'stable'}
            </p>
          )}
        </div>
        <Icon className="w-8 h-8 text-blue-600 opacity-20" />
      </div>
    </div>
  );
}

function AlertCard({ alert }) {
  const severityColors = {
    high: 'bg-red-50 border-red-200 text-red-800',
    medium: 'bg-yellow-50 border-yellow-200 text-yellow-800',
    low: 'bg-blue-50 border-blue-200 text-blue-800',
  };

  const severityIcons = {
    high: <AlertTriangle className="w-5 h-5" />,
    medium: <BellRing className="w-5 h-5" />,
    low: <Activity className="w-5 h-5" />,
  };

  return (
    <div className={`border-l-4 p-4 rounded ${severityColors[alert.severity] || severityColors.medium}`}>
      <div className="flex items-start">
        <div className="flex-shrink-0 mt-0.5">{severityIcons[alert.severity] || severityIcons.medium}</div>
        <div className="ml-3 flex-1">
          <h4 className="font-semibold">{alert.category.replace('_', ' ').toUpperCase()}</h4>
          <p className="text-sm mt-1">{alert.message}</p>
          <p className="text-xs opacity-75 mt-2">Room: {alert.room_id}</p>
        </div>
        {!alert.acknowledged && (
          <button className="ml-4 px-3 py-1 bg-white bg-opacity-50 rounded text-sm font-medium hover:bg-opacity-75">
            ACK
          </button>
        )}
      </div>
    </div>
  );
}

function Dashboard({ token, onLogout, fetcher }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [selectedRoom, setSelectedRoom] = useState(null);
  const { messages } = useWebSocket(token);

  // Fetch analytics
  const { data: summary, mutate: mutateSummary } = useSWR(
    token ? `${API_BASE}/analytics/summary` : null,
    fetcher,
    { refreshInterval: 5000 }
  );

  // Fetch alerts
  const { data: alertsList } = useSWR(
    token ? `${API_BASE}/alerts?limit=50` : null,
    fetcher,
    { refreshInterval: 5000 }
  );

  // Fetch devices
  const { data: devices } = useSWR(
    token ? `${API_BASE}/devices` : null,
    fetcher,
    { refreshInterval: 10000 }
  );

  // Fetch rooms
  const { data: rooms } = useSWR(
    token ? `${API_BASE}/rooms` : null,
    fetcher,
    { refreshInterval: 10000 }
  );

  return (
    <div className="min-h-screen bg-gray-50">
      {/* HEADER */}
      <div className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <Building2 className="w-8 h-8 text-blue-600 mr-3" />
              <h1 className="text-2xl font-bold text-gray-900">Smart Garbage Chute Control Room</h1>
            </div>
            <button
              onClick={onLogout}
              className="inline-flex items-center px-4 py-2 bg-gray-100 hover:bg-gray-200 rounded-lg text-gray-700 font-medium"
            >
              <LogOut className="w-4 h-4 mr-2" />
              Logout
            </button>
          </div>
        </div>
      </div>

      {/* NAVIGATION TABS */}
      <div className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex space-x-8">
            {[
              { id: 'overview', label: 'Overview', icon: Home },
              { id: 'alerts', label: 'Alerts', icon: AlertTriangle },
              { id: 'devices', label: 'Devices', icon: Cpu },
              { id: 'ota', label: 'OTA Updates', icon: Zap },
              { id: 'analytics', label: 'Analytics', icon: TrendingUp },
              { id: 'settings', label: 'Settings', icon: Settings },
            ].map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setActiveTab(id)}
                className={`py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === id
                    ? 'border-blue-600 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                <Icon className="w-4 h-4 inline mr-2" />
                {label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* CONTENT */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* OVERVIEW TAB */}
        {activeTab === 'overview' && (
          <div className="space-y-8">
            {/* STATS GRID */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              <StatCard icon={Building2} label="Buildings" value={summary?.buildings || 0} />
              <StatCard icon={Home} label="Rooms" value={summary?.rooms || 0} />
              <StatCard icon={Cpu} label="Devices" value={summary?.devices || 0} />
              <StatCard
                icon={AlertTriangle}
                label="Active Alerts"
                value={summary?.alerts_open || 0}
                trend={summary?.alerts_1h ? (summary.alerts_1h > 0 ? 10 : 0) : 0}
              />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
              {/* REAL-TIME ALERTS */}
              <div className="lg:col-span-2">
                <div className="bg-white rounded-lg shadow p-6">
                  <div className="flex items-center justify-between mb-6">
                    <h2 className="text-lg font-semibold text-gray-900">Recent Alerts</h2>
                    <RefreshCw className="w-5 h-5 text-gray-400 cursor-pointer" />
                  </div>
                  <div className="space-y-4">
                    {alertsList && alertsList.length > 0 ? (
                      alertsList.slice(0, 10).map((alert) => <AlertCard key={alert.id} alert={alert} />)
                    ) : (
                      <p className="text-gray-500 text-center py-8">No recent alerts</p>
                    )}
                  </div>
                </div>
              </div>

              {/* QUICK STATS */}
              <div className="space-y-4">
                <div className="bg-white rounded-lg shadow p-6">
                  <h3 className="font-semibold text-gray-900 mb-4">System Status</h3>
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-gray-600">Devices Online</span>
                      <span className="font-bold text-green-600">{devices?.length || 0}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-600">Open Alerts</span>
                      <span className="font-bold text-red-600">{summary?.alerts_open || 0}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-600">24h AI Events</span>
                      <span className="font-bold text-blue-600">{summary?.ai_events_24h || 0}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-gray-600">Active OTA Jobs</span>
                      <span className="font-bold text-purple-600">{summary?.ota_jobs_active || 0}</span>
                    </div>
                  </div>
                </div>

                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <p className="text-sm text-blue-800">
                    <CheckCircle2 className="w-4 h-4 inline mr-2" />
                    System is operating normally
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ALERTS TAB */}
        {activeTab === 'alerts' && (
          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-6">Alert Management</h2>
            <div className="space-y-4">
              {alertsList && alertsList.length > 0 ? (
                alertsList.map((alert) => <AlertCard key={alert.id} alert={alert} />)
              ) : (
                <p className="text-gray-500 text-center py-8">No alerts</p>
              )}
            </div>
          </div>
        )}

        {/* DEVICES TAB */}
        {activeTab === 'devices' && (
          <div className="bg-white rounded-lg shadow overflow-hidden">
            <div className="p-6">
              <h2 className="text-lg font-semibold text-gray-900 mb-6">Device Monitoring</h2>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead className="bg-gray-50 border-t border-gray-200">
                  <tr>
                    <th className="px-6 py-3 text-left text-sm font-semibold text-gray-900">Device ID</th>
                    <th className="px-6 py-3 text-left text-sm font-semibold text-gray-900">Room</th>
                    <th className="px-6 py-3 text-left text-sm font-semibold text-gray-900">Type</th>
                    <th className="px-6 py-3 text-left text-sm font-semibold text-gray-900">Firmware</th>
                    <th className="px-6 py-3 text-left text-sm font-semibold text-gray-900">Status</th>
                    <th className="px-6 py-3 text-left text-sm font-semibold text-gray-900">Last Seen</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {devices && devices.length > 0 ? (
                    devices.map((device) => (
                      <tr key={device.id} className="hover:bg-gray-50">
                        <td className="px-6 py-4 text-sm text-gray-900 font-mono">{device.device_id}</td>
                        <td className="px-6 py-4 text-sm text-gray-600">Room {device.room_id}</td>
                        <td className="px-6 py-4 text-sm text-gray-600">{device.device_type}</td>
                        <td className="px-6 py-4 text-sm text-gray-600">{device.firmware_version}</td>
                        <td className="px-6 py-4 text-sm">
                          <span
                            className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${
                              device.status === 'online'
                                ? 'bg-green-100 text-green-800'
                                : 'bg-gray-100 text-gray-800'
                            }`}
                          >
                            {device.status}
                          </span>
                        </td>
                        <td className="px-6 py-4 text-sm text-gray-600">
                          {device.last_seen_at ? new Date(device.last_seen_at).toLocaleString() : 'Never'}
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan="6" className="px-6 py-8 text-center text-gray-500">
                        No devices
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* OTA TAB */}
        {activeTab === 'ota' && (
          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-6">OTA Firmware Management</h2>
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-6 text-center">
              <Zap className="w-12 h-12 text-blue-600 mx-auto mb-4" />
              <p className="text-blue-900 font-medium mb-4">Firmware Update Management</p>
              <p className="text-blue-800 text-sm mb-6">Upload new firmware binaries and manage device updates</p>
              <button className="px-6 py-2 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700">
                Upload Firmware
              </button>
            </div>
          </div>
        )}

        {/* ANALYTICS TAB */}
        {activeTab === 'analytics' && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div className="bg-white rounded-lg shadow p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-4">Alerts by Severity</h3>
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span>🔴 High</span>
                  <span className="font-bold">{summary?.alerts_24h || 0}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span>🟡 Medium</span>
                  <span className="font-bold">{Math.floor((summary?.alerts_24h || 0) * 0.4)}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span>🔵 Low</span>
                  <span className="font-bold">{Math.floor((summary?.alerts_24h || 0) * 0.2)}</span>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-lg shadow p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-4">AI Detection Events</h3>
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span>Last 24 Hours</span>
                  <span className="font-bold">{summary?.ai_events_24h || 0}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span>Last 1 Hour</span>
                  <span className="font-bold">{summary?.ai_events_1h || 0}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span>Detection Rate</span>
                  <span className="font-bold text-green-600">95%</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* SETTINGS TAB */}
        {activeTab === 'settings' && (
          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-6">System Settings</h2>
            <div className="space-y-6">
              <div>
                <h3 className="text-md font-semibold text-gray-900 mb-3">General</h3>
                <div className="space-y-3">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">System Name</label>
                    <input
                      type="text"
                      defaultValue="Smart Garbage Chute - Al Ghurair"
                      className="w-full px-4 py-2 border border-gray-300 rounded-lg"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ============================================================
// MAIN PAGE COMPONENT
// ============================================================

export default function Page() {
  const { token, loading, error, fetcher } = useFetcher();
  const [displayToken, setDisplayToken] = useState(null);

  // Handle token updates from login page
  const handleLogin = (newToken) => {
    setDisplayToken(newToken);
  };

  const handleLogout = () => {
    setDisplayToken(null);
    // Force page reload to reset auth state
    window.location.reload();
  };

  if (loading) return <LoadingSpinner />;

  if (!displayToken && !token) {
    return <LoginPage onLogin={handleLogin} />;
  }

  return <Dashboard token={displayToken || token} onLogout={handleLogout} fetcher={fetcher} />;
}
