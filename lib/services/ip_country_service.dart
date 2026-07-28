import 'dart:convert';

import 'package:http/http.dart' as http;

/// Détection du pays par **adresse IP** — repli de la détection GPS
/// (permission refusée, service coupé, position introuvable).
///
/// Endpoint : `https://api.country.is/` — gratuit, sans clé, HTTPS,
/// pas de journalisation des requêtes, réponse `{"ip": "...", "country": "CM"}`
/// (vérifié en live le 2026-07-28).
///
/// ⚠️ Un VPN fausse le résultat → ne JAMAIS le faire primer sur le GPS.
/// Échec silencieux (`null`) : le pays retombe alors sur profil / locale / CM.
Future<String?> countryFromIp({
  http.Client? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse('https://api.country.is/'))
        .timeout(timeout);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    final iso = body['country'];
    if (iso is! String || iso.length != 2) return null;
    return iso.toUpperCase();
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
