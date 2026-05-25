import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Override manuel de la locale de l'app (utile pour tester FR/EN sans
/// changer la langue système).
///
/// `null` = pas d'override → Flutter utilise la locale du téléphone et tombe
/// sur le premier `supportedLocale` si elle n'est pas supportée.
///
/// La valeur est persistée dans `SharedPreferences` sous la clé
/// `locale_override` (ex. `"fr"`, `"en"`, ou absente).
class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    _load();
  }

  static const _prefKey = 'locale_override';

  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    if (code != null && code.isNotEmpty) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  /// Définit l'override. `null` = retour à la locale système.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, locale.languageCode);
    }
  }
}
