bool isSafeBrowserUri(Uri uri) {
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

Uri? resolveBrowserInput(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    return isSafeBrowserUri(parsed) ? parsed : null;
  }

  final looksLikeHost = !value.contains(RegExp(r'\s')) && value.contains('.');
  if (looksLikeHost) {
    final uri = Uri.tryParse('https://$value');
    return uri != null && isSafeBrowserUri(uri) ? uri : null;
  }

  return Uri.https('www.google.com', '/search', {'q': value});
}
