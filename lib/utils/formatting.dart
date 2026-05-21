String relativeTime(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 4) return 'il y a $weeks sem';
  final months = (diff.inDays / 30).floor();
  if (months < 12) return 'il y a $months mois';
  return 'il y a ${(diff.inDays / 365).floor()} an(s)';
}
