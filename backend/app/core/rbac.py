SYSTEM_ADMIN = "system_admin"
FACILITY_ADMIN = "facility_admin"
CONTROL_ROOM_OPERATOR = "control_room_operator"
MAINTENANCE_STAFF = "maintenance_staff"
CLEANING_STAFF = "cleaning_staff"
VIEWER = "viewer"

ROLE_LABELS = {
    SYSTEM_ADMIN: "System Admin",
    FACILITY_ADMIN: "Facility Admin",
    CONTROL_ROOM_OPERATOR: "Control Room Operator",
    MAINTENANCE_STAFF: "Maintenance Staff",
    CLEANING_STAFF: "Cleaning Staff",
    VIEWER: "Viewer",
}

LEGACY_ROLE_ALIASES = {
    "admin": SYSTEM_ADMIN,
    "administrator": SYSTEM_ADMIN,
    "operator": CONTROL_ROOM_OPERATOR,
    "maintenance": MAINTENANCE_STAFF,
    "cleaning": CLEANING_STAFF,
}

ALL_ROLES = tuple(ROLE_LABELS.keys())
ROLE_SET = set(ALL_ROLES)

MONITORING_ROLES = ROLE_SET
FACILITY_MANAGEMENT_ROLES = {
    SYSTEM_ADMIN,
    FACILITY_ADMIN,
}
ALERT_ACK_ROLES = {
    SYSTEM_ADMIN,
    FACILITY_ADMIN,
    CONTROL_ROOM_OPERATOR,
    MAINTENANCE_STAFF,
    CLEANING_STAFF,
}
SIMULATION_ROLES = {
    SYSTEM_ADMIN,
    FACILITY_ADMIN,
}
SYSTEM_ADMIN_ROLES = {SYSTEM_ADMIN}


def normalize_role(role: str | None) -> str:
    if not role:
        return VIEWER

    normalized = str(role).strip().lower()
    return LEGACY_ROLE_ALIASES.get(normalized, normalized)


def is_known_role(role: str | None) -> bool:
    return normalize_role(role) in ROLE_SET

