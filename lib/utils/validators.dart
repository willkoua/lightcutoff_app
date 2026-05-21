class Validators {
  Validators._();

  static final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'L\'email est requis';
    if (!_emailRegex.hasMatch(v)) return 'Email invalide';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Le mot de passe est requis';
    if (v.length < 6) return 'Au moins 6 caractères';
    return null;
  }

  static String? required(String? value, {String label = 'Ce champ'}) {
    if ((value?.trim() ?? '').isEmpty) return '$label est requis';
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Le téléphone est requis';
    if (v.replaceAll(RegExp(r'[\s+]'), '').length < 8) {
      return 'Numéro invalide';
    }
    return null;
  }
}
