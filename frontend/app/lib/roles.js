export const ROLE_LABELS = {
  system_admin: 'System Admin',
  facility_admin: 'Facility Admin',
  control_room_operator: 'Control Room Operator',
  maintenance_staff: 'Maintenance Staff',
  cleaning_staff: 'Cleaning Staff',
  viewer: 'Viewer',
};

export const ACKNOWLEDGE_ROLES = new Set([
  'system_admin',
  'facility_admin',
  'control_room_operator',
  'maintenance_staff',
  'cleaning_staff',
]);

export const SIMULATION_ROLES = new Set(['system_admin', 'facility_admin']);
export const ADMIN_PORTAL_ROLES = new Set(['system_admin', 'facility_admin']);
export const SYSTEM_ADMIN_ROLES = new Set(['system_admin']);

export function roleLabel(role) {
  return ROLE_LABELS[role] || role || 'User';
}
