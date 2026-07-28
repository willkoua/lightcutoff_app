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

  static AccountStatus fromName(String? value) => AccountStatus.values
      .firstWhere((e) => e.name == value, orElse: () => AccountStatus.active);
}

enum OutageStatus {
  ongoing,
  resolved;

  static OutageStatus fromName(String? value) => OutageStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => OutageStatus.ongoing,
  );
}

/// Type de coupure. Seules deux catégories existent : les coupures
/// **programmées** (annoncées à l'avance, alimentées par les opérateurs) et les
/// coupures **imprévues**. Tout signalement saisi par un utilisateur est
/// imprévu par défaut.
enum OutageType {
  unplanned,
  scheduled;

  static OutageType fromName(String? value) => OutageType.values.firstWhere(
    (e) => e.name == value,
    // Valeur inconnue ou absente (anciens docs, signalements citoyens) →
    // imprévue.
    orElse: () => OutageType.unplanned,
  );
}

/// Service public concerné par le signalement. Introduit avec le pivot
/// multi-service (étape 3 — 2026-06-24). Tous les reports antérieurs à cette
/// étape n'ont pas le champ → défaut [electricity] pour rester rétro-compat.
enum ServiceType {
  electricity,
  water;

  static ServiceType fromName(String? value) => ServiceType.values.firstWhere(
    (e) => e.name == value,
    // Champ absent (legacy) ou valeur inconnue → électricité (le seul
    // service avant l'ouverture eau).
    orElse: () => ServiceType.electricity,
  );
}

/// Provenance de la position d'un signalement : vécue (GPS) ou **décrite**
/// (géocodée depuis un texte — précision quartier/ville au mieux). Sert à
/// mesurer/pondérer la fiabilité (2026-07-28) ; nourrira aussi la décision du
/// modèle de localisation du bot WhatsApp.
enum PositionSource {
  gps,
  described;

  static PositionSource fromName(String? value) =>
      PositionSource.values.firstWhere(
        (e) => e.name == value,
        // Champ absent (legacy) → gps (seule source avant 2026-06-29).
        orElse: () => PositionSource.gps,
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
  String get label => this == OutageStatus.ongoing ? 'En cours' : 'Rétabli';
}

extension OutageTypeLabel on OutageType {
  String get label => switch (this) {
    OutageType.unplanned => 'Coupure imprévue',
    OutageType.scheduled => 'Coupure programmée',
  };
}
