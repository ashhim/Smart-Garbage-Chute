'use client';

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  AlertTriangle,
  Building2,
  Cpu,
  FileClock,
  Radio,
  ShieldCheck,
  UserCog,
  Wrench,
} from 'lucide-react';

import { AuthForm } from '../components/auth-form';
import {
  AccessDeniedScreen,
  LoadingScreen,
  PortalShell,
} from '../components/portal-shell';
import { usePortalSession } from '../components/session';
import { apiUrl } from '../lib/config';

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

function Table({ columns, rows, emptyLabel = 'No records found.' }) {
  if (!rows.length) {
    return (
      <div className="rounded-2xl border border-dashed border-white/10 bg-white/5 p-6 text-sm text-slate-400">
        {emptyLabel}
      </div>
    );
  }

  return (
    <div className="overflow-hidden rounded-2xl border border-white/10">
      <div className="overflow-auto">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-white/5 text-xs uppercase tracking-[0.18em] text-slate-400">
            <tr>
              {columns.map((column) => (
                <th key={column.key} className="px-4 py-3 font-medium">
                  {column.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, rowIndex) => (
              <tr key={row.key || row.id || rowIndex} className="border-t border-white/10 text-slate-200">
                {columns.map((column) => (
                  <td key={column.key} className="px-4 py-3 align-top">
                    {column.render ? column.render(row) : row[column.key]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function TextInput({ value, onChange, placeholder, type = 'text' }) {
  return (
    <input
      type={type}
      value={value}
      onChange={(event) => onChange(event.target.value)}
      placeholder={placeholder}
      className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
    />
  );
}

function SelectInput({ value, onChange, options }) {
  return (
    <select
      value={value}
      onChange={(event) => onChange(event.target.value)}
      className="w-full rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white outline-none transition focus:border-cyan-400/40"
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  );
}

export default function AdminPage() {
  const session = usePortalSession(['system_admin']);
  const [statusMessage, setStatusMessage] = useState('');

  const [userForm, setUserForm] = useState({
    email: '',
    full_name: '',
    password: 'Admin@12345',
    role: 'viewer',
  });
  const [buildingForm, setBuildingForm] = useState({ code: '', name: '' });
  const [floorForm, setFloorForm] = useState({ building_id: '', level: '1', name: '' });
  const [roomForm, setRoomForm] = useState({
    floor_id: '',
    room_code: '',
    name: '',
    zone: 'chute-room',
  });
  const [deviceForm, setDeviceForm] = useState({
    room_id: '',
    device_id: '',
    device_type: 'esp32-s3-poe',
    firmware_version: '1.2.1',
  });
  const [firmwareForm, setFirmwareForm] = useState({
    version: '',
    build_sha: '',
    artifact_url: '',
    notes: '',
  });
  const [otaForm, setOtaForm] = useState({
    target_type: 'room',
    target_ref: '',
    firmware_version: '1.2.1',
  });

  const swrOptions = { refreshInterval: 8000 };
  const roles = useSWR(session.token ? apiUrl('/admin/roles') : null, session.fetcher, swrOptions);
  const users = useSWR(session.token ? apiUrl('/admin/users') : null, session.fetcher, swrOptions);
  const buildings = useSWR(session.token ? apiUrl('/buildings') : null, session.fetcher, swrOptions);
  const floors = useSWR(session.token ? apiUrl('/floors') : null, session.fetcher, swrOptions);
  const rooms = useSWR(session.token ? apiUrl('/rooms') : null, session.fetcher, swrOptions);
  const devices = useSWR(session.token ? apiUrl('/devices') : null, session.fetcher, swrOptions);
  const firmware = useSWR(session.token ? apiUrl('/admin/firmware') : null, session.fetcher, swrOptions);
  const otaJobs = useSWR(session.token ? apiUrl('/ota/jobs') : null, session.fetcher, swrOptions);
  const alerts = useSWR(session.token ? apiUrl('/alerts') : null, session.fetcher, swrOptions);
  const auditLogs = useSWR(session.token ? apiUrl('/admin/audit-logs') : null, session.fetcher, swrOptions);

  const roleOptions = useMemo(
    () => (Array.isArray(roles.data) ? roles.data : []).map((role) => ({ value: role.value, label: role.label })),
    [roles.data]
  );
  const buildingOptions = useMemo(
    () =>
      (Array.isArray(buildings.data) ? buildings.data : []).map((building) => ({
        value: String(building.id),
        label: `${building.code} - ${building.name}`,
      })),
    [buildings.data]
  );
  const floorOptions = useMemo(
    () =>
      (Array.isArray(floors.data) ? floors.data : []).map((floor) => ({
        value: String(floor.id),
        label: `Floor ${floor.level} - ${floor.name}`,
      })),
    [floors.data]
  );
  const roomOptions = useMemo(
    () =>
      (Array.isArray(rooms.data) ? rooms.data : []).map((room) => ({
        value: String(room.id),
        label: `${room.room_code} - ${room.name}`,
      })),
    [rooms.data]
  );
  const firmwareOptions = useMemo(
    () =>
      (Array.isArray(firmware.data) ? firmware.data : []).map((item) => ({
        value: item.version,
        label: `${item.version}${item.is_active ? ' (active)' : ''}`,
      })),
    [firmware.data]
  );

  const refreshAll = () =>
    Promise.all([
      users.mutate(),
      buildings.mutate(),
      floors.mutate(),
      rooms.mutate(),
      devices.mutate(),
      firmware.mutate(),
      otaJobs.mutate(),
      alerts.mutate(),
      auditLogs.mutate(),
    ]);

  async function runAction(action, successMessage) {
    try {
      await action();
      setStatusMessage(successMessage);
      await refreshAll();
    } catch (error) {
      console.error(error);
      setStatusMessage(error.message || 'Action failed.');
    }
  }

  if (session.loading) {
    return <LoadingScreen label="Loading admin website..." />;
  }

  if (!session.token) {
    return (
      <AuthForm
        title="Admin Website"
        subtitle="System-administrator portal for user accounts, role assignment, facilities, device registration, firmware, OTA, alerts, and audit history."
        helper="Only the seeded system administrator can access this surface."
        authError={session.authError}
        onLogin={session.login}
        accent="amber"
      />
    );
  }

  if (!session.authorized) {
    return <AccessDeniedScreen role={session.user?.role} onLogout={session.logout} />;
  }

  return (
    <PortalShell
      title="Smart Garbage Chute Administration"
      subtitle="Highest-privilege surface for enterprise administration and lifecycle control."
      section="Admin Website"
      currentPath="/admin"
      session={session}
    >
      {statusMessage ? (
        <div className="mb-6 rounded-2xl border border-cyan-400/20 bg-cyan-500/10 px-4 py-3 text-sm text-cyan-100">
          {statusMessage}
        </div>
      ) : null}

      <div className="grid gap-6 xl:grid-cols-2">
        <SectionCard
          icon={UserCog}
          title="Accounts And Roles"
          subtitle="Create accounts, assign roles, and control user access."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <TextInput value={userForm.email} onChange={(value) => setUserForm((current) => ({ ...current, email: value }))} placeholder="Email" />
            <TextInput value={userForm.full_name} onChange={(value) => setUserForm((current) => ({ ...current, full_name: value }))} placeholder="Full name" />
            <TextInput value={userForm.password} onChange={(value) => setUserForm((current) => ({ ...current, password: value }))} placeholder="Password" type="password" />
            <SelectInput value={userForm.role} onChange={(value) => setUserForm((current) => ({ ...current, role: value }))} options={roleOptions} />
          </div>
          <button
            onClick={() =>
              runAction(
                () => session.request('/admin/users', { method: 'POST', body: userForm }),
                `Created user ${userForm.email}.`
              )
            }
            className="mt-4 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-300"
          >
            Create Account
          </button>

          <div className="mt-5">
            <Table
              columns={[
                { key: 'email', label: 'Email' },
                { key: 'full_name', label: 'Full Name' },
                {
                  key: 'role',
                  label: 'Role',
                  render: (row) => (
                    <select
                      value={row.role}
                      onChange={(event) =>
                        runAction(
                          () =>
                            session.request(`/admin/users/${row.id}`, {
                              method: 'PATCH',
                              body: { role: event.target.value },
                            }),
                          `Updated role for ${row.email}.`
                        )
                      }
                      className="rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-white"
                    >
                      {roleOptions.map((role) => (
                        <option key={role.value} value={role.value}>
                          {role.label}
                        </option>
                      ))}
                    </select>
                  ),
                },
                {
                  key: 'actions',
                  label: 'Actions',
                  render: (row) => (
                    <button
                      onClick={() =>
                        runAction(
                          () => session.request(`/admin/users/${row.id}`, { method: 'DELETE' }),
                          `Deleted user ${row.email}.`
                        )
                      }
                      className="rounded-xl border border-rose-400/20 bg-rose-500/10 px-3 py-2 text-xs uppercase tracking-[0.14em] text-rose-100"
                    >
                      Delete
                    </button>
                  ),
                },
              ]}
              rows={Array.isArray(users.data) ? users.data : []}
            />
          </div>
        </SectionCard>

        <SectionCard
          icon={Building2}
          title="Facility Registry"
          subtitle="Manage buildings, floors, rooms, and registered ESP32 nodes."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <TextInput value={buildingForm.code} onChange={(value) => setBuildingForm((current) => ({ ...current, code: value }))} placeholder="Building code" />
            <TextInput value={buildingForm.name} onChange={(value) => setBuildingForm((current) => ({ ...current, name: value }))} placeholder="Building name" />
          </div>
          <button
            onClick={() =>
              runAction(
                () => session.request('/buildings', { method: 'POST', body: buildingForm }),
                `Created building ${buildingForm.code}.`
              )
            }
            className="mt-4 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white hover:bg-white/10"
          >
            Add Building
          </button>

          <div className="mt-4 grid gap-3 md:grid-cols-3">
            <SelectInput value={floorForm.building_id} onChange={(value) => setFloorForm((current) => ({ ...current, building_id: value }))} options={buildingOptions} />
            <TextInput value={floorForm.level} onChange={(value) => setFloorForm((current) => ({ ...current, level: value }))} placeholder="Level" type="number" />
            <TextInput value={floorForm.name} onChange={(value) => setFloorForm((current) => ({ ...current, name: value }))} placeholder="Floor name" />
          </div>
          <button
            onClick={() =>
              runAction(
                () =>
                  session.request('/floors', {
                    method: 'POST',
                    body: {
                      building_id: Number(floorForm.building_id),
                      level: Number(floorForm.level),
                      name: floorForm.name,
                    },
                  }),
                `Created floor ${floorForm.name || floorForm.level}.`
              )
            }
            className="mt-4 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white hover:bg-white/10"
          >
            Add Floor
          </button>

          <div className="mt-4 grid gap-3 md:grid-cols-2">
            <SelectInput value={roomForm.floor_id} onChange={(value) => setRoomForm((current) => ({ ...current, floor_id: value }))} options={floorOptions} />
            <TextInput value={roomForm.room_code} onChange={(value) => setRoomForm((current) => ({ ...current, room_code: value }))} placeholder="Room code" />
            <TextInput value={roomForm.name} onChange={(value) => setRoomForm((current) => ({ ...current, name: value }))} placeholder="Room name" />
            <TextInput value={roomForm.zone} onChange={(value) => setRoomForm((current) => ({ ...current, zone: value }))} placeholder="Zone" />
          </div>
          <button
            onClick={() =>
              runAction(
                () =>
                  session.request('/rooms', {
                    method: 'POST',
                    body: {
                      floor_id: Number(roomForm.floor_id),
                      room_code: roomForm.room_code,
                      name: roomForm.name,
                      zone: roomForm.zone,
                    },
                  }),
                `Created room ${roomForm.room_code}.`
              )
            }
            className="mt-4 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white hover:bg-white/10"
          >
            Add Room
          </button>

          <div className="mt-4 grid gap-3 md:grid-cols-2">
            <SelectInput value={deviceForm.room_id} onChange={(value) => setDeviceForm((current) => ({ ...current, room_id: value }))} options={roomOptions} />
            <TextInput value={deviceForm.device_id} onChange={(value) => setDeviceForm((current) => ({ ...current, device_id: value }))} placeholder="Node ID" />
            <TextInput value={deviceForm.device_type} onChange={(value) => setDeviceForm((current) => ({ ...current, device_type: value }))} placeholder="Device type" />
            <SelectInput value={deviceForm.firmware_version} onChange={(value) => setDeviceForm((current) => ({ ...current, firmware_version: value }))} options={firmwareOptions.length ? firmwareOptions : [{ value: '1.2.1', label: '1.2.1' }]} />
          </div>
          <button
            onClick={() =>
              runAction(
                () =>
                  session.request('/devices', {
                    method: 'POST',
                    body: {
                      room_id: Number(deviceForm.room_id),
                      device_id: deviceForm.device_id,
                      device_type: deviceForm.device_type,
                      firmware_version: deviceForm.firmware_version,
                    },
                  }),
                `Registered node ${deviceForm.device_id}.`
              )
            }
            className="mt-4 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-300"
          >
            Register ESP32 Node
          </button>
        </SectionCard>

        <SectionCard
          icon={Radio}
          title="Firmware And OTA"
          subtitle="Manage firmware releases and trigger OTA jobs by scope."
        >
          <div className="grid gap-3 md:grid-cols-2">
            <TextInput value={firmwareForm.version} onChange={(value) => setFirmwareForm((current) => ({ ...current, version: value }))} placeholder="Version" />
            <TextInput value={firmwareForm.build_sha} onChange={(value) => setFirmwareForm((current) => ({ ...current, build_sha: value }))} placeholder="Build SHA" />
            <TextInput value={firmwareForm.artifact_url} onChange={(value) => setFirmwareForm((current) => ({ ...current, artifact_url: value }))} placeholder="Artifact URL" />
            <TextInput value={firmwareForm.notes} onChange={(value) => setFirmwareForm((current) => ({ ...current, notes: value }))} placeholder="Notes" />
          </div>
          <button
            onClick={() =>
              runAction(
                () => session.request('/admin/firmware', { method: 'POST', body: firmwareForm }),
                `Created firmware ${firmwareForm.version}.`
              )
            }
            className="mt-4 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white hover:bg-white/10"
          >
            Add Firmware
          </button>

          <div className="mt-5">
            <Table
              columns={[
                { key: 'version', label: 'Version' },
                { key: 'build_sha', label: 'Build SHA' },
                { key: 'artifact_url', label: 'Artifact URL' },
                {
                  key: 'actions',
                  label: 'Actions',
                  render: (row) => (
                    <div className="flex gap-2">
                      <button
                        onClick={() =>
                          runAction(
                            () => session.request(`/admin/firmware/${row.id}/activate`, { method: 'POST' }),
                            `Activated firmware ${row.version}.`
                          )
                        }
                        className="rounded-xl border border-emerald-400/20 bg-emerald-500/10 px-3 py-2 text-xs uppercase tracking-[0.14em] text-emerald-100"
                      >
                        {row.is_active ? 'Active' : 'Activate'}
                      </button>
                    </div>
                  ),
                },
              ]}
              rows={Array.isArray(firmware.data) ? firmware.data : []}
            />
          </div>

          <div className="mt-5 grid gap-3 md:grid-cols-3">
            <SelectInput
              value={otaForm.target_type}
              onChange={(value) => setOtaForm((current) => ({ ...current, target_type: value }))}
              options={[
                { value: 'device', label: 'One Node' },
                { value: 'room', label: 'One Room' },
                { value: 'floor', label: 'One Floor' },
                { value: 'building', label: 'One Building' },
                { value: 'all', label: 'All Devices' },
              ]}
            />
            <TextInput value={otaForm.target_ref} onChange={(value) => setOtaForm((current) => ({ ...current, target_ref: value }))} placeholder="Target ref" />
            <SelectInput value={otaForm.firmware_version} onChange={(value) => setOtaForm((current) => ({ ...current, firmware_version: value }))} options={firmwareOptions.length ? firmwareOptions : [{ value: '1.2.1', label: '1.2.1' }]} />
          </div>
          <button
            onClick={() =>
              runAction(
                () => session.request('/ota/jobs', { method: 'POST', body: otaForm }),
                `Queued OTA for ${otaForm.target_type}:${otaForm.target_ref || 'all'}.`
              )
            }
            className="mt-4 rounded-2xl bg-cyan-400 px-4 py-3 text-sm font-semibold text-slate-950 hover:bg-cyan-300"
          >
            Trigger OTA Job
          </button>
        </SectionCard>

        <SectionCard
          icon={FileClock}
          title="Alerts And Audit"
          subtitle="Review active alerts, OTA history, and administrative activity."
        >
          <div className="grid gap-4">
            <Table
              columns={[
                { key: 'created_at', label: 'Time', render: (row) => row.created_at?.replace('T', ' ').slice(0, 19) || '--' },
                { key: 'room_code', label: 'Room' },
                { key: 'severity', label: 'Severity' },
                { key: 'message', label: 'Message' },
              ]}
              rows={Array.isArray(alerts.data) ? alerts.data.slice(0, 8) : []}
              emptyLabel="No active alerts."
            />

            <Table
              columns={[
                { key: 'target_type', label: 'Target Type' },
                { key: 'target_ref', label: 'Target Ref' },
                { key: 'firmware_version', label: 'Firmware' },
                { key: 'status', label: 'Status' },
                { key: 'requested_by', label: 'Requested By' },
              ]}
              rows={Array.isArray(otaJobs.data) ? otaJobs.data.slice(0, 8) : []}
              emptyLabel="No OTA jobs recorded."
            />

            <Table
              columns={[
                { key: 'created_at', label: 'Time', render: (row) => row.created_at?.replace('T', ' ').slice(0, 19) || '--' },
                { key: 'actor', label: 'Actor' },
                { key: 'action', label: 'Action' },
                { key: 'entity_type', label: 'Entity' },
                { key: 'entity_id', label: 'Entity ID' },
              ]}
              rows={Array.isArray(auditLogs.data) ? auditLogs.data.slice(0, 12) : []}
              emptyLabel="No audit history yet."
            />
          </div>
        </SectionCard>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-2">
        <SectionCard
          icon={Cpu}
          title="Registered Nodes"
          subtitle="Current room-linked ESP32 device inventory."
        >
          <Table
            columns={[
              { key: 'device_id', label: 'Node ID' },
              { key: 'room_code', label: 'Room' },
              { key: 'firmware_version', label: 'Firmware' },
              { key: 'status', label: 'Status' },
              {
                key: 'actions',
                label: 'Actions',
                render: (row) => (
                  <button
                    onClick={() =>
                      runAction(
                        () => session.request(`/devices/${row.id}`, { method: 'DELETE' }),
                        `Deleted node ${row.device_id}.`
                      )
                    }
                    className="rounded-xl border border-rose-400/20 bg-rose-500/10 px-3 py-2 text-xs uppercase tracking-[0.14em] text-rose-100"
                  >
                    Delete
                  </button>
                ),
              },
            ]}
            rows={Array.isArray(devices.data) ? devices.data.slice(0, 20) : []}
          />
        </SectionCard>

        <SectionCard
          icon={Wrench}
          title="Facility Structure"
          subtitle="Current building, floor, and room inventory."
        >
          <div className="grid gap-4">
            <Table
              columns={[
                { key: 'code', label: 'Building Code' },
                { key: 'name', label: 'Name' },
              ]}
              rows={Array.isArray(buildings.data) ? buildings.data : []}
              emptyLabel="No buildings."
            />
            <Table
              columns={[
                { key: 'building_id', label: 'Building ID' },
                { key: 'level', label: 'Level' },
                { key: 'name', label: 'Name' },
              ]}
              rows={Array.isArray(floors.data) ? floors.data : []}
              emptyLabel="No floors."
            />
            <Table
              columns={[
                { key: 'room_code', label: 'Room Code' },
                { key: 'name', label: 'Name' },
                { key: 'building_code', label: 'Building' },
                { key: 'floor_level', label: 'Floor' },
                { key: 'open_alert_count', label: 'Open Alerts' },
              ]}
              rows={Array.isArray(rooms.data) ? rooms.data.slice(0, 20) : []}
              emptyLabel="No rooms."
            />
          </div>
        </SectionCard>
      </div>
    </PortalShell>
  );
}
