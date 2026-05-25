import '../models/device.dart';

/// Contrat d'accès à la collection `devices/{token}`.
///
/// L'id du document est **toujours le token FCM** : on upserte (set + merge),
/// ce qui rend l'enregistrement idempotent (même appareil = même doc).
abstract class DeviceRepository {
  /// Crée/met à jour le doc `devices/{token}` pour cet utilisateur.
  Future<void> upsertDevice(Device device);

  /// Supprime un doc device (déconnexion / désinscription).
  Future<void> deleteDevice(String token);
}
