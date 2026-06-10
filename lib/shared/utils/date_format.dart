// Pure date display helpers. The month-abbreviation table lives here and
// nowhere else.

const kShortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Mar 4"
String formatMonthDay(DateTime dt) => '${kShortMonths[dt.month - 1]} ${dt.day}';

/// "Mar 4, 2026"
String formatMonthDayYear(DateTime dt) => '${formatMonthDay(dt)}, ${dt.year}';

/// Relative timestamp for list rows: "3m ago", "2h ago", "5d ago",
/// then "Mar 4" beyond a week.
String formatRelative(int msEpoch) {
  final dt = DateTime.fromMillisecondsSinceEpoch(msEpoch);
  final diff = DateTime.now().difference(dt);
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatMonthDay(dt);
}
