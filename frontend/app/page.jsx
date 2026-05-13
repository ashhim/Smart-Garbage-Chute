'use client';

import useSWR from 'swr';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  Building2,
  Cpu,
  BellRing,
  Loader2,
  LogOut,
  Activity,
  ShieldCheck,
  Server,
  Wifi,
  Radio,
  Camera,
  Trash2,
  Clock3,
  MapPinned,
  RefreshCw,
  TriangleAlert,
  BadgeAlert,
  Waves,
  DoorClosed,
  DoorOpen,
  Flame,
  CircleAlert,
  Zap,
  Send,
  PlayCircle,
  Square,
  CheckCircle2,
} from 'lucide-react';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost/api';
const WS_URL = process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost/ws';

function cn(...classes) {
  return classes.filter(Boolean).join(' ');
}

function formatTime(value) {
  if (!value) return '—';
  try {
    const d = new Date(value);
    return d.toLocaleString();
  } catch {
    return String(value);
  }
}

function useFetcher() {
  const [token, setToken] = useState(null);
  const [loading, setLoading] = useState(true);
  const [authError, setAuthError] = useState('');

  useEffect(() => {
    const cached = sessionStorage.getItem('sgc_token');
    if (cached) {
      setToken(cached);
      setLoading(false);
      return;
    }

    const login = async () => {
      try {
        const res = await fetch(`${API_BASE}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: 'admin@alghurair.local',
            password: 'Admin@12345',
          }),
        });

        const data = await res.json();

        if (data?.access_token) {
          sessionStorage.setItem('sgc_token', data.access_token);
          setToken(data.access_token);
        } else {
          setAuthError(data?.detail || 'Authentication failed');
        }
      } catch (err) {
        setAuthError('Backend unavailable');
        console.error(err);
      } finally {
        setLoading(false);
      }
    };

    login();
  }, []);

  const logout = useCallback(() => {
    sessionStorage.removeItem('sgc_token');
    setToken(null);
    window.location.reload();
  }, []);

  const fetcher = useCallback(
    async (url) => {
      if (!token) return null;

      const res = await fetch(url, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body?.detail || `Request failed: ${res.status}`);
      }

      return res.json();
    },
    [token]
  );

  return { token, loading, authError, logout, fetcher };
}

function useSocket(enabled) {
  const [events, setEvents] = useState([]);

  useEffect(() => {
    if (!enabled) return;

    let ws;

    try {
      ws = new WebSocket(WS_URL);
    } catch {
      return;
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        setEvents((prev) => [data, ...prev].slice(0, 20));
      } catch (e) {
        console.error(e);
      }
    };

    return () => {
      if (ws && ws.readyState === WebSocket.OPEN) ws.close();
    };
  }, [enabled]);

  return events;
}

function LoadingScreen() {
  return (
    <div className="min-h-screen bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-slate-900 via-slate-950 to-black flex items-center justify-center text-white">
      <div className="text-center max-w-md px-6">
        <div className="mx-auto mb-5 h-16 w-16 rounded-2xl border border-cyan-400/30 bg-cyan-400/10 flex items-center justify-center shadow-[0_0_60px_rgba(34,211,238,0.25)]">
          <Loader2 className="w-8 h-8 animate-spin text-cyan-300" />
        </div>
        <h1 className="text-2xl font-semibold tracking-tight">Smart Garbage Chute</h1>
        <p className="text-slate-400 mt-2">
          Initializing industrial monitoring console...
        </p>
      </div>
    </div>
  );
}

function SectionHeader({ icon: Icon, title, subtitle, action }) {
  return (
    <div className="flex items-start justify-between gap-4 mb-4">
      <div>
        <div className="flex items-center gap-2">
          <Icon className="w-5 h-5 text-cyan-300" />
          <h2 className="text-lg sm:text-xl font-semibold text-white">{title}</h2>
        </div>
        {subtitle ? <p className="text-sm text-slate-400 mt-1">{subtitle}</p> : null}
      </div>
      {action}
    </div>
  );
}

function MetricCard({ icon: Icon, label, value, helper, tone = 'cyan' }) {
  const tones = {
    cyan: 'from-cyan-500/20 to-cyan-500/5 border-cyan-400/20',
    violet: 'from-violet-500/20 to-violet-500/5 border-violet-400/20',
    amber: 'from-amber-500/20 to-amber-500/5 border-amber-400/20',
    rose: 'from-rose-500/20 to-rose-500/5 border-rose-400/20',
    emerald: 'from-emerald-500/20 to-emerald-500/5 border-emerald-400/20',
    slate: 'from-slate-500/20 to-slate-500/5 border-slate-400/20',
  };

  return (
    <div className={cn(
      'rounded-2xl border bg-gradient-to-br p-5 shadow-[0_10px_40px_rgba(0,0,0,0.25)] backdrop-blur',
      tones[tone] || tones.cyan
    )}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm text-slate-400">{label}</p>
          <div className="mt-2 text-3xl font-semibold tracking-tight text-white">
            {value}
          </div>
          {helper ? <p className="mt-2 text-xs text-slate-500">{helper}</p> : null}
        </div>
        <div className="h-12 w-12 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center">
          <Icon className="w-6 h-6 text-white" />
        </div>
      </div>
    </div>
  );
}

function Badge({ children, className }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border px-2.5 py-1 text-[11px] font-medium uppercase tracking-[0.14em]',
        className
      )}
    >
      {children}
    </span>
  );
}

function AlertItem({ alert, onAck }) {
  const severityStyles = {
    critical: 'border-rose-500/40 bg-rose-500/10 text-rose-200',
    high: 'border-orange-500/40 bg-orange-500/10 text-orange-200',
    medium: 'border-amber-500/40 bg-amber-500/10 text-amber-100',
    low: 'border-sky-500/40 bg-sky-500/10 text-sky-100',
    info: 'border-slate-500/40 bg-slate-500/10 text-slate-100',
  };

  return (
    <div className={cn('rounded-2xl border p-4', severityStyles[alert.severity] || severityStyles.medium)}>
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-4 h-4" />
            <div className="font-semibold uppercase tracking-wide">
              {String(alert.category || 'alert').replaceAll('_', ' ')}
            </div>
            <Badge className="border-white/15 text-white/80">
              {alert.severity || 'medium'}
            </Badge>
          </div>

          <p className="text-sm text-white/85">{alert.message || 'No message provided'}</p>

          <div className="flex flex-wrap items-center gap-3 text-xs text-white/60">
            <span>Room: {alert.room_id ?? '—'}</span>
            <span>Source: {alert.source ?? 'system'}</span>
            <span>Time: {formatTime(alert.created_at || alert.timestamp)}</span>
          </div>
        </div>

        <div className="flex flex-col items-end gap-2">
          {alert.acknowledged ? (
            <Badge className="border-emerald-400/30 bg-emerald-500/10 text-emerald-200">
              ACKED
            </Badge>
          ) : (
            <button
              onClick={() => onAck?.(alert)}
              className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-white hover:bg-white/10"
            >
              <CheckCircle2 className="w-4 h-4" />
              Acknowledge
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function DeviceCard({ device }) {
  const online = String(device.status || '').toLowerCase() === 'online';

  return (
    <div className="rounded-2xl border border-white/10 bg-slate-900/70 p-5 shadow-[0_10px_30px_rgba(0,0,0,0.2)]">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h3 className="text-white font-semibold tracking-tight">
            {device.device_id || 'Unknown Device'}
          </h3>
          <p className="text-slate-400 text-sm mt-1">
            {device.device_type || 'ESP32 PoE Node'}
          </p>
        </div>

        <div
          className={cn(
            'h-3 w-3 rounded-full shadow-[0_0_20px_rgba(34,197,94,0.35)]',
            online ? 'bg-emerald-400' : 'bg-rose-400 shadow-[0_0_20px_rgba(251,113,133,0.35)]'
          )}
        />
      </div>

      <div className="mt-5 space-y-3 text-sm">
        <Row label="Room" value={device.room_id ?? '—'} />
        <Row label="Firmware" value={device.firmware_version ?? '—'} />
        <Row label="Last Seen" value={formatTime(device.last_seen_at)} />
        <Row
          label="State"
          value={
            <span className={online ? 'text-emerald-300' : 'text-rose-300'}>
              {device.status || 'unknown'}
            </span>
          }
        />
      </div>
    </div>
  );
}

function Row({ label, value }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <span className="text-slate-500">{label}</span>
      <span className="text-white text-right">{value}</span>
    </div>
  );
}

function TimelineEvent({ item }) {
  const label =
    item?.type ||
    item?.event_type ||
    item?.category ||
    'event';

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-cyan-300" />
          <span className="text-sm font-medium text-white">
            {String(label).replaceAll('_', ' ')}
          </span>
        </div>
        <span className="text-xs text-slate-500">
          {formatTime(item?.timestamp || item?.created_at || item?.time)}
        </span>
      </div>
      <pre className="mt-2 overflow-auto rounded-lg bg-black/20 p-3 text-[11px] leading-5 text-cyan-200">
        {JSON.stringify(item, null, 2)}
      </pre>
    </div>
  );
}

export default function Page() {
  const { token, loading, authError, logout, fetcher } = useFetcher();
  const socketEvents = useSocket(Boolean(token));

  const [simulationRunning, setSimulationRunning] = useState(false);
  const [simulationRoom, setSimulationRoom] = useState('CHR_01');
  const [simulationEvent, setSimulationEvent] = useState('blockage');
  const [simMessage, setSimMessage] = useState('');

  const { data: summary } = useSWR(
    token ? `${API_BASE}/analytics/summary` : null,
    fetcher,
    { refreshInterval: 5000 }
  );

  const { data: alerts } = useSWR(
    token ? `${API_BASE}/alerts` : null,
    fetcher,
    { refreshInterval: 5000 }
  );

  const { data: devices } = useSWR(
    token ? `${API_BASE}/devices` : null,
    fetcher,
    { refreshInterval: 5000 }
  );

  const deviceList = useMemo(() => Array.isArray(devices) ? devices : [], [devices]);
  const alertList = useMemo(() => Array.isArray(alerts) ? alerts : [], [alerts]);
  const liveRooms = useMemo(() => {
    const map = new Map();

    for (const d of deviceList) {
      if (d?.room_id) map.set(String(d.room_id), d);
    }

    for (const a of alertList) {
      if (a?.room_id && !map.has(String(a.room_id))) {
        map.set(String(a.room_id), { room_id: a.room_id });
      }
    }

    return [...map.values()];
  }, [deviceList, alertList]);

  useEffect(() => {
    if (deviceList.length > 0) {
      setSimulationRoom(String(deviceList[0]?.room_id || 'CHR_01'));
    }
  }, [deviceList.length]);

  const onAck = useCallback(async (alert) => {
    try {
      const res = await fetch(`${API_BASE}/alerts/${alert.id}/acknowledge`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!res.ok) throw new Error('Failed to acknowledge alert');
    } catch (error) {
      console.error(error);
      setSimMessage('Acknowledge action failed.');
    }
  }, [token]);

  const callSimulation = useCallback(async (path, body) => {
    setSimMessage('');
    try {
      const res = await fetch(`${API_BASE}/simulation${path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: body ? JSON.stringify(body) : undefined,
      });

      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        throw new Error(data?.detail || 'Simulation request failed');
      }

      setSimMessage(data?.ok ? 'Simulation updated successfully.' : 'Simulation action sent.');
      return data;
    } catch (error) {
      console.error(error);
      setSimMessage(error.message || 'Simulation request failed.');
      return null;
    }
  }, [token]);

  if (loading) return <LoadingScreen />;

  if (!token) {
    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center p-6">
        <div className="max-w-lg w-full rounded-3xl border border-white/10 bg-slate-950/80 p-8">
          <div className="flex items-center gap-3">
            <div className="h-12 w-12 rounded-2xl bg-cyan-500/10 border border-cyan-400/20 flex items-center justify-center">
              <Wifi className="w-6 h-6 text-cyan-300" />
            </div>
            <div>
              <h1 className="text-2xl font-semibold">Smart Garbage Chute</h1>
              <p className="text-slate-400 text-sm">Industrial Monitoring Dashboard</p>
            </div>
          </div>

          <div className="mt-6 rounded-2xl border border-amber-400/20 bg-amber-500/10 p-4 text-amber-100 text-sm">
            {authError || 'Login unavailable. Check backend and seeded user credentials.'}
          </div>
        </div>
      </div>
    );
  }

  const onlineDevices = deviceList.filter((d) => String(d?.status || '').toLowerCase() === 'online').length;

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(15,23,42,0.7),_rgba(2,6,23,1)_45%)] text-white">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-slate-950/80 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-5 py-4">
          <div className="flex items-center gap-4">
            <div className="h-12 w-12 rounded-2xl border border-cyan-400/20 bg-cyan-400/10 flex items-center justify-center shadow-[0_0_50px_rgba(34,211,238,0.18)]">
              <Building2 className="w-6 h-6 text-cyan-300" />
            </div>
            <div>
              <h1 className="text-xl sm:text-2xl font-semibold tracking-tight">
                Smart Garbage Chute Control Room
              </h1>
              <div className="flex flex-wrap items-center gap-2 mt-1 text-sm text-slate-400">
                <span>Al Ghurair</span>
                <span className="text-slate-600">•</span>
                <span>Realtime Monitoring</span>
                <span className="text-slate-600">•</span>
                <span>Simulation Enabled</span>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <Badge className="border-emerald-400/20 bg-emerald-500/10 text-emerald-200">
              <Wifi className="mr-1 h-3.5 w-3.5" />
              Online
            </Badge>
            <button
              onClick={logout}
              className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-4 py-2 text-sm text-white hover:bg-white/10"
            >
              <LogOut className="w-4 h-4" />
              Logout
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-5 py-6 sm:py-8">
        <div className="mb-6 grid gap-4 lg:grid-cols-[1.3fr_0.7fr]">
          <div className="rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl shadow-black/20">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div className="max-w-2xl">
                <div className="flex items-center gap-2 text-cyan-300">
                  <ShieldCheck className="h-5 w-5" />
                  <span className="text-xs font-semibold uppercase tracking-[0.24em]">
                    Industrial IoT / AI Control Surface
                  </span>
                </div>
                <h2 className="mt-3 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
                  Multi-building chute monitoring with sensor telemetry, AI alerts, and OTA control.
                </h2>
                <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-400">
                  Central command view for chute-room nodes, RTSP camera analytics, alerts, maintenance, and simulation.
                </p>
              </div>

              <div className="grid gap-3 sm:grid-cols-2">
                <div className="rounded-2xl border border-white/10 bg-slate-950/60 px-4 py-3">
                  <div className="text-xs uppercase tracking-[0.2em] text-slate-500">Live Rooms</div>
                  <div className="mt-1 text-2xl font-semibold">{liveRooms.length}</div>
                </div>
                <div className="rounded-2xl border border-white/10 bg-slate-950/60 px-4 py-3">
                  <div className="text-xs uppercase tracking-[0.2em] text-slate-500">Online Devices</div>
                  <div className="mt-1 text-2xl font-semibold">{onlineDevices}</div>
                </div>
              </div>
            </div>

            <div className="mt-6 flex flex-wrap items-center gap-3">
              <Badge className="border-cyan-400/20 bg-cyan-500/10 text-cyan-200">
                MQTT
              </Badge>
              <Badge className="border-violet-400/20 bg-violet-500/10 text-violet-200">
                WebSocket
              </Badge>
              <Badge className="border-amber-400/20 bg-amber-500/10 text-amber-200">
                AI CCTV
              </Badge>
              <Badge className="border-emerald-400/20 bg-emerald-500/10 text-emerald-200">
                Simulation
              </Badge>
            </div>
          </div>

          <div className="rounded-3xl border border-white/10 bg-slate-950/75 p-6">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xs uppercase tracking-[0.22em] text-slate-500">System Health</div>
                <div className="mt-1 text-lg font-semibold text-white">Operational Snapshot</div>
              </div>
              <div className="rounded-xl border border-white/10 bg-white/5 p-2">
                <RefreshCw className="h-4 w-4 text-cyan-300" />
              </div>
            </div>

            <div className="mt-5 space-y-3">
              <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                <span className="flex items-center gap-2 text-slate-300">
                  <Camera className="h-4 w-4 text-cyan-300" />
                  AI Events (24h)
                </span>
                <span className="font-semibold">{summary?.ai_events_24h || 0}</span>
              </div>

              <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                <span className="flex items-center gap-2 text-slate-300">
                  <Radio className="h-4 w-4 text-violet-300" />
                  OTA Jobs Active
                </span>
                <span className="font-semibold">{summary?.ota_jobs_active || 0}</span>
              </div>

              <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                <span className="flex items-center gap-2 text-slate-300">
                  <AlertTriangle className="h-4 w-4 text-rose-300" />
                  Open Alerts
                </span>
                <span className="font-semibold">{summary?.alerts_open || 0}</span>
              </div>
            </div>

            {simMessage ? (
              <div className="mt-4 rounded-2xl border border-cyan-400/20 bg-cyan-500/10 px-4 py-3 text-sm text-cyan-100">
                {simMessage}
              </div>
            ) : null}
          </div>
        </div>

        <div className="grid gap-6 xl:grid-cols-12">
          <div className="space-y-6 xl:col-span-8">
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <MetricCard
                icon={Building2}
                label="Buildings"
                value={summary?.buildings ?? 0}
                helper="Connected buildings in the system"
                tone="cyan"
              />
              <MetricCard
                icon={Trash2}
                label="Rooms"
                value={summary?.rooms ?? 0}
                helper="Chute rooms under monitoring"
                tone="violet"
              />
              <MetricCard
                icon={Cpu}
                label="Devices"
                value={summary?.devices ?? 0}
                helper="ESP32 PoE controller nodes"
                tone="amber"
              />
              <MetricCard
                icon={AlertTriangle}
                label="Open Alerts"
                value={summary?.alerts_open ?? 0}
                helper="Pending operations queue"
                tone="rose"
              />
            </div>

            <div className="rounded-3xl border border-white/10 bg-slate-950/75 p-5">
              <SectionHeader
                icon={BellRing}
                title="Recent Alerts"
                subtitle="Live operational events requiring attention."
              />

              <div className="space-y-4">
                {alertList.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-8 text-center text-slate-400">
                    No active alerts. The chute network is stable.
                  </div>
                ) : (
                  alertList.slice(0, 8).map((alert) => (
                    <AlertItem key={alert.id} alert={alert} onAck={onAck} />
                  ))
                )}
              </div>
            </div>

            <div className="rounded-3xl border border-white/10 bg-slate-950/75 p-5">
              <SectionHeader
                icon={Server}
                title="Device Monitoring"
                subtitle="Independent PoE nodes by room with live status and firmware visibility."
              />

              <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
                {deviceList.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-8 text-center text-slate-400 md:col-span-2 2xl:col-span-3">
                    No devices discovered yet.
                  </div>
                ) : (
                  deviceList.map((device) => (
                    <DeviceCard key={device.id || device.device_id} device={device} />
                  ))
                )}
              </div>
            </div>
          </div>

          <div className="space-y-6 xl:col-span-4">
            <div className="rounded-3xl border border-white/10 bg-slate-950/75 p-5">
              <SectionHeader
                icon={Activity}
                title="Live WebSocket Feed"
                subtitle="Realtime telemetry, AI events, and alert updates."
              />

              <div className="max-h-[420px] space-y-3 overflow-auto pr-1">
                {socketEvents.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-6 text-sm text-slate-400">
                    Waiting for realtime events...
                  </div>
                ) : (
                  socketEvents.map((item, index) => (
                    <TimelineEvent key={index} item={item} />
                  ))
                )}
              </div>
            </div>

            <div className="rounded-3xl border border-white/10 bg-slate-950/75 p-5">
              <SectionHeader
                icon={TriangleAlert}
                title="Demo / Simulation Controls"
                subtitle="Use this panel when hardware is unavailable."
              />

              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <button
                    onClick={() => callSimulation('/start')}
                    className="inline-flex items-center justify-center gap-2 rounded-2xl border border-emerald-400/20 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-100 hover:bg-emerald-500/15"
                  >
                    <PlayCircle className="h-4 w-4" />
                    Start
                  </button>
                  <button
                    onClick={() => callSimulation('/stop')}
                    className="inline-flex items-center justify-center gap-2 rounded-2xl border border-rose-400/20 bg-rose-500/10 px-4 py-3 text-sm text-rose-100 hover:bg-rose-500/15"
                  >
                    <Square className="h-4 w-4" />
                    Stop
                  </button>
                </div>

                <div className="space-y-2">
                  <label className="text-xs uppercase tracking-[0.22em] text-slate-500">
                    Room Code
                  </label>
                  <input
                    value={simulationRoom}
                    onChange={(e) => setSimulationRoom(e.target.value)}
                    className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none placeholder:text-slate-500 focus:border-cyan-400/40"
                    placeholder="CHR_01"
                  />
                </div>

                <div className="space-y-2">
                  <label className="text-xs uppercase tracking-[0.22em] text-slate-500">
                    Event Type
                  </label>
                  <select
                    value={simulationEvent}
                    onChange={(e) => setSimulationEvent(e.target.value)}
                    className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none focus:border-cyan-400/40"
                  >
                    <option value="heartbeat">Heartbeat</option>
                    <option value="door_open">Door Open</option>
                    <option value="door_prolonged_open">Prolonged Door Open</option>
                    <option value="blockage">Blockage</option>
                    <option value="overflow">Overflow</option>
                    <option value="leak">Leak</option>
                    <option value="garbage_left">Garbage Left</option>
                    <option value="misuse">Misuse</option>
                  </select>
                </div>

                <button
                  onClick={() =>
                    callSimulation('/emit', {
                      room_code: simulationRoom,
                      event_type: simulationEvent,
                      severity: ['blockage', 'overflow', 'leak', 'misuse', 'door_prolonged_open'].includes(simulationEvent)
                        ? 'high'
                        : 'medium',
                    })
                  }
                  className="inline-flex w-full items-center justify-center gap-2 rounded-2xl border border-cyan-400/20 bg-cyan-500/10 px-4 py-3 text-sm text-cyan-100 hover:bg-cyan-500/15"
                >
                  <Send className="h-4 w-4" />
                  Inject False Input
                </button>

                <div className="rounded-2xl border border-white/10 bg-white/5 p-4 text-xs text-slate-400">
                  Simulation mode allows full dashboard validation without physical sensors or cameras.
                </div>
              </div>
            </div>

            <div className="rounded-3xl border border-white/10 bg-slate-950/75 p-5">
              <SectionHeader
                icon={MapPinned}
                title="Room Coverage"
                subtitle="Rooms inferred from connected devices and recent alerts."
              />

              <div className="space-y-3">
                {liveRooms.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-6 text-center text-slate-400">
                    No rooms detected.
                  </div>
                ) : (
                  liveRooms.slice(0, 6).map((room, idx) => (
                    <div
                      key={`${room.room_id}-${idx}`}
                      className="flex items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3"
                    >
                      <div>
                        <div className="font-medium text-white">{room.room_id || 'Unknown Room'}</div>
                        <div className="text-xs text-slate-500">PoE node assigned</div>
                      </div>
                      <Badge className="border-white/10 text-slate-200">
                        Live
                      </Badge>
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        </div>

        <footer className="mt-8 flex items-center justify-center gap-2 py-4 text-sm text-slate-500">
          <Clock3 className="h-4 w-4" />
          <span>Industrial dashboard operating in realtime monitoring mode.</span>
        </footer>
      </main>
    </div>
  );
}