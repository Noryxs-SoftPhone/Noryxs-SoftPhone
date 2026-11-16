/// Búsqueda tolerante: sin mayúsculas ni acentos, y números comparados solo por sus dígitos
/// ("+34 612 84" encuentra "612849310"; "garcia" encuentra "García").
library;

const _from = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
const _to = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';

String foldText(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString().toLowerCase();
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// true si [query] aparece en alguno de los textos o (si tiene dígitos) en alguno de los números.
bool matchesQuery(String query, {Iterable<String> texts = const [], Iterable<String> numbers = const []}) {
  final q = foldText(query.trim());
  if (q.isEmpty) return true;
  for (final t in texts) {
    if (foldText(t).contains(q)) return true;
  }
  final qd = _digits(query);
  if (qd.length >= 2) {
    for (final n in numbers) {
      final d = _digits(n);
      // Ignorar el prefijo internacional al comparar (34612… ~ 612…)
      if (d.contains(qd) || (qd.startsWith('34') && d.contains(qd.substring(2)))) return true;
    }
  }
  return false;
}
