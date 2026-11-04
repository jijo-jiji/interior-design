/// "1 cabinet", "9 cabinets".
String cabinetCountLabel(int count) =>
    count == 1 ? '1 cabinet' : '$count cabinets';

/// How long ago something was saved: "just now", "10 min ago", "3 h ago",
/// "yesterday", "4 days ago".
String timeAgoLabel(DateTime saved, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(saved);
  if (age.inMinutes < 1) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours} h ago';
  if (age.inDays == 1) return 'yesterday';
  return '${age.inDays} days ago';
}
