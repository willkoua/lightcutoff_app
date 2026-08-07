/// Rendu des taches d'impact sur la carte — fonctions pures et testées.
///
/// Une coupure est dessinée comme un disque translucide couleur service :
/// le RAYON dit l'ampleur (agrégat `impactRadiusM` calculé côté serveur),
/// l'OPACITÉ dit la fraîcheur (dernier signal = confirmation ou création).
library;

/// Rayon plancher (mètres) d'un signalement jamais confirmé — assez pour
/// être visible au zoom quartier, assez petit pour rester « un point de
/// départ » face à une coupure confirmée.
const double kImpactMinRadiusM = 150;

/// Fraîcheur pleine jusqu'à 2 h, puis décroissance linéaire jusqu'à 24 h.
const Duration kZoneFreshFor = Duration(hours: 2);
const Duration kZoneStaleAfter = Duration(hours: 24);

const double kZoneMaxOpacity = 0.28;
const double kZoneMinOpacity = 0.10;

/// Rayon affiché : agrégat serveur, sinon plancher.
double zoneRadiusM(double? impactRadiusM) {
  final r = impactRadiusM ?? 0;
  return r < kImpactMinRadiusM ? kImpactMinRadiusM : r;
}

/// Opacité du remplissage selon l'âge du dernier signal.
///
/// `lastSignalAt` = `updatedAt` du report (bougé par chaque confirmation et
/// par l'extension de rayon serveur) avec repli sur `reportedAt`. `null`
/// (donnée legacy incomplète) → opacité minimale, la tache reste discrète.
double zoneOpacity(DateTime? lastSignalAt, {required DateTime now}) {
  if (lastSignalAt == null) return kZoneMinOpacity;
  final age = now.difference(lastSignalAt);
  if (age <= kZoneFreshFor) return kZoneMaxOpacity;
  if (age >= kZoneStaleAfter) return kZoneMinOpacity;
  final span = kZoneStaleAfter - kZoneFreshFor;
  final progress = (age - kZoneFreshFor).inSeconds / span.inSeconds; // 0 → 1
  return kZoneMaxOpacity - (kZoneMaxOpacity - kZoneMinOpacity) * progress;
}

/// Opacité du liseré : lisible sans dominer (2× le remplissage, plafonné).
double zoneBorderOpacity(double fillOpacity) {
  final o = fillOpacity * 2;
  return o > 0.6 ? 0.6 : o;
}
