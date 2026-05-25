import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/device.dart';
import '../repositories/device_repository.dart';

/// Implémentation Firestore du [DeviceRepository].
class DeviceService implements DeviceRepository {
  DeviceService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _devices => _db.collection('devices');

  @override
  Future<void> upsertDevice(Device device) {
    // L'id du doc = token FCM ; merge:true pour ne pas écraser les champs
    // gérés ailleurs (p. ex. `fcmEnabled` toggle par l'utilisateur).
    return _devices.doc(device.token).set(device.toWriteMap(), SetOptions(merge: true));
  }

  @override
  Future<void> deleteDevice(String token) => _devices.doc(token).delete();
}
