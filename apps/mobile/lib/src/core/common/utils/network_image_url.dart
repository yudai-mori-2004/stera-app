/// Returns true only for non-empty http(s) URLs with a host. Avoids
/// [CachedNetworkImage] / [Image.network] throwing on "" or malformed URIs.
bool isValidHttpImageUrl(String? url) {
  if (url == null) return false;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (uri.scheme != "http" && uri.scheme != "https") return false;
  return uri.hasAuthority && uri.host.isNotEmpty;
}
