const _simulationRoles = {'system_admin', 'facility_admin'};
const _acknowledgeRoles = {
  'system_admin',
  'facility_admin',
  'control_room_operator',
  'maintenance_staff',
  'cleaning_staff',
};

class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  final int id;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      email: json['email'].toString(),
      fullName: (json['full_name'] ?? '').toString(),
      role: (json['role'] ?? 'viewer').toString(),
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  String get roleLabel {
    switch (role) {
      case 'system_admin':
        return 'System Admin';
      case 'facility_admin':
        return 'Facility Admin';
      case 'control_room_operator':
        return 'Control Room Operator';
      case 'maintenance_staff':
        return 'Maintenance Staff';
      case 'cleaning_staff':
        return 'Cleaning Staff';
      default:
        return 'Viewer';
    }
  }

  bool get canUseSimulation => _simulationRoles.contains(role);

  bool get canAcknowledgeAlerts => _acknowledgeRoles.contains(role);

  bool get readOnly => !canAcknowledgeAlerts && !canUseSimulation;
}
