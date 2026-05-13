'use client';

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  Bot,
  Cpu,
  PauseCircle,
  PlayCircle,
  Send,
  ShieldCheck,
  SquareTerminal,
  TestTube2,
  Trash2,
} from 'lucide-react';

import { AuthForm } from '../components/auth-form';
import {
  AccessDeniedScreen,
  LoadingScreen,
  PortalShell,
} from '../components/portal-shell';
import { usePortalSession } from '../components/session';
import { apiUrl } from '../lib/config';

const SENSOR_OPTIONS = [
  { value: 'ir_blockage', label: 'IR Blockage' },
  { value: 'ultrasonic', label: 'Ultrasonic' },
  { value: 'door_contact', label: 'Door Contact' },
  { value: 'leak_sensor', label: 'Leak Sensor' },
  { value: 'heartbeat', label: 'Heartbeat' },
  { value: 'cctv_ai', label: 'CCTV / AI' },
];

const EVENT_OPTIONS = [
  'heartbeat',
  'door_open',
  'door_prolonged_open',
  'blockage',
  'overflow',
  'leak',
  'motion',
  'garbage_left',
  'misuse',
];

function SectionCard({ icon: Icon, title, subtitle, children }) {
  return (
    <section className="rounded-[32px] border border-white/10 bg-slate-950/75 p-5">
      <div className="mb-4 flex items-center gap-3">
        <div className="flex h-11 w-11 items-center justify-center rounded-2xl border border-white/10 bg-white/5">
          <Icon className="h-5 w-5 text-cyan-300" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-white">{title}</h2>
          <p className="text-sm text-slate-400">{subtitle}</p>
        </div>
      </div>
      {children}
    </section>
  );
}

function TextInput({ value, onChange, placeholder }) {
  return (
    <input
      value={value}
      onChange={(event) => onChange(event.target.value)}
      placeholder={placeholder}
      className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
    />
  );
}

function Badge({ children }) {
  return (
    <span className="rounded-full border border-white/10 px-2.5 py-1 text-[11px] uppercase tracking-[0.14em] text-slate-200">
      {children}
    </span>
  );
}

export default function InjectionPage() {
  const session = usePortalSession(['system_admin', 'facility_admin']);
  const [statusMessage, setStatusMessage] = useState('');
  const [nodeForm, setNodeForm] = useState({
    label: '',
    room_code: '',
    notes: '',
    auto_mode: false,
    sensor_types: SENSOR_OPTIONS.map((option) => option.value),
  });
  const [eventSelections, setEventSelections] = useState({});

  const rooms = useSWR(session.token ? apiUrl('/rooms') : null, session.fetcher, {
    refreshInterval: 8000,
  });
  const nodes = useSWR(session.token ? apiUrl('/injection/nodes') : null, session.fetcher, {
    refreshInterval: 5000,
  });

  const roomOptions = useMemo(
    () =>
      (Array.isArray(rooms.data) ? rooms.data : []).map((room) => ({
        value: room.room_code,
        label: `${room.room_code} - ${room.name}`,
      })),
    [rooms.data]
  );

  async function runAction(action, successMessage) {
    try {
      await action();
      setStatusMessage(successMessage);
      await Promise.all([nodes.mutate(), rooms.mutate()]);
    } catch (error) {
      console.error(error);
      setStatusMessage(error.message || 'Action failed.');
    }
  }

  function selectedEvent(nodeId) {
    return eventSelections[nodeId] || 'heartbeat';
  }

  if (session.loading) {
    return <LoadingScreen label="Loading node injection website..." />;
  }

  if (!session.token) {
    return (
      <AuthForm
        title="ESP32 Node Injection Website"
        subtitle="Internal test surface for staged ESP32 draft creation, realistic sensor emission, and admin-gated activation into the live monitoring system."
        helper="Facility administrators and system administrators can access this surface."
        authError={session.authError}
        onLogin={session.login}
        accent="rose"
      />
    );
  }

  if (!session.authorized) {
    return <AccessDeniedScreen role={session.user?.role} onLogout={session.logout} />;
  }

  return (
    <PortalShell
      title="ESP32 Node Injection And Simulation"
      subtitle="Internal test website for draft-only node creation, per-node telemetry emission, and approval handoff."
      section="Node Injection Website"
      currentPath="/injection"
      session={session}
    >
      {statusMessage ? (
        <div className="mb-6 rounded-2xl border border-cyan-400/20 bg-cyan-500/10 px-4 py-3 text-sm text-cyan-100">
          {statusMessage}
        </div>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-[0.95fr_1.05fr]">
        <SectionCard
          icon={Bot}
          title="Create Pending Draft"
          subtitle="Create a simulated ESP32 draft only. The official node ID is generated later in the admin portal."
        >
          <div className="grid gap-3">
            <TextInput
              value={nodeForm.label}
              onChange={(value) => setNodeForm((current) => ({ ...current, label: value }))}
              placeholder="Draft label"
            />
            <select
              value={nodeForm.room_code}
              onChange={(event) =>
                setNodeForm((current) => ({ ...current, room_code: event.target.value }))
              }
              className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
            >
              <option value="">Select room</option>
              {roomOptions.map((room) => (
                <option key={room.value} value={room.value}>
                  {room.label}
                </option>
              ))}
            </select>
            <TextInput
              value={nodeForm.notes}
              onChange={(value) => setNodeForm((current) => ({ ...current, notes: value }))}
              placeholder="Draft notes"
            />
            <label className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-slate-200">
              <input
                type="checkbox"
                checked={nodeForm.auto_mode}
                onChange={(event) =>
                  setNodeForm((current) => ({ ...current, auto_mode: event.target.checked }))
                }
              />
              <span>Enable per-node auto mode</span>
            </label>
          </div>

          <div className="mt-4 grid gap-2 sm:grid-cols-2">
            {SENSOR_OPTIONS.map((option) => {
              const checked = nodeForm.sensor_types.includes(option.value);
              return (
                <label
                  key={option.value}
                  className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-slate-200"
                >
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={(event) =>
                      setNodeForm((current) => ({
                        ...current,
                        sensor_types: event.target.checked
                          ? [...current.sensor_types, option.value]
                          : current.sensor_types.filter((sensor) => sensor !== option.value),
                      }))
                    }
                  />
                  <span>{option.label}</span>
                </label>
              );
            })}
          </div>

          <button
            onClick={() =>
              runAction(
                () =>
                  session.request('/injection/nodes', {
                    method: 'POST',
                    body: nodeForm,
                  }),
                'Created pending draft node.'
              )
            }
            className="mt-5 inline-flex items-center gap-2 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-300"
          >
            <Cpu className="h-4 w-4" />
            Create Draft
          </button>
        </SectionCard>

        <SectionCard
          icon={SquareTerminal}
          title="Per-Node Controls"
          subtitle="Emit realistic payloads, pause or resume draft behavior, and submit drafts for admin approval."
        >
          <div className="space-y-4">
            {(Array.isArray(nodes.data) ? nodes.data : []).map((node) => (
              <div key={node.node_id} className="rounded-3xl border border-white/10 bg-white/5 p-5">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="text-lg font-semibold text-white">{node.label || 'Pending Node Draft'}</div>
                    <div className="mt-1 text-sm text-slate-400">
                      Draft reference {node.draft_reference} | {node.room_code || 'Unassigned room'}
                    </div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      <Badge>{node.approval_status || 'draft'}</Badge>
                      <Badge>{node.status || 'draft'}</Badge>
                      {node.official_device_id ? <Badge>official {node.official_device_id}</Badge> : null}
                    </div>
                    <div className="mt-3 flex flex-wrap gap-2">
                      {(node.sensor_types || []).map((sensor) => (
                        <Badge key={sensor}>{sensor}</Badge>
                      ))}
                    </div>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <button
                      onClick={() =>
                        runAction(
                          () =>
                            session.request(`/injection/nodes/${node.node_id}`, {
                              method: 'PATCH',
                              body: { paused: !node.paused },
                            }),
                          `${node.paused ? 'Resumed' : 'Paused'} ${node.draft_reference}.`
                        )
                      }
                      className="rounded-2xl border border-white/10 bg-white/5 px-4 py-2 text-sm text-white hover:bg-white/10"
                    >
                      {node.paused ? (
                        <span className="inline-flex items-center gap-2">
                          <PlayCircle className="h-4 w-4" />
                          Resume
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-2">
                          <PauseCircle className="h-4 w-4" />
                          Pause
                        </span>
                      )}
                    </button>
                    <button
                      onClick={() =>
                        runAction(
                          () =>
                            session.request(`/injection/nodes/${node.node_id}`, {
                              method: 'PATCH',
                              body: { auto_mode: !node.auto_mode },
                            }),
                          `${node.auto_mode ? 'Disabled' : 'Enabled'} auto mode for ${node.draft_reference}.`
                        )
                      }
                      className="rounded-2xl border border-emerald-400/20 bg-emerald-500/10 px-4 py-2 text-sm text-emerald-100 hover:bg-emerald-500/15"
                    >
                      {node.auto_mode ? 'Disable Auto' : 'Enable Auto'}
                    </button>
                    <button
                      onClick={() =>
                        runAction(
                          () =>
                            session.request(`/injection/nodes/${node.node_id}/submit-approval`, {
                              method: 'POST',
                              body: { notes: node.notes || '' },
                            }),
                          `Submitted ${node.draft_reference} for admin approval.`
                        )
                      }
                      className="rounded-2xl border border-cyan-400/20 bg-cyan-500/10 px-4 py-2 text-sm text-cyan-100 hover:bg-cyan-500/15"
                    >
                      <span className="inline-flex items-center gap-2">
                        <ShieldCheck className="h-4 w-4" />
                        Submit For Approval
                      </span>
                    </button>
                    <button
                      onClick={() =>
                        runAction(
                          () => session.request(`/injection/nodes/${node.node_id}`, { method: 'DELETE' }),
                          `Deleted draft ${node.draft_reference}.`
                        )
                      }
                      className="rounded-2xl border border-rose-400/20 bg-rose-500/10 px-4 py-2 text-sm text-rose-100 hover:bg-rose-500/15"
                    >
                      <span className="inline-flex items-center gap-2">
                        <Trash2 className="h-4 w-4" />
                        Delete
                      </span>
                    </button>
                  </div>
                </div>

                <div className="mt-5 grid gap-3 md:grid-cols-[0.9fr_0.4fr]">
                  <select
                    value={selectedEvent(node.node_id)}
                    onChange={(event) =>
                      setEventSelections((current) => ({
                        ...current,
                        [node.node_id]: event.target.value,
                      }))
                    }
                    className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
                  >
                    {EVENT_OPTIONS.map((eventType) => (
                      <option key={eventType} value={eventType}>
                        {eventType.replaceAll('_', ' ')}
                      </option>
                    ))}
                  </select>

                  <button
                    onClick={() =>
                      runAction(
                        () =>
                          session.request(`/injection/nodes/${node.node_id}/emit`, {
                            method: 'POST',
                            body: {
                              event_type: selectedEvent(node.node_id),
                              payload: {},
                            },
                          }),
                        `Emitted ${selectedEvent(node.node_id)} for ${node.draft_reference}.`
                      )
                    }
                    className="inline-flex items-center justify-center gap-2 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-300"
                  >
                    <Send className="h-4 w-4" />
                    Emit
                  </button>
                </div>

                <div className="mt-4 grid gap-2 sm:grid-cols-3">
                  {['blockage', 'overflow', 'leak'].map((eventType) => (
                    <button
                      key={eventType}
                      onClick={() =>
                        runAction(
                          () =>
                            session.request(`/injection/nodes/${node.node_id}/emit`, {
                              method: 'POST',
                              body: { event_type: eventType, payload: {} },
                            }),
                          `Injected ${eventType} for ${node.draft_reference}.`
                        )
                      }
                      className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white hover:bg-white/10"
                    >
                      Quick {eventType}
                    </button>
                  ))}
                </div>
              </div>
            ))}

            {!Array.isArray(nodes.data) || nodes.data.length === 0 ? (
              <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-6 text-sm text-slate-400">
                No draft nodes staged yet.
              </div>
            ) : null}
          </div>
        </SectionCard>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-3">
        <SectionCard
          icon={TestTube2}
          title="Realistic Payload Model"
          subtitle="Event generation remains aligned to the current backend contracts."
        >
          <div className="space-y-3 text-sm leading-7 text-slate-300">
            <p>`blockage` and `overflow` use ultrasonic or IR semantics with room-linked telemetry.</p>
            <p>`door_open` and `door_prolonged_open` map to the magnetic door contact contract.</p>
            <p>`leak` maps to the floor liquid sensor and remains urgent for cleaning response.</p>
            <p>`motion`, `garbage_left`, and `misuse` emit AI-like room events without creating live hardware records.</p>
          </div>
        </SectionCard>

        <SectionCard
          icon={ShieldCheck}
          title="Approval Boundary"
          subtitle="Drafts stay isolated until the admin portal activates them."
        >
          <div className="space-y-3 text-sm leading-7 text-slate-300">
            <p>This injection surface never assigns the final ESP32 device ID.</p>
            <p>Submitting for approval moves the draft into the admin queue for official node-ID generation and room activation.</p>
            <p>The live device registry only changes after an admin approval action.</p>
          </div>
        </SectionCard>

        <SectionCard
          icon={PlayCircle}
          title="Operational Safety"
          subtitle="Testing stays manual by default, with optional per-node automation."
        >
          <div className="space-y-3 text-sm leading-7 text-slate-300">
            <p>Each draft node can be paused or resumed independently.</p>
            <p>Per-node auto mode is optional and isolated to the specific draft.</p>
            <p>The main monitoring website stays free of draft creation controls and test-only forms.</p>
          </div>
        </SectionCard>
      </div>
    </PortalShell>
  );
}
