/// The web address of [link], or null when [link] is not an http or https address.
Uri? webLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  return uri;
}
