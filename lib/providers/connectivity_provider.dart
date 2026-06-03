import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// État de connectivité réseau de l'appareil, exposé à l'UI pour afficher le
/// bandeau « Hors ligne » et adapter les actions impossibles sans réseau.
///
/// ⚠️ `connectivity_plus` détecte l'**interface réseau** (Wi-Fi / données /
/// aucune), pas la **vraie joignabilité d'Internet** : on peut être « en ligne »
/// sur un Wi-Fi sans accès. C'est suffisant pour un bandeau d'information ; pour
/// la cohérence des données, on s'appuie sur la file d'attente offline de
/// Firestore (persistance activée).
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _offline = false;
  bool get isOffline => _offline;

  Future<void> _init() async {
    try {
      _apply(await _connectivity.checkConnectivity());
    } catch (_) {
      // En cas d'échec du check initial, on suppose en ligne (pas de faux
      // bandeau bloquant).
    }
    _sub = _connectivity.onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    // En ligne dès qu'au moins une interface n'est pas « none ». Liste vide =
    // hors ligne.
    final online = results.any((r) => r != ConnectivityResult.none);
    final newOffline = !online;
    if (newOffline == _offline) return; // pas de changement → on ne notifie pas
    _offline = newOffline;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
