// Énumérations partagées du domaine NJUKA.

enum UserRole {
  citizen,
  operator,
  admin;

  static UserRole fromName(String? value) => UserRole.values.firstWhere(
        (e) => e.name == value,
        orElse: () => UserRole.citizen,
      );
}

enum AccountStatus {
  active,
  disabled;

  static AccountStatus fromName(String? value) =>
      AccountStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AccountStatus.active,
      );
}

enum OutageStatus {
  ongoing,
  resolved;

  static OutageStatus fromName(String? value) =>
      OutageStatus.values.firstWhere(
        (e) => e.name == value,
        orElse: () => OutageStatus.ongoing,
      );
}

enum OutageCause {
  unknown,
  unplanned,
  scheduled,
  incident;

  static OutageCause fromName(String? value) =>
      OutageCause.values.firstWhere(
        (e) => e.name == value,
        orElse: () => OutageCause.unknown,
      );
}

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
        UserRole.citizen => 'Citoyen',
        UserRole.operator => 'Opérateur',
        UserRole.admin => 'Administrateur',
      };
}

extension OutageStatusLabel on OutageStatus {
  String get label =>
      this == OutageStatus.ongoing ? 'En cours' : 'Rétabli';
}

extension OutageCauseLabel on OutageCause {
  String get label => switch (this) {
        OutageCause.unknown => 'Cause inconnue',
        OutageCause.unplanned => 'Coupure inopinée',
        OutageCause.scheduled => 'Coupure programmée',
        OutageCause.incident => 'Incident',
      };
}
