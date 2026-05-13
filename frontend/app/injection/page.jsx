'use client';

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  Bot,
  Cpu,
  PlayCircle,
  Send,
  SquareTerminal,
  TestTube2,
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

export default function InjectionPage() {
  const session = usePortalSession(['system_admin', 'facility_admin']);
  const [statusMessage, setStatusMessage] = useState('');
  const [nodeForm, setNodeForm] = useState({
    node_id: '',
    label: '',
    room_code: '',
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
        subtitle="Internal test surface for simulated ESP32 node creation, room assignment, realistic sensor emission, and registration into the live monitoring system."
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
      subtitle="Internal test website for staged node creation, realistic telemetry emission, and room-linked registration."
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
          title="Create Simulation Node"
          subtitle="Assign a unique node ID, room, and sensor set without touching live device inventory."
        >
          <div className="grid gap-3">
            <TextInput
              value={nodeForm.node_id}
              onChange={(value) => setNodeForm((current) => ({ ...current, node_id: value }))}
              placeholder="Node ID"
            />
            <TextInput
              value={nodeForm.label}
              onChange={(value) => setNodeForm((current) => ({ ...current, label: value }))}
              placeholder="Display label"
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
                `Created simulation node ${nodeForm.node_id}.`
              )
            }
            className="mt-5 inline-flex items-center gap-2 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-300"
          >
            <Cpu className="h-4 w-4" />
            Create Node
          </button>
        </SectionCard>

        <SectionCard
          icon={SquareTerminal}
          title="Node Actions"
          subtitle="Register nodes into the main system and emit realistic test payloads."
        >
          <div className="space-y-4">
            {(Array.isArray(nodes.data) ? nodes.data : []).map((node) => (
              <div key={node.node_id} className="rounded-3xl border border-white/10 bg-white/5 p-5">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="text-lg font-semibold text-white">{node.node_id}</div>
                    <div className="mt-1 text-sm text-slate-400">
                      {node.label} | {node.room_code || 'Unassigned room'} | {node.status}
                    </div>
                    <div className="mt-3 flex flex-wrap gap-2">
                      {(node.sensor_types || []).map((sensor) => (
                        <span
                          key={sensor}
                          className="rounded-full border border-white/10 px-2.5 py-1 text-[11px] uppercase tracking-[0.14em] text-slate-200"
                        >
                          {sensor}
                        </span>
                      ))}
                    </div>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <button
                      onClick={() =>
                        runAction(
                          () =>
                            session.request(`/injection/nodes/${node.node_id}/register`, {
                              method: 'POST',
                              body: { room_code: node.room_code },
                            }),
                          `Registered ${node.node_id} into the main system.`
                        )
                      }
                      className="rounded-2xl border border-emerald-400/20 bg-emerald-500/10 px-4 py-2 text-sm text-emerald-100 hover:bg-emerald-500/15"
                    >
                      Register By Node ID
                    </button>
                    <button
                      onClick={() =>
                        runAction(
                          () => session.request(`/injection/nodes/${node.node_id}`, { method: 'DELETE' }),
                          `Deleted simulation node ${node.node_id}.`
                        )
                      }
                      className="rounded-2xl border border-rose-400/20 bg-rose-500/10 px-4 py-2 text-sm text-rose-100 hover:bg-rose-500/15"
                    >
                      Delete
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
                        `Emitted ${selectedEvent(node.node_id)} for ${node.node_id}.`
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
                          `Injected ${eventType} for ${node.node_id}.`
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
                No simulation nodes staged yet.
              </div>
            ) : null}
          </div>
        </SectionCard>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-3">
        <SectionCard
          icon={TestTube2}
          title="Realistic Payload Model"
          subtitle="Event generation stays aligned to current backend contracts."
        >
          <div className="space-y-3 text-sm leading-7 text-slate-300">
            <p>`blockage` and `overflow` use ultrasonic or IR semantics with room-linked telemetry.</p>
            <p>`door_open` and `door_prolonged_open` map to the magnetic door contact contract.</p>
            <p>`leak` maps to the floor liquid sensor and is treated as urgent.</p>
            <p>`motion`, `garbage_left`, and `misuse` emit AI-like room events.</p>
          </div>
        </SectionCard>

        <SectionCard
          icon={PlayCircle}
          title="Main-System Registration"
          subtitle="Nodes created here can be registered into the operational system by node ID."
        >
          <div className="space-y-3 text-sm leading-7 text-slate-300">
            <p>Registration creates or updates a room-linked device record using the simulation node ID as the device ID.</p>
            <p>The main monitoring website will then resolve the node through the existing `/devices`, `/rooms`, and alert flows without contract changes.</p>
          </div>
        </SectionCard>

        <SectionCard
          icon={SquareTerminal}
          title="Safety Boundary"
          subtitle="Test tooling is isolated from the control-room dashboard."
        >
          <div className="space-y-3 text-sm leading-7 text-slate-300">
            <p>Simulation node records are stored separately from the live device registry until explicitly registered.</p>
            <p>This surface never exposes user management or admin account controls.</p>
            <p>Operational monitoring remains in the main website without form clutter.</p>
          </div>
        </SectionCard>
      </div>
    </PortalShell>
  );
}
