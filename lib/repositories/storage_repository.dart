import 'dart:typed_data';

/// Contrat de stockage des médias (GIF/images des signalements).
abstract class StorageRepository {
  /// Upload un média de signalement et renvoie son URL de téléchargement.
  Future<String> uploadReportMedia({
    required String uid,
    required Uint8List bytes,
    String contentType,
  });
}
