import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// App Links / Universal Links — `https://njuka.app/s/{reportId}`.
///
/// Quand l'app est installée, le lien de partage l'ouvre directement (au lieu
/// de la page web) et navigue vers le détail du signalement en réutilisant le
/// canal existant des notifications ([NotificationService.pendingReportId],
/// consommé par MainShell). Vérification du domaine : `assetlinks.json` +
/// `apple-app-site-association` servis par le site njuka.app.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  bool _initialized = false;

  /// ID de signalement extrait d'un lien `/s/{id}`, sinon `null`.
  @visibleForTesting
  static String? reportIdFromUri(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments.first != 's') return null;
    final id = segments[1];
    final valid = RegExp(r'^[A-Za-z0-9_-]{5,40}$').hasMatch(id);
    return valid ? id : null;
  }

  /// Écoute le lien de lancement à froid ET les liens reçus app ouverte.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('[DeepLink] lien initial illisible: $e');
    }
    _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('[DeepLink] erreur de flux: $e'),
    );
  }

  void _handle(Uri uri) {
    final reportId = reportIdFromUri(uri);
    if (reportId == null) return;
    debugPrint('[DeepLink] ouverture du signalement $reportId');
    NotificationService.instance.pendingReportId.value = reportId;
  }
}
