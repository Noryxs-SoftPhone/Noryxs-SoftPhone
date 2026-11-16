/// Clic para llamar: extrae el número de un enlace tel:, sip:, sips: o callto:.
///   tel:+34 600 11 22 33   → +34600112233
///   sip:201@pbx.hotel.es   → 201
///   callto://600112233     → 600112233
/// Devuelve null si el enlace no lleva un número marcable.
String? parseDialUrl(String url) {
  var s = Uri.decodeFull(url.trim());
  final m = RegExp(r'^(tel|sips?|callto):(//)?', caseSensitive: false).firstMatch(s);
  if (m == null) return null;
  s = s.substring(m.end);
  s = s.split(RegExp(r'[;?]')).first; // parámetros (;phone-context=…, ?subject=…)
  if (m[1]!.toLowerCase().startsWith('sip')) s = s.split('@').first;
  final n = s.replaceAll(RegExp(r'[^0-9+*#]'), '');
  if (n.isEmpty) return null;
  // El + solo vale al principio
  return n[0] + n.substring(1).replaceAll('+', '');
}
