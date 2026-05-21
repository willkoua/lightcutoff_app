import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../repositories/storage_repository.dart';

/// Implémentation Firebase Storage de [StorageRepository].
class StorageService implements StorageRepository {
  StorageService({FirebaseStorage? storage}) : _override = storage;

  // Résolu paresseusement pour ne pas toucher FirebaseStorage.instance
  // à la construction (utile en tests sans Firebase initialisé).
  final FirebaseStorage? _override;
  FirebaseStorage get _storage => _override ?? FirebaseStorage.instance;

  @override
  Future<String> uploadReportMedia({
    required String uid,
    required Uint8List bytes,
    String contentType = 'image/gif',
  }) async {
    final ext = contentType.split('/').last;
    final ref = _storage.ref(
      'report_media/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
