import 'dart:convert';
import 'dart:typed_data';

/// Generador de códigos QR (modo byte, corrección de errores L), sin dependencias.
/// Basado en el algoritmo de referencia de Project Nayuki (dominio público / MIT).
class QrCode {
  QrCode._(this.size, this._modules);
  final int size;
  final List<bool> _modules;
  bool get(int x, int y) => _modules[y * size + x];

  /// Código para un texto UTF-8, o null si no cabe (máx. ≈2.9 KB).
  static QrCode? encode(String text) {
    final data = Uint8List.fromList(utf8.encode(text));
    for (var ver = 1; ver <= 40; ver++) {
      final capBits = _dataCodewords(ver) * 8;
      final ccBits = ver < 10 ? 8 : 16;
      final used = 4 + ccBits + data.length * 8;
      if (used <= capBits) return _build(ver, data);
    }
    return null;
  }

  // Codewords de corrección por bloque y número de bloques (nivel L), índices 1..40.
  static const _eccPerBlock = [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30];
  static const _numBlocks = [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25];

  static int _rawModules(int ver) {
    var r = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      final na = ver ~/ 7 + 2;
      r -= (25 * na - 10) * na - 55;
      if (ver >= 7) r -= 36;
    }
    return r;
  }

  static int _dataCodewords(int ver) => _rawModules(ver) ~/ 8 - _eccPerBlock[ver] * _numBlocks[ver];

  static QrCode _build(int ver, Uint8List data) {
    // Flujo de bits: modo byte (0100) + longitud + datos + terminador y relleno
    final bits = <int>[];
    void put(int v, int n) {
      for (var i = n - 1; i >= 0; i--) {
        bits.add((v >> i) & 1);
      }
    }

    put(4, 4);
    put(data.length, ver < 10 ? 8 : 16);
    for (final b in data) {
      put(b, 8);
    }
    final cap = _dataCodewords(ver) * 8;
    put(0, (cap - bits.length).clamp(0, 4));
    put(0, (8 - bits.length % 8) % 8);
    for (var pad = 0xEC; bits.length < cap; pad ^= 0xEC ^ 0x11) {
      put(pad, 8);
    }
    final dataCw = Uint8List(bits.length ~/ 8);
    for (var i = 0; i < bits.length; i++) {
      dataCw[i >> 3] |= bits[i] << (7 - (i & 7));
    }
    final all = _addEcc(ver, dataCw);

    final size = ver * 4 + 17;
    final mods = List<bool>.filled(size * size, false);
    final isFn = List<bool>.filled(size * size, false);
    void set(int x, int y, bool v) {
      mods[y * size + x] = v;
      isFn[y * size + x] = true;
    }

    // Patrones de temporización, buscadores y alineación
    for (var i = 0; i < size; i++) {
      set(6, i, i % 2 == 0);
      set(i, 6, i % 2 == 0);
    }
    void finder(int cx, int cy) {
      for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          final d = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
          final x = cx + dx, y = cy + dy;
          if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, d != 2 && d != 4);
        }
      }
    }

    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);
    final align = _alignPositions(ver);
    for (var i = 0; i < align.length; i++) {
      for (var j = 0; j < align.length; j++) {
        if ((i == 0 && j == 0) || (i == 0 && j == align.length - 1) || (i == align.length - 1 && j == 0)) continue;
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            set(align[i] + dx, align[j] + dy, (dx.abs() > dy.abs() ? dx.abs() : dy.abs()) != 1);
          }
        }
      }
    }
    // Reservar formato y versión (se escriben al final)
    _drawFormat(mods, isFn, size, 0, reserveOnly: true);
    _drawVersion(mods, isFn, size, ver);

    // Colocar los datos en zigzag
    var i = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final x = right - j;
          final upward = ((right + 1) & 2) == 0;
          final y = upward ? size - 1 - vert : vert;
          if (!isFn[y * size + x] && i < all.length * 8) {
            mods[y * size + x] = ((all[i >> 3] >> (7 - (i & 7))) & 1) == 1;
            i++;
          }
        }
      }
    }

    // Elegir la máscara con menor penalización
    var best = 0, bestScore = 1 << 30;
    for (var m = 0; m < 8; m++) {
      final t = List<bool>.of(mods);
      _applyMask(t, isFn, size, m);
      _drawFormat(t, isFn, size, m);
      final s = _penalty(t, size);
      if (s < bestScore) {
        bestScore = s;
        best = m;
      }
    }
    _applyMask(mods, isFn, size, best);
    _drawFormat(mods, isFn, size, best);
    return QrCode._(size, mods);
  }

  static List<int> _alignPositions(int ver) {
    if (ver == 1) return [];
    final num = ver ~/ 7 + 2;
    final step = ver == 32 ? 26 : ((ver * 4 + num * 2 + 1) ~/ (num * 2 - 2)) * 2;
    final res = <int>[6];
    for (var pos = ver * 4 + 17 - 7; res.length < num; pos -= step) {
      res.insert(1, pos);
    }
    return res;
  }

  static void _drawFormat(List<bool> m, List<bool> fn, int size, int mask, {bool reserveOnly = false}) {
    // Nivel L = 01
    final data = (1 << 3) | mask;
    var rem = data;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    final bits = ((data << 10) | rem) ^ 0x5412;
    bool b(int i) => !reserveOnly && ((bits >> i) & 1) == 1;
    void s(int x, int y, bool v) {
      m[y * size + x] = v;
      fn[y * size + x] = true;
    }

    for (var i = 0; i <= 5; i++) {
      s(8, i, b(i));
    }
    s(8, 7, b(6));
    s(8, 8, b(7));
    s(7, 8, b(8));
    for (var i = 9; i < 15; i++) {
      s(14 - i, 8, b(i));
    }
    for (var i = 0; i < 8; i++) {
      s(size - 1 - i, 8, b(i));
    }
    for (var i = 8; i < 15; i++) {
      s(8, size - 15 + i, b(i));
    }
    s(8, size - 8, true); // módulo oscuro
  }

  static void _drawVersion(List<bool> m, List<bool> fn, int size, int ver) {
    if (ver < 7) return;
    var rem = ver;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    }
    final bits = (ver << 12) | rem;
    for (var i = 0; i < 18; i++) {
      final v = ((bits >> i) & 1) == 1;
      final a = size - 11 + i % 3, b = i ~/ 3;
      m[b * size + a] = v;
      fn[b * size + a] = true;
      m[a * size + b] = v;
      fn[a * size + b] = true;
    }
  }

  static void _applyMask(List<bool> m, List<bool> fn, int size, int mask) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (fn[y * size + x]) continue;
        final inv = switch (mask) {
          0 => (x + y) % 2 == 0,
          1 => y % 2 == 0,
          2 => x % 3 == 0,
          3 => (x + y) % 3 == 0,
          4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
          5 => x * y % 2 + x * y % 3 == 0,
          6 => (x * y % 2 + x * y % 3) % 2 == 0,
          _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
        };
        if (inv) m[y * size + x] = !m[y * size + x];
      }
    }
  }

  static int _penalty(List<bool> m, int size) {
    var score = 0;
    bool at(int x, int y) => m[y * size + x];
    // Rachas de 5+ y bloques 2×2
    for (var y = 0; y < size; y++) {
      var run = 1;
      for (var x = 1; x < size; x++) {
        if (at(x, y) == at(x - 1, y)) {
          run++;
          if (run == 5) score += 3;
          if (run > 5) score++;
        } else {
          run = 1;
        }
      }
    }
    for (var x = 0; x < size; x++) {
      var run = 1;
      for (var y = 1; y < size; y++) {
        if (at(x, y) == at(x, y - 1)) {
          run++;
          if (run == 5) score += 3;
          if (run > 5) score++;
        } else {
          run = 1;
        }
      }
    }
    for (var y = 0; y < size - 1; y++) {
      for (var x = 0; x < size - 1; x++) {
        final c = at(x, y);
        if (c == at(x + 1, y) && c == at(x, y + 1) && c == at(x + 1, y + 1)) score += 3;
      }
    }
    // Equilibrio de oscuros
    final dark = m.where((v) => v).length;
    final k = ((dark * 20 - m.length * 10).abs() + m.length - 1) ~/ m.length - 1;
    return score + k * 10;
  }

  // ---- Reed–Solomon sobre GF(256) ----
  static Uint8List _addEcc(int ver, Uint8List data) {
    final nb = _numBlocks[ver], ecl = _eccPerBlock[ver];
    final raw = _rawModules(ver) ~/ 8;
    final shortLen = raw ~/ nb;
    final numShort = nb - raw % nb;
    final gen = _rsGenerator(ecl);
    final blocks = <List<int>>[];
    var k = 0;
    for (var i = 0; i < nb; i++) {
      final len = shortLen - ecl + (i < numShort ? 0 : 1);
      final d = data.sublist(k, k + len);
      k += len;
      final ecc = _rsRemainder(d, gen);
      final b = <int>[...d];
      if (i < numShort) b.add(0); // relleno para intercalar
      b.addAll(ecc);
      blocks.add(b);
    }
    final out = <int>[];
    for (var i = 0; i < blocks[0].length; i++) {
      for (var j = 0; j < blocks.length; j++) {
        if (i != shortLen - ecl || j >= numShort) out.add(blocks[j][i]);
      }
    }
    return Uint8List.fromList(out);
  }

  static int _mul(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      z ^= ((y >> i) & 1) * x;
    }
    return z & 0xFF;
  }

  static List<int> _rsGenerator(int degree) {
    final r = List<int>.filled(degree, 0);
    r[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < degree; j++) {
        r[j] = _mul(r[j], root);
        if (j + 1 < degree) r[j] ^= r[j + 1];
      }
      root = _mul(root, 0x02);
    }
    return r;
  }

  static List<int> _rsRemainder(List<int> data, List<int> gen) {
    final r = List<int>.filled(gen.length, 0, growable: true);
    for (final b in data) {
      final f = b ^ r[0];
      r.removeAt(0);
      r.add(0);
      for (var i = 0; i < r.length; i++) {
        r[i] ^= _mul(gen[i], f);
      }
    }
    return r;
  }
}
