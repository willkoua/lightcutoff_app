import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/repositories/auth_repository.dart';
import 'package:lightcutoff_app/services/auth_service.dart';

/// Tests d'intégration de [AuthService] : Firestore fake + Auth mock.
/// Couvre la logique propre au service — résolution pseudo→email, garde
/// « compte désactivé », inscription (compte + doc user + index pseudo).
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<void> seedUser(
    String uid, {
    String username = 'willk',
    String email = 'will@njuka.app',
    String status = 'active',
  }) {
    return db.collection('users').doc(uid).set({
      'email': email,
      'username': username,
      'firstName': 'Will',
      'lastName': 'Koua',
      'role': 'citizen',
      'status': status,
    });
  }

  Future<void> seedUsername(
    String uname, {
    required String uid,
    required String email,
  }) {
    return db.collection('usernames').doc(uname).set({
      'uid': uid,
      'email': email,
    });
  }

  test('isUsernameAvailable : libre puis pris (normalisé)', () async {
    final service = AuthService(auth: MockFirebaseAuth(), firestore: db);
    expect(await service.isUsernameAvailable('willk'), isTrue);
    await seedUsername('willk', uid: 'u1', email: 'a@b.com');
    expect(await service.isUsernameAvailable('WILLK'), isFalse);
  });

  test('fetchProfile : null si absent, AppUser sinon', () async {
    final service = AuthService(auth: MockFirebaseAuth(), firestore: db);
    expect(await service.fetchProfile('nope'), isNull);
    await seedUser('u1');
    final p = await service.fetchProfile('u1');
    expect(p?.username, 'willk');
  });

  group('signInWithIdentifier', () {
    test('résout le pseudo en email puis connecte', () async {
      await seedUsername('willk', uid: 'u1', email: 'will@njuka.app');
      await seedUser('u1');
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', email: 'will@njuka.app'),
      );
      final service = AuthService(auth: auth, firestore: db);

      await service.signInWithIdentifier(
        identifier: 'willk',
        password: 'secret',
      );

      expect(auth.currentUser?.uid, 'u1');
    });

    test('pseudo inconnu → user-not-found', () async {
      final service = AuthService(auth: MockFirebaseAuth(), firestore: db);
      expect(
        () => service.signInWithIdentifier(identifier: 'ghost', password: 'x'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'user-not-found',
          ),
        ),
      );
    });

    test('compte désactivé → AccountDisabledException + déconnexion', () async {
      await seedUser('u1', email: 'a@b.com', status: 'disabled');
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', email: 'a@b.com'),
      );
      final service = AuthService(auth: auth, firestore: db);

      await expectLater(
        service.signInWithIdentifier(identifier: 'a@b.com', password: 'x'),
        throwsA(isA<AccountDisabledException>()),
      );
      expect(auth.currentUser, isNull); // signOut a bien été appelé
    });
  });

  group('register', () {
    test('crée le compte, le doc user et l\'index pseudo (normalisé)', () async {
      final auth = MockFirebaseAuth(mockUser: MockUser(email: 'new@njuka.app'));
      final service = AuthService(auth: auth, firestore: db);

      await service.register(
        firstName: 'Will',
        lastName: 'Koua',
        username: 'WillK',
        email: 'new@njuka.app',
        password: 'secret',
        birthDate: DateTime(2000, 1, 1),
      );

      // L'uid est attribué par le mock à la création — on le lit via currentUser.
      final uid = auth.currentUser!.uid;
      final userDoc = await db.collection('users').doc(uid).get();
      expect(userDoc.exists, isTrue);
      expect(userDoc.data()!['username'], 'willk'); // normalisé en minuscules

      final unameDoc = await db.collection('usernames').doc('willk').get();
      expect(unameDoc.data()!['uid'], uid);
    });

    test('pseudo déjà pris → username-already-in-use', () async {
      await seedUsername('willk', uid: 'other', email: 'x@y.com');
      final service = AuthService(auth: MockFirebaseAuth(), firestore: db);

      expect(
        () => service.register(
          firstName: 'W',
          lastName: 'K',
          username: 'willk',
          email: 'a@b.com',
          password: 'secret',
        ),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'username-already-in-use',
          ),
        ),
      );
    });
  });
}
