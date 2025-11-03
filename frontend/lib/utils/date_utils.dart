/// Utility functions for date and time formatting
String formatTimestamp(DateTime timestamp) {
  final now = DateTime.now();
  final difference = now.difference(timestamp);

  if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'Just now';
  }
}
