/// Date courte « JJ/MM/AAAA ».
///
/// Pour les durées relatives (« il y a 3 h »), utiliser `relativeTimeL10n`
/// dans `utils/l10n_helpers.dart` qui prend un BuildContext et lit les
/// libellés depuis les fichiers ARB.
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}
