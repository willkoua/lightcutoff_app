import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marqueur local d'activité de la session ANONYME courante.
///
/// Sert à n'afficher l'avertissement « tes signalements/votes anonymes ne
/// seront pas rattachés » (avant l'écran de connexion) QUE si la session a
/// réellement quelque chose à perdre — un nouvel utilisateur qui n'a rien
/// fait se connecte sans friction (décision 2026-07-25).
///
/// On stocke l'**uid** anonyme ayant agi : le marqueur s'invalide donc tout
/// seul quand une nouvelle session anonyme démarre (uid différent), sans
/// nettoyage explicite au logout/reset.
const String _kAnonActivityUidKey = 'anon_activity_uid';

/// À appeler après toute action de contenu (signalement, confirmation,
/// démenti, déclaration de retour) — sans effet si [user] n'est pas anonyme.
Future<void> markAnonymousActivity(User? user) async {
  if (user == null || !user.isAnonymous) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAnonActivityUidKey, user.uid);
  } catch (_) {
    // Best-effort : au pire, l'avertissement s'affichera par défaut.
  }
}

/// Vrai si la session anonyme COURANTE a déjà produit du contenu.
Future<bool> anonymousSessionHasActivity(User? user) async {
  if (user == null || !user.isAnonymous) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAnonActivityUidKey) == user.uid;
  } catch (_) {
    // En cas de doute, on protège : considérer qu'il y a de l'activité.
    return true;
  }
}
