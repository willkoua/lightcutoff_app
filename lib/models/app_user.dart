import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';
import 'geo.dart';

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String? phoneNumber;
  final String? photoURL;
  final GeoArea homeLocation;
  final UserRole role;
  final AccountStatus status;
  final DateTime? disabledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.phoneNumber,
    this.photoURL,
    this.homeLocation = const GeoArea(),
    this.role = UserRole.citizen,
    this.status = AccountStatus.active,
    this.disabledAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isDisabled => status == AccountStatus.disabled;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return AppUser(
      uid: doc.id,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      phoneNumber: map['phoneNumber'] as String?,
      photoURL: map['photoURL'] as String?,
      homeLocation: GeoArea.fromMap(map['homeLocation'] as Map<String, dynamic>?),
      role: UserRole.fromName(map['role'] as String?),
      status: AccountStatus.fromName(map['status'] as String?),
      disabledAt: (map['disabledAt'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Données pour la création initiale du profil.
  Map<String, dynamic> toCreateMap() => {
        'email': email,
        'displayName': displayName,
        'phoneNumber': phoneNumber,
        'photoURL': photoURL,
        'homeLocation': homeLocation.toMap(),
        'role': role.name,
        'status': status.name,
        'disabledAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
