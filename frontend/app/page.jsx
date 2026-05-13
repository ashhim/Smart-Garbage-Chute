'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  Activity,
  AlertTriangle,
  BellRing,
  Building2,
  Camera,
  CheckCircle2,
  Cpu,
  Radio,
  Server,
  ShieldCheck,
  Trash2,
  Wifi,
} from 'lucide-react';

import { AuthForm } from './components/auth-form';
import { LoadingScreen, PortalShell } from './components/portal-shell';
import { usePortalSession } from './components/session';
import { API_BASE, WS_URL, apiUrl } from './lib/config';
import { ACKNOWLEDGE_ROLES, SIMULATION_ROLES, SYSTEM_ADMIN_ROLES } from './lib/roles';

function cn(...classes) {
  return classes.filter(Boolean).join(' ');
}

function formatTime(value) {
  if (!value) return '--';
  try {
    return new Date(value).toLocaleString();
  } catch {
    return String(value);
  }
}

function formatEventLabel(value) {
  return value ? String(value).replaceAll('_', ' ') : 'event';
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

function MetricCard({ icon: Icon, label, value, helper, tone = 'cyan' }) {
  const tones = {
    cyan: 'from-cyan-500/20 to-cyan-500/5 border-cyan-400/20',
    amber: 'from-amber-500/20 to-amber-500/5 border-amber-400/20',
    rose: 'from-rose-500/20 to-rose-500/5 border-rose-400/20',
    emerald: 'from-emerald-500/20 to-emerald-500/5 border-emerald-400/20',
  };

  return (
    <div
      className={cn(
        'rounded-3xl border bg-gradient-to-br p-5 shadow-[0_12px_36px_rgba(0,0,0,0.25)]',
        tones[tone] || tones.cyan
      )}
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm text-slate-400">{label}</p>
          <div className="mt-2 text-3xl font-semibold tracking-tight text-white">{value}</div>
          <p className="mt-2 text-xs text-slate-500">{helper}</p>
        </div>
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl border border-white/10 bg-white/5">
          <Icon className="h-6 w-6 text-white" />
        </div>
      </div>
    </div>
  );
}

function AlertItem({ alert, onAck, canAck }) {
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
            <AlertTriangle className="h-4 w-4" />
            <div className="font-semibold uppercase tracking-wide">{formatEventLabel(alert.category)}</div>
            <Badge className="border-white/15 text-white/80">{alert.severity}</Badge>
          </div>
          <p className="text-sm text-white/90">{alert.message}</p>
          <div className="flex flex-wrap gap-3 text-xs text-white/60">
            <span>Room: {alert.room_code || alert.room_id || '--'}</span>
            <span>Source: {alert.source || 'system'}</span>
            <span>Time: {formatTime(alert.created_at)}</span>
          </div>
        </div>

        <div className="flex flex-col items-end gap-2">
          {alert.acknowledged ? (
            <Badge className="border-emerald-400/30 bg-emerald-500/10 text-emerald-200">ACKED</Badge>
          ) : canAck ? (
            <button
              onClick={() => onAck(alert)}
              className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-white hover:bg-white/10"
            >
              <CheckCircle2 className="h-4 w-4" />
              Acknowledge
            </button>
          ) : (
            <Badge className="border-white/10 text-slate-300">VIEW ONLY</Badge>
          )}
        </div>
      </div>
    </div>
  );
}

function DeviceCard({ device }) {
  const online = String(device.status || '').toLowerCase() === 'online';

  return (
    <div className="rounded-3xl border border-white/10 bg-slate-950/70 p-5">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h3 className="text-white font-semibold tracking-tight">{device.device_id}</h3>
          <p className="mt-1 text-sm text-slate-400">{device.device_type}</p>
        </div>
        <div className={online ? 'h-3 w-3 rounded-full bg-emerald-400' : 'h-3 w-3 rounded-full bg-rose-400'} />
      </div>

      <div className="mt-5 space-y-2 text-sm text-slate-300">
        <div className="flex justify-between gap-3">
          <span className="text-slate-500">Room</span>
          <span>{device.room_name ? `${device.room_code} - ${device.room_name}` : device.room_code || '--'}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-slate-500">Location</span>
          <span>{device.building_code && device.floor_level ? `${device.building_code} / Level ${device.floor_level}` : '--'}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-slate-500">Firmware</span>
          <span>{device.firmware_version || '--'}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-slate-500">Last Seen</span>
          <span>{formatTime(device.last_seen_at)}</span>
        </div>
      </div>
    </div>
  );
}

function TimelineEvent({ event }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-cyan-300" />
          <span className="text-sm font-medium text-white">
            {formatEventLabel(event.type || event.event_type || event.category)}
          </span>
        </div>
        <span className="text-xs text-slate-500">
          {formatTime(event.timestamp || event.created_at)}
        </span>
      </div>
      <pre className="mt-2 rounded-xl bg-black/25 p-3 text-[11px] leading-5 text-cyan-100">
        {JSON.stringify(event, null, 2)}
      </pre>
    </div>
  );
}

function useSocket(token) {
  const [events, setEvents] = useState([]);

  useEffect(() => {
    if (!token) return undefined;

    const wsUrl = `${WS_URL}${WS_URL.includes('?') ? '&' : '?'}token=${token}`;
    let ws;

    try {
      ws = new WebSocket(wsUrl);
    } catch {
      return undefined;
    }

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        setEvents((previous) => [data, ...previous].slice(0, 16));
      } catch (error) {
        console.error(error);
      }
    };

    return () => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    };
  }, [token]);

  return events;
}

export default function MonitoringPage() {
  const session = usePortalSession();
  const socketEvents = useSocket(session.token);
  const [statusMessage, setStatusMessage] = useState('');

  const { data: summary, mutate: refreshSummary } = useSWR(
    session.token ? apiUrl('/analytics/summary') : null,
    session.fetcher,
    { refreshInterval: 5000 }
  );
  const { data: alerts, mutate: refreshAlerts } = useSWR(
    session.token ? apiUrl('/alerts') : null,
    session.fetcher,
    { refreshInterval: 5000 }
  );
  const { data: devices } = useSWR(
    session.token ? apiUrl('/devices') : null,
    session.fetcher,
    { refreshInterval: 5000 }
  );
  const { data: rooms } = useSWR(
    session.token ? apiUrl('/rooms') : null,
    session.fetcher,
    { refreshInterval: 5000 }
  );

  const alertList = useMemo(() => (Array.isArray(alerts) ? alerts : []), [alerts]);
  const deviceList = useMemo(() => (Array.isArray(devices) ? devices : []), [devices]);
  const roomList = useMemo(() => (Array.isArray(rooms) ? rooms : []), [rooms]);
  const onlineDevices = deviceList.filter((device) => String(device.status).toLowerCase() === 'online').length;

  const canAcknowledge = ACKNOWLEDGE_ROLES.has(session.user?.role);
  const canSeeInjectionLink = SIMULATION_ROLES.has(session.user?.role);
  const canSeeAdminLink = SYSTEM_ADMIN_ROLES.has(session.user?.role);

  const acknowledgeAlert = useCallback(
    async (alert) => {
      try {
        await session.request(`/alerts/${alert.id}/acknowledge`, {
          method: 'POST',
          body: {},
        });
        setStatusMessage(`Alert ${alert.id} acknowledged.`);
        refreshAlerts();
        refreshSummary();
      } catch (error) {
        console.error(error);
        setStatusMessage(error.message || 'Acknowledge action failed.');
      }
    },
    [refreshAlerts, refreshSummary, session]
  );

  if (session.loading) {
    return <LoadingScreen label="Loading monitoring surface..." />;
  }

  if (!session.token) {
    return (
      <AuthForm
        title="Realtime Monitoring Website"
        subtitle="Operational surface for control-room staff monitoring live telemetry, alerts, device health, AI detections, and room status."
        helper="This monitoring surface intentionally excludes node creation forms, user management, and simulation controls."
        authError={session.authError}
        onLogin={session.login}
        accent="cyan"
      />
    );
  }

  return (
    <PortalShell
      title="Smart Garbage Chute Monitoring"
      subtitle="Live operational dashboard for control-room use."
      section="Main Website"
      currentPath="/"
      session={session}
    >
      <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
        <div className="rounded-[32px] border border-white/10 bg-white/5 p-6 shadow-2xl shadow-black/20">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="max-w-2xl">
              <div className="flex items-center gap-2 text-cyan-300">
                <ShieldCheck className="h-5 w-5" />
                <span className="text-xs font-semibold uppercase tracking-[0.24em]">
                  Industrial Monitoring Surface
                </span>
              </div>
              <h2 className="mt-4 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
                Live chute-room telemetry, alerts, AI events, and room coverage.
              </h2>
              <p className="mt-3 max-w-2xl text-sm leading-7 text-slate-300">
                This control-room surface is intentionally limited to current operational state. Admin workflows and node injection remain isolated in their own portals.
              </p>
            </div>

            <div className="flex flex-wrap gap-2">
              <Badge className="border-cyan-400/20 bg-cyan-500/10 text-cyan-200">
                <Wifi className="mr-1 h-3.5 w-3.5" />
                Live
              </Badge>
              <Badge className="border-emerald-400/20 bg-emerald-500/10 text-emerald-200">MQTT</Badge>
              <Badge className="border-amber-400/20 bg-amber-500/10 text-amber-200">AI CCTV</Badge>
              <Badge className="border-violet-400/20 bg-violet-500/10 text-violet-200">WebSocket</Badge>
            </div>
          </div>

          <div className="mt-6 flex flex-wrap gap-3">
            {canSeeAdminLink ? (
              <a
                href="/admin"
                className="rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm text-white hover:bg-white/10"
              >
                Open Admin Website
              </a>
            ) : null}
            {canSeeInjectionLink ? (
              <a
                href="/injection"
                className="rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm text-white hover:bg-white/10"
              >
                Open Node Injection Website
              </a>
            ) : null}
          </div>
        </div>

        <div className="rounded-[32px] border border-white/10 bg-slate-950/75 p-6">
          <div className="text-xs uppercase tracking-[0.22em] text-slate-500">Operational Snapshot</div>
          <div className="mt-2 text-lg font-semibold text-white">Current system state</div>

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
            <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
              <span className="text-slate-300">Online Devices</span>
              <span className="font-semibold">{onlineDevices}</span>
            </div>
          </div>

          {statusMessage ? (
            <div className="mt-4 rounded-2xl border border-cyan-400/20 bg-cyan-500/10 px-4 py-3 text-sm text-cyan-100">
              {statusMessage}
            </div>
          ) : null}
        </div>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-12">
        <div className="space-y-6 xl:col-span-8">
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard icon={Building2} label="Buildings" value={summary?.buildings ?? 0} helper="Active buildings" tone="cyan" />
            <MetricCard icon={Trash2} label="Rooms" value={summary?.rooms ?? 0} helper="Room-aware monitoring" tone="amber" />
            <MetricCard icon={Cpu} label="Devices" value={summary?.devices ?? 0} helper="ESP32 PoE nodes" tone="emerald" />
            <MetricCard icon={AlertTriangle} label="Open Alerts" value={summary?.alerts_open ?? 0} helper="Pending response queue" tone="rose" />
          </div>

          <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
            <div className="mb-4 flex items-center gap-2">
              <BellRing className="h-5 w-5 text-cyan-300" />
              <div>
                <h3 className="text-lg font-semibold text-white">Recent Alerts</h3>
                <p className="text-sm text-slate-400">Live alert stream requiring operational attention.</p>
              </div>
            </div>

            <div className="space-y-4">
              {alertList.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-8 text-center text-slate-400">
                  No active alerts. The chute network is stable.
                </div>
              ) : (
                alertList.slice(0, 8).map((alert) => (
                  <AlertItem
                    key={alert.id}
                    alert={alert}
                    onAck={acknowledgeAlert}
                    canAck={canAcknowledge}
                  />
                ))
              )}
            </div>
          </section>

          <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
            <div className="mb-4 flex items-center gap-2">
              <Server className="h-5 w-5 text-cyan-300" />
              <div>
                <h3 className="text-lg font-semibold text-white">Device Monitoring</h3>
                <p className="text-sm text-slate-400">Live PoE controller visibility by room.</p>
              </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
              {deviceList.map((device) => (
                <DeviceCard key={device.id || device.device_id} device={device} />
              ))}
            </div>
          </section>
        </div>

        <div className="space-y-6 xl:col-span-4">
          <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
            <div className="mb-4 flex items-center gap-2">
              <Activity className="h-5 w-5 text-cyan-300" />
              <div>
                <h3 className="text-lg font-semibold text-white">Live WebSocket Feed</h3>
                <p className="text-sm text-slate-400">Realtime telemetry, AI detections, and alert broadcasts.</p>
              </div>
            </div>

            <div className="max-h-[420px] space-y-3 overflow-auto pr-1">
              {socketEvents.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-6 text-sm text-slate-400">
                  Waiting for realtime events...
                </div>
              ) : (
                socketEvents.map((event, index) => <TimelineEvent key={index} event={event} />)
              )}
            </div>
          </section>

          <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
            <div className="mb-4 flex items-center gap-2">
              <Building2 className="h-5 w-5 text-cyan-300" />
              <div>
                <h3 className="text-lg font-semibold text-white">Room Coverage</h3>
                <p className="text-sm text-slate-400">Live room state and open alert count.</p>
              </div>
            </div>

            <div className="space-y-3">
              {roomList.slice(0, 10).map((room) => (
                <div
                  key={room.id || room.room_code}
                  className="flex items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3"
                >
                  <div>
                    <div className="font-medium text-white">{room.room_code || room.id}</div>
                    <div className="text-xs text-slate-500">
                      {room.name || 'Chute room'}
                      {room.building_code && room.floor_level
                        ? ` | ${room.building_code} / Level ${room.floor_level}`
                        : ''}
                    </div>
                  </div>
                  <Badge className="border-white/10 text-slate-200">
                    {formatEventLabel(room.status || 'normal')}
                    {room.open_alert_count ? ` (${room.open_alert_count})` : ''}
                  </Badge>
                </div>
              ))}
            </div>
          </section>
        </div>
      </div>
    </PortalShell>
  );
}
