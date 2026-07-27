/// Constantes métier centralisées : rayons de proximité, limites des médias,
/// limites de saisie. Regroupées ici pour rester cohérentes entre l'UI, les
/// providers et les utilitaires (source unique de vérité).
///
/// Note : la limite de taille média est aussi appliquée côté serveur dans
/// `storage.rules` — garder les deux valeurs synchronisées.
class AppConstants {
  AppConstants._();

  // --- Proximité (mètres) ---

  /// Rayon en-deçà duquel deux coupures sont considérées identiques
  /// (détection de doublon lors d'un nouveau signalement).
  static const double duplicateRadiusMeters = 500;

  /// Rayon du filtre « à proximité » appliqué à la liste et à la carte.
  static const double nearbyFilterRadiusMeters = 5000;

  /// Intervalle de rafraîchissement auto des coupures « à proximité ».
  /// (Cette requête est ponctuelle, contrairement au flux principal qui est
  /// déjà temps réel.)
  static const Duration nearRefreshInterval = Duration(seconds: 60);

  /// Rayon (m) du **prompt d'ouverture** « Chez toi aussi ? » : on ne sollicite
  /// l'utilisateur que si une coupure en cours est à moins de cette distance.
  static const double promptRadiusMeters = 1000;

  // --- Médias des signalements ---

  /// Côté le plus long (px) au-delà duquel une image fixe est redimensionnée.
  static const int maxMediaDimension = 1280;

  /// Taille maximale d'un média uploadé (octets). Doit rester ≤ la règle
  /// Storage (`storage.rules`).
  static const int maxMediaBytes = 8 * 1024 * 1024;

  /// Qualité JPEG de ré-encodage après redimensionnement (0–100).
  static const int mediaJpegQuality = 85;

  // --- Saisie ---

  /// Longueur maximale de la description d'un signalement (caractères).
  static const int maxDescriptionLength = 500;

  // --- Liste / pagination ---

  /// Nombre de coupures chargées par lot (scroll infini de la liste).
  static const int reportsPageSize = 20;

  // --- Notifications push ---

  /// Rayon (m) d'alerte : un device est notifié si la coupure tombe dedans.
  static const double notifyRadiusMeters = 2000;

  /// Précision du geohash pour le ciblage de proximité (6 ≈ cellule ~1,2 km).
  static const int geohashPrecision = 6;

  /// Identifiant du channel Android pour les notifications de coupure.
  /// Doit correspondre au `channel_id` envoyé par la Cloud Function (Phase 4).
  static const String fcmOutageChannelId = 'njuka_outage_alerts';

  /// Libellé du channel (visible dans Paramètres → Notifications).
  static const String fcmOutageChannelName = 'Alertes de coupure';

  /// Description du channel.
  static const String fcmOutageChannelDescription =
      'Notifications de coupures signalées près de chez vous.';

  // --- Résolution crowd-sourcée ---

  /// Nombre minimum de déclarations « courant revenu » avant de pouvoir
  /// passer une coupure en `resolved` automatiquement. Plancher pour éviter
  /// qu'une seule personne ferme une vraie coupure.
  static const int restorationMinVotes = 3;

  /// Ratio (rapporté à [Report.confirmationCount]) à atteindre en plus du
  /// plancher pour déclencher l'auto-résolution. Ex. 0.5 = il faut au moins
  /// la moitié des confirmants pour fermer la coupure.
  static const double restorationRatio = 0.5;

  // --- Archivage ---

  /// Durée (jours) pendant laquelle un report archivé reste en base avant
  /// purge définitive par le cron `purgeArchivedReports`. Au-delà : hard
  /// delete (récursif, sous-collections incluses).
  static const int archivedRetentionDays = 30;

  // --- Liens légaux ---

  /// URL publique de la politique de confidentialité (Firebase Hosting).
  /// Source : `public/privacy.html`. Exigée par les stores + lien in-app.
  static const String privacyPolicyUrl =
      'https://lightcutoff-dev.web.app/privacy';

  /// URL publique des Conditions d'utilisation (Firebase Hosting).
  /// Source : `public/cgu.html`. Liée à la case d'acceptation à l'inscription.
  static const String termsUrl = 'https://lightcutoff-dev.web.app/cgu';

  /// Adresse de support (tuile « Signaler un problème », Paramètres → Aide).
  /// Le brouillon d'email est pré-rempli avec le diagnostic (version, OS…).
  static const String supportEmail = 'support@bogal.ca';

  /// Sondage de retour des testeurs (Google Forms). Affiché via une bannière
  /// sur la Liste **en staging/dev uniquement** (cf. AppConfig.showDevTools).
  static const String surveyUrl =
      'https://docs.google.com/forms/d/e/1FAIpQLSc4-2-C0Kryt4SUDGO0WucSYPqK4fEtAlCWBv6_HTRBKklMgA/viewform';
}
