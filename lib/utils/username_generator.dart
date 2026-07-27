/// Génération de pseudos : `slug_NNN` à partir d'un « germe » (prénom, nom
/// affiché du provider social, ou partie locale de l'email).
///
/// Pourquoi : le pseudo est **attribué** à la création du compte (zéro
/// friction, pas de champ obligatoire ni d'erreur « déjà pris ») puis
/// personnalisable **une seule fois** (Profil → Modifier). Cf. décision
/// produit 2026-07-25.
library;

import 'dart:math';

const int _suffixMin = 10;
const int _suffixMax = 999;
const int _slugMaxLength = 15;

/// Translittération grossière des caractères accentués courants (fr).
const Map<String, String> _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'õ': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Slug en minuscules, sans accents ni caractères spéciaux, tronqué à
/// [_slugMaxLength]. Renvoie `citoyen` si le germe est inutilisable.
String usernameSlug(String? seed) {
  var s = (seed ?? '').trim().toLowerCase();
  // Email → partie locale ; nom complet → premier mot (le prénom).
  if (s.contains('@')) s = s.split('@').first;
  if (s.contains(' ')) s = s.split(RegExp(r'\s+')).first;
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final mapped = _accents[ch] ?? ch;
    if (RegExp(r'[a-z0-9_]').hasMatch(mapped)) buf.write(mapped);
  }
  var slug = buf.toString();
  if (slug.length > _slugMaxLength) slug = slug.substring(0, _slugMaxLength);
  return slug.isEmpty ? 'citoyen' : slug;
}

/// Propose un pseudo `slug_NNN`. [random] est injectable pour les tests.
String generateUsername(String? seed, {Random? random}) {
  final rng = random ?? Random();
  final suffix = _suffixMin + rng.nextInt(_suffixMax - _suffixMin + 1);
  return '${usernameSlug(seed)}_$suffix';
}
