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
  X,
} from 'lucide-react';

import { AuthForm } from './components/auth-form';
import { LoadingScreen, PortalShell } from './components/portal-shell';
import { usePortalSession } from './components/session';
import { apiUrl, resolveWebSocketUrl } from './lib/config';
import { ACKNOWLEDGE_ROLES } from './lib/roles';

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

function DetailPanel({ detail, onClose }) {
  if (!detail) return null;

  return (
    <div className="fixed inset-0 z-30 bg-black/55 backdrop-blur-sm">
      <div className="ml-auto flex h-full w-full max-w-2xl flex-col border-l border-white/10 bg-slate-950 shadow-2xl">
        <div className="flex items-start justify-between gap-4 border-b border-white/10 px-6 py-5">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-300">
              {detail.section}
            </div>
            <h2 className="mt-2 text-2xl font-semibold text-white">{detail.title}</h2>
            {detail.subtitle ? <p className="mt-2 text-sm text-slate-400">{detail.subtitle}</p> : null}
          </div>
          <button
            onClick={onClose}
            className="rounded-full border border-white/10 bg-white/5 p-2 text-white hover:bg-white/10"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 space-y-6 overflow-auto px-6 py-6">
          {detail.highlights?.length ? (
            <div className="grid gap-3 sm:grid-cols-2">
              {detail.highlights.map((item) => (
                <div key={`${item.label}-${item.value}`} className="rounded-2xl border border-white/10 bg-white/5 p-4">
                  <div className="text-xs uppercase tracking-[0.18em] text-slate-500">{item.label}</div>
                  <div className="mt-2 text-sm font-medium text-white">{item.value}</div>
                </div>
              ))}
            </div>
          ) : null}

          <div className="rounded-[28px] border border-white/10 bg-white/5 p-5">
            <div className="text-xs uppercase tracking-[0.2em] text-slate-500">Raw Payload</div>
            <pre className="mt-4 overflow-auto rounded-2xl bg-black/30 p-4 text-xs leading-6 text-cyan-100">
              {JSON.stringify(detail.payload, null, 2)}
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
}

function MetricCard({ icon: Icon, label, value, helper, tone = 'cyan', onClick }) {
  const tones = {
    cyan: 'from-cyan-500/20 to-cyan-500/5 border-cyan-400/20',
    amber: 'from-amber-500/20 to-amber-500/5 border-amber-400/20',
    rose: 'from-rose-500/20 to-rose-500/5 border-rose-400/20',
    emerald: 'from-emerald-500/20 to-emerald-500/5 border-emerald-400/20',
  };

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'rounded-3xl border bg-gradient-to-br p-5 text-left shadow-[0_12px_36px_rgba(0,0,0,0.25)] transition hover:-translate-y-0.5 hover:border-cyan-300/30',
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
    </button>
  );
}

function AlertItem({ alert, onAck, canAck, onSelect }) {
  const severityStyles = {
    critical: 'border-rose-500/40 bg-rose-500/10 text-rose-200',
    high: 'border-orange-500/40 bg-orange-500/10 text-orange-200',
    medium: 'border-amber-500/40 bg-amber-500/10 text-amber-100',
    low: 'border-sky-500/40 bg-sky-500/10 text-sky-100',
    info: 'border-slate-500/40 bg-slate-500/10 text-slate-100',
  };

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => onSelect(alert)}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          onSelect(alert);
        }
      }}
      className={cn(
        'w-full rounded-2xl border p-4 text-left transition hover:border-cyan-300/30',
        severityStyles[alert.severity] || severityStyles.medium
      )}
    >
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
              onClick={(event) => {
                event.stopPropagation();
                onAck(alert);
              }}
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

function DeviceCard({ device, onSelect }) {
  const online = String(device.status || '').toLowerCase() === 'online';

  return (
    <button
      type="button"
      onClick={() => onSelect(device)}
      className="rounded-3xl border border-white/10 bg-slate-950/70 p-5 text-left transition hover:border-cyan-300/30"
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <h3 className="font-semibold tracking-tight text-white">{device.device_id}</h3>
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
    </button>
  );
}

function TimelineEvent({ event, onSelect }) {
  return (
    <button
      type="button"
      onClick={() => onSelect(event)}
      className="w-full rounded-2xl border border-white/10 bg-white/5 p-3 text-left transition hover:border-cyan-300/30"
    >
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
    </button>
  );
}

function AiEventCard({ event, onSelect }) {
  return (
    <button
      type="button"
      onClick={() => onSelect(event)}
      className="w-full rounded-2xl border border-white/10 bg-white/5 p-4 text-left transition hover:border-cyan-300/30"
    >
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="font-semibold text-white">{event.room_code || event.payload?.room_code || `Room ${event.room_id}`}</div>
          <div className="mt-1 text-sm text-slate-300">{formatEventLabel(event.event_type)}</div>
        </div>
        <Badge className="border-amber-400/20 bg-amber-500/10 text-amber-100">
          {(Number(event.confidence || 0) * 100).toFixed(0)}%
        </Badge>
      </div>
      <div className="mt-3 text-xs text-slate-500">
        Camera {event.camera_id || '--'} | {formatTime(event.created_at)}
      </div>
    </button>
  );
}

function useSocket(token) {
  const [events, setEvents] = useState([]);

  useEffect(() => {
    if (!token) return undefined;

    const baseWsUrl = resolveWebSocketUrl();
    const wsUrl = `${baseWsUrl}${baseWsUrl.includes('?') ? '&' : '?'}token=${token}`;
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
  const [selectedDetail, setSelectedDetail] = useState(null);

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
  const { data: aiEvents } = useSWR(
    session.token ? apiUrl('/ai-events?limit=12') : null,
    session.fetcher,
    { refreshInterval: 5000 }
  );
  const { data: otaJobs } = useSWR(
    session.token ? apiUrl('/ota/jobs') : null,
    session.fetcher,
    { refreshInterval: 7000 }
  );

  const alertList = useMemo(() => (Array.isArray(alerts) ? alerts : []), [alerts]);
  const deviceList = useMemo(() => (Array.isArray(devices) ? devices : []), [devices]);
  const roomList = useMemo(() => (Array.isArray(rooms) ? rooms : []), [rooms]);
  const aiEventList = useMemo(() => (Array.isArray(aiEvents) ? aiEvents : []), [aiEvents]);
  const otaJobList = useMemo(() => (Array.isArray(otaJobs) ? otaJobs : []), [otaJobs]);
  const onlineDevices = deviceList.filter((device) => String(device.status).toLowerCase() === 'online').length;

  const canAcknowledge = ACKNOWLEDGE_ROLES.has(session.user?.role);

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

  const openDetail = useCallback((section, title, payload, highlights = [], subtitle = '') => {
    setSelectedDetail({ section, title, payload, highlights, subtitle });
  }, []);

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
    <>
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
                  This control-room surface is restricted to operational visibility only. Administration, node drafting, and activation remain isolated in their own role-gated portals.
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
          </div>

          <div className="rounded-[32px] border border-white/10 bg-slate-950/75 p-6">
            <div className="text-xs uppercase tracking-[0.22em] text-slate-500">Operational Snapshot</div>
            <div className="mt-2 text-lg font-semibold text-white">Current system state</div>

            <div className="mt-5 space-y-3">
              <button
                type="button"
                onClick={() =>
                  openDetail('Snapshot', 'AI Event Throughput', { summary, ai_events: aiEventList }, [
                    { label: 'AI Events 24h', value: `${summary?.ai_events_24h || 0}` },
                    { label: 'Latest Visible Events', value: `${aiEventList.length}` },
                  ])
                }
                className="flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:border-cyan-300/30"
              >
                <span className="flex items-center gap-2 text-slate-300">
                  <Camera className="h-4 w-4 text-cyan-300" />
                  AI Events (24h)
                </span>
                <span className="font-semibold">{summary?.ai_events_24h || 0}</span>
              </button>
              <button
                type="button"
                onClick={() =>
                  openDetail('Snapshot', 'OTA Activity', { summary, ota_jobs: otaJobList }, [
                    { label: 'Active OTA Jobs', value: `${summary?.ota_jobs_active || 0}` },
                    { label: 'Visible Jobs', value: `${otaJobList.length}` },
                  ])
                }
                className="flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:border-cyan-300/30"
              >
                <span className="flex items-center gap-2 text-slate-300">
                  <Radio className="h-4 w-4 text-violet-300" />
                  OTA Jobs Active
                </span>
                <span className="font-semibold">{summary?.ota_jobs_active || 0}</span>
              </button>
              <button
                type="button"
                onClick={() =>
                  openDetail('Snapshot', 'Alert Queue', { summary, alerts: alertList.slice(0, 24) }, [
                    { label: 'Open Alerts', value: `${summary?.alerts_open || 0}` },
                    { label: 'Visible Alerts', value: `${alertList.length}` },
                  ])
                }
                className="flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:border-cyan-300/30"
              >
                <span className="flex items-center gap-2 text-slate-300">
                  <AlertTriangle className="h-4 w-4 text-rose-300" />
                  Open Alerts
                </span>
                <span className="font-semibold">{summary?.alerts_open || 0}</span>
              </button>
              <button
                type="button"
                onClick={() =>
                  openDetail('Snapshot', 'Online Device Coverage', { devices: deviceList }, [
                    { label: 'Online Devices', value: `${onlineDevices}` },
                    { label: 'Total Devices', value: `${summary?.devices || 0}` },
                  ])
                }
                className="flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:border-cyan-300/30"
              >
                <span className="text-slate-300">Online Devices</span>
                <span className="font-semibold">{onlineDevices}</span>
              </button>
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
              <MetricCard
                icon={Building2}
                label="Buildings"
                value={summary?.buildings ?? 0}
                helper="Active buildings"
                tone="cyan"
                onClick={() =>
                  openDetail('Summary', 'Building Coverage', { summary, rooms: roomList }, [
                    { label: 'Buildings', value: `${summary?.buildings ?? 0}` },
                    { label: 'Rooms', value: `${summary?.rooms ?? 0}` },
                  ])
                }
              />
              <MetricCard
                icon={Trash2}
                label="Rooms"
                value={summary?.rooms ?? 0}
                helper="Room-aware monitoring"
                tone="amber"
                onClick={() =>
                  openDetail('Summary', 'Room Coverage', { rooms: roomList }, [
                    { label: 'Rooms', value: `${summary?.rooms ?? 0}` },
                    { label: 'Visible Rooms', value: `${roomList.length}` },
                  ])
                }
              />
              <MetricCard
                icon={Cpu}
                label="Devices"
                value={summary?.devices ?? 0}
                helper="ESP32 PoE nodes"
                tone="emerald"
                onClick={() =>
                  openDetail('Summary', 'Device Footprint', { devices: deviceList }, [
                    { label: 'Devices', value: `${summary?.devices ?? 0}` },
                    { label: 'Online', value: `${onlineDevices}` },
                  ])
                }
              />
              <MetricCard
                icon={AlertTriangle}
                label="Open Alerts"
                value={summary?.alerts_open ?? 0}
                helper="Pending response queue"
                tone="rose"
                onClick={() =>
                  openDetail('Summary', 'Open Alert Queue', { alerts: alertList }, [
                    { label: 'Open Alerts', value: `${summary?.alerts_open ?? 0}` },
                    { label: 'Recent Alerts', value: `${alertList.length}` },
                  ])
                }
              />
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
                      onSelect={(item) =>
                        openDetail('Alert', item.message, item, [
                          { label: 'Severity', value: item.severity },
                          { label: 'Room', value: item.room_code || item.room_id || '--' },
                          { label: 'Created', value: formatTime(item.created_at) },
                          { label: 'Acknowledged', value: item.acknowledged ? 'Yes' : 'No' },
                        ])
                      }
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
                  <DeviceCard
                    key={device.id || device.device_id}
                    device={device}
                    onSelect={(item) =>
                      openDetail('Device', item.device_id, item, [
                        { label: 'Room', value: item.room_code || '--' },
                        { label: 'Status', value: item.status || '--' },
                        { label: 'Firmware', value: item.firmware_version || '--' },
                        { label: 'Last Seen', value: formatTime(item.last_seen_at) },
                      ])
                    }
                  />
                ))}
              </div>
            </section>

            <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
              <div className="mb-4 flex items-center gap-2">
                <Camera className="h-5 w-5 text-cyan-300" />
                <div>
                  <h3 className="text-lg font-semibold text-white">AI CCTV Detections</h3>
                  <p className="text-sm text-slate-400">Current AI-generated misuse, overflow, and floor-object events.</p>
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                {aiEventList.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-8 text-center text-slate-400 md:col-span-2">
                    No AI detections in the current window.
                  </div>
                ) : (
                  aiEventList.map((event) => (
                    <AiEventCard
                      key={event.id}
                      event={event}
                      onSelect={(item) =>
                        openDetail('AI Event', `${item.event_type} | ${item.camera_id}`, item, [
                          { label: 'Room', value: item.payload?.room_code || item.room_code || `Room ${item.room_id}` },
                          { label: 'Camera', value: item.camera_id || '--' },
                          { label: 'Confidence', value: `${(Number(item.confidence || 0) * 100).toFixed(0)}%` },
                          { label: 'Created', value: formatTime(item.created_at) },
                        ])
                      }
                    />
                  ))
                )}
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
                  socketEvents.map((event, index) => (
                    <TimelineEvent
                      key={index}
                      event={event}
                      onSelect={(item) =>
                        openDetail('Realtime Event', formatEventLabel(item.type || item.event_type || item.category), item, [
                          { label: 'Type', value: item.type || item.event_type || item.category || '--' },
                          { label: 'Room', value: item.room_code || item.room_id || '--' },
                          { label: 'Severity', value: item.severity || '--' },
                          { label: 'Timestamp', value: formatTime(item.timestamp || item.created_at) },
                        ])
                      }
                    />
                  ))
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
                  <button
                    key={room.id || room.room_code}
                    type="button"
                    onClick={() =>
                      openDetail('Room', `${room.room_code || room.id} | ${room.name || 'Chute room'}`, room, [
                        { label: 'Building', value: room.building_code || '--' },
                        { label: 'Floor', value: room.floor_level ? `Level ${room.floor_level}` : '--' },
                        { label: 'Status', value: room.status || '--' },
                        { label: 'Open Alerts', value: `${room.open_alert_count || 0}` },
                      ])
                    }
                    className="flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:border-cyan-300/30"
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
                  </button>
                ))}
              </div>
            </section>

            <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
              <div className="mb-4 flex items-center gap-2">
                <Radio className="h-5 w-5 text-cyan-300" />
                <div>
                  <h3 className="text-lg font-semibold text-white">OTA Watch</h3>
                  <p className="text-sm text-slate-400">Active and recent firmware rollout scope.</p>
                </div>
              </div>

              <div className="space-y-3">
                {otaJobList.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-6 text-sm text-slate-400">
                    No OTA jobs recorded.
                  </div>
                ) : (
                  otaJobList.slice(0, 6).map((job) => (
                    <button
                      key={job.id}
                      type="button"
                      onClick={() =>
                        openDetail('OTA Job', `${job.target_type} | ${job.target_ref}`, job, [
                          { label: 'Firmware', value: job.firmware_version || '--' },
                          { label: 'Status', value: job.status || '--' },
                          { label: 'Progress', value: `${job.progress || 0}%` },
                          { label: 'Requested By', value: job.requested_by || '--' },
                        ])
                      }
                      className="flex w-full items-center justify-between rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:border-cyan-300/30"
                    >
                      <div>
                        <div className="font-medium text-white">{job.target_ref || `Job ${job.id}`}</div>
                        <div className="text-xs text-slate-500">
                          {job.target_type} | firmware {job.firmware_version}
                        </div>
                      </div>
                      <Badge className="border-white/10 text-slate-200">{job.status}</Badge>
                    </button>
                  ))
                )}
              </div>
            </section>
          </div>
        </div>
      </PortalShell>

      <DetailPanel detail={selectedDetail} onClose={() => setSelectedDetail(null)} />
    </>
  );
}
