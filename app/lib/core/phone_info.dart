// Números de teléfono: formato unificado e identificación offline del origen.
//
// - Formato canónico para comparar (agenda, historial, notas): "+34612849310",
//   o los dígitos tal cual para extensiones internas.
// - Origen: España con detalle (provincia de los fijos, móvil, servicios
//   especiales) y país (+ móvil/fijo en los principales) para el resto.
// - No se muestra el operador: con la portabilidad no es fiable sin internet.

class PhoneInfo {
  const PhoneInfo({required this.label, this.flag = '', this.internal = false});
  final String label; // "Barcelona • Fijo", "Francia • Móvil", "Extensión interna"
  final String flag; // emoji de bandera
  final bool internal;

  String get display => flag.isEmpty ? label : '$flag $label';
}

class PhoneNumbers {
  const PhoneNumbers._();

  /// País por defecto para números sin prefijo internacional.
  static const defaultCountry = '34';

  /// Formato canónico. Extensiones (≤ 5 dígitos) y códigos (*97, **205) se devuelven tal cual.
  static String canonical(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('*')) return s;
    final plus = s.startsWith('+');
    var d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return s;
    if (plus) return '+$d';
    if (d.startsWith('00') && d.length > 6) return '+${d.substring(2)}';
    if (d.length <= 5) return d; // extensión interna
    // Nacional español de 9 cifras
    if (d.length == 9 && RegExp(r'^[6789]').hasMatch(d)) return '+$defaultCountry$d';
    // Con el 34 delante pero sin '+'
    if (d.length == 11 && d.startsWith('34') && RegExp(r'^34[6789]').hasMatch(d)) return '+$d';
    return d;
  }

  static bool same(String a, String b) {
    final ca = canonical(a), cb = canonical(b);
    if (ca.isEmpty || cb.isEmpty) return false;
    if (ca == cb) return true;
    // Últimas 9 cifras (cubre formatos mixtos)
    final da = ca.replaceAll(RegExp(r'[^0-9]'), ''), db = cb.replaceAll(RegExp(r'[^0-9]'), '');
    return da.length >= 9 && db.length >= 9 && da.substring(da.length - 9) == db.substring(db.length - 9);
  }

  /// Origen del número, o null si no aporta nada (vacío, código de servicio…).
  static PhoneInfo? lookup(String raw) {
    final c = canonical(raw);
    if (c.isEmpty || c.startsWith('*')) return null;
    if (!c.startsWith('+')) {
      if (c.length <= 5) return const PhoneInfo(label: 'Extensión interna', internal: true);
      return null;
    }
    final d = c.substring(1);
    if (d.startsWith('34')) return _spain(d.substring(2));
    return _international(d);
  }

  // ------------------------------------------------------------------ España

  static PhoneInfo _spain(String n) {
    const flag = '🇪🇸';
    if (n.length != 9) return const PhoneInfo(label: 'España', flag: flag);
    if (n.startsWith('6') || RegExp(r'^7[1-4]').hasMatch(n)) return const PhoneInfo(label: 'Móvil nacional', flag: flag);
    if (n.startsWith('900') || n.startsWith('800')) return const PhoneInfo(label: 'Número gratuito', flag: flag);
    if (n.startsWith('901')) return const PhoneInfo(label: 'Coste compartido', flag: flag);
    if (n.startsWith('902')) return const PhoneInfo(label: 'Tarifa nacional (902)', flag: flag);
    if (RegExp(r'^80[3-7]').hasMatch(n)) return const PhoneInfo(label: 'Tarificación adicional', flag: flag);
    if (n.startsWith('905')) return const PhoneInfo(label: 'Televoto', flag: flag);
    if (n.startsWith('70')) return const PhoneInfo(label: 'Número personal', flag: flag);
    if (n.startsWith('9') || n.startsWith('8')) {
      // Los fijos 8xx usan las mismas provincias que los 9xx
      final g = '9${n.substring(1)}';
      final p3 = _provinces3[g.substring(0, 3)];
      final p2 = _provinces2[g.substring(0, 2)];
      final prov = p3 ?? p2;
      if (prov != null) return PhoneInfo(label: '$prov • Fijo', flag: flag);
      return const PhoneInfo(label: 'Fijo nacional', flag: flag);
    }
    return const PhoneInfo(label: 'España', flag: flag);
  }

  static const _provinces2 = {'91': 'Madrid', '93': 'Barcelona'};

  static const _provinces3 = {
    '920': 'Ávila', '921': 'Segovia', '922': 'Santa Cruz de Tenerife', '923': 'Salamanca', '924': 'Badajoz',
    '925': 'Toledo', '926': 'Ciudad Real', '927': 'Cáceres', '928': 'Las Palmas',
    '941': 'La Rioja', '942': 'Cantabria', '943': 'Gipuzkoa', '944': 'Bizkaia', '945': 'Álava', '946': 'Bizkaia',
    '947': 'Burgos', '948': 'Navarra', '949': 'Guadalajara',
    '950': 'Almería', '951': 'Málaga', '952': 'Málaga', '953': 'Jaén', '954': 'Sevilla', '955': 'Sevilla',
    '956': 'Cádiz', '957': 'Córdoba', '958': 'Granada', '959': 'Huelva',
    '960': 'Valencia', '961': 'Valencia', '962': 'Valencia', '963': 'Valencia', '964': 'Castellón',
    '965': 'Alicante', '966': 'Alicante', '967': 'Albacete', '968': 'Murcia', '969': 'Cuenca',
    '971': 'Illes Balears', '972': 'Girona', '973': 'Lleida', '974': 'Huesca', '975': 'Soria',
    '976': 'Zaragoza', '977': 'Tarragona', '978': 'Teruel', '979': 'Palencia',
    '980': 'Zamora', '981': 'A Coruña', '982': 'Lugo', '983': 'Valladolid', '984': 'Asturias',
    '985': 'Asturias', '986': 'Pontevedra', '987': 'León', '988': 'Ourense',
  };

  // ----------------------------------------------------------- Internacional

  static PhoneInfo _international(String d) {
    for (var len = 4; len >= 1; len--) {
      if (d.length <= len) continue;
      final cc = d.substring(0, len);
      final c = _countries[cc];
      if (c == null) continue;
      final rest = d.substring(len);
      final mob = _mobile[cc];
      String kind = '';
      if (mob != null) kind = RegExp(mob).hasMatch(rest) ? ' • Móvil' : ' • Fijo';
      return PhoneInfo(label: '${c.$1}$kind', flag: c.$2);
    }
    return const PhoneInfo(label: 'Internacional', flag: '🌐');
  }

  /// Prefijos de móvil (sobre el número nacional sin el código de país).
  static const _mobile = {
    '33': r'^[67]', // Francia
    '351': r'^9', // Portugal
    '39': r'^3', // Italia
    '49': r'^1[5-7]', // Alemania
    '44': r'^7', // Reino Unido
    '31': r'^6', // Países Bajos
    '32': r'^4', // Bélgica
    '41': r'^7[5-9]', // Suiza
    '43': r'^6', // Austria
    '353': r'^8', // Irlanda
    '48': r'^[4-8]', // Polonia (aprox.)
    '212': r'^[67]', // Marruecos
    '54': r'^9', // Argentina
    '57': r'^3', // Colombia
    '58': r'^4', // Venezuela
    '56': r'^9', // Chile
    '593': r'^9', // Ecuador
    '51': r'^9', // Perú
    '53': r'^5', // Cuba
    '55': r'^\d{2}9', // Brasil
  };

  /// Código de país → (nombre, bandera).
  static const _countries = <String, (String, String)>{
    '1': ('EE. UU. / Canadá', '🇺🇸'), '7': ('Rusia / Kazajistán', '🇷🇺'), '20': ('Egipto', '🇪🇬'),
    '27': ('Sudáfrica', '🇿🇦'), '30': ('Grecia', '🇬🇷'), '31': ('Países Bajos', '🇳🇱'), '32': ('Bélgica', '🇧🇪'),
    '33': ('Francia', '🇫🇷'), '34': ('España', '🇪🇸'), '36': ('Hungría', '🇭🇺'), '39': ('Italia', '🇮🇹'),
    '40': ('Rumanía', '🇷🇴'), '41': ('Suiza', '🇨🇭'), '43': ('Austria', '🇦🇹'), '44': ('Reino Unido', '🇬🇧'),
    '45': ('Dinamarca', '🇩🇰'), '46': ('Suecia', '🇸🇪'), '47': ('Noruega', '🇳🇴'), '48': ('Polonia', '🇵🇱'),
    '49': ('Alemania', '🇩🇪'), '51': ('Perú', '🇵🇪'), '52': ('México', '🇲🇽'), '53': ('Cuba', '🇨🇺'),
    '54': ('Argentina', '🇦🇷'), '55': ('Brasil', '🇧🇷'), '56': ('Chile', '🇨🇱'), '57': ('Colombia', '🇨🇴'),
    '58': ('Venezuela', '🇻🇪'), '60': ('Malasia', '🇲🇾'), '61': ('Australia', '🇦🇺'), '62': ('Indonesia', '🇮🇩'),
    '63': ('Filipinas', '🇵🇭'), '64': ('Nueva Zelanda', '🇳🇿'), '65': ('Singapur', '🇸🇬'), '66': ('Tailandia', '🇹🇭'),
    '81': ('Japón', '🇯🇵'), '82': ('Corea del Sur', '🇰🇷'), '84': ('Vietnam', '🇻🇳'), '86': ('China', '🇨🇳'),
    '90': ('Turquía', '🇹🇷'), '91': ('India', '🇮🇳'), '92': ('Pakistán', '🇵🇰'), '93': ('Afganistán', '🇦🇫'),
    '94': ('Sri Lanka', '🇱🇰'), '95': ('Myanmar', '🇲🇲'), '98': ('Irán', '🇮🇷'),
    '211': ('Sudán del Sur', '🇸🇸'), '212': ('Marruecos', '🇲🇦'), '213': ('Argelia', '🇩🇿'), '216': ('Túnez', '🇹🇳'),
    '218': ('Libia', '🇱🇾'), '220': ('Gambia', '🇬🇲'), '221': ('Senegal', '🇸🇳'), '222': ('Mauritania', '🇲🇷'),
    '223': ('Malí', '🇲🇱'), '224': ('Guinea', '🇬🇳'), '225': ('Costa de Marfil', '🇨🇮'), '226': ('Burkina Faso', '🇧🇫'),
    '227': ('Níger', '🇳🇪'), '228': ('Togo', '🇹🇬'), '229': ('Benín', '🇧🇯'), '230': ('Mauricio', '🇲🇺'),
    '231': ('Liberia', '🇱🇷'), '232': ('Sierra Leona', '🇸🇱'), '233': ('Ghana', '🇬🇭'), '234': ('Nigeria', '🇳🇬'),
    '237': ('Camerún', '🇨🇲'), '240': ('Guinea Ecuatorial', '🇬🇶'), '241': ('Gabón', '🇬🇦'), '242': ('Congo', '🇨🇬'),
    '243': ('R. D. del Congo', '🇨🇩'), '244': ('Angola', '🇦🇴'), '245': ('Guinea-Bisáu', '🇬🇼'), '238': ('Cabo Verde', '🇨🇻'),
    '249': ('Sudán', '🇸🇩'), '251': ('Etiopía', '🇪🇹'), '254': ('Kenia', '🇰🇪'), '255': ('Tanzania', '🇹🇿'),
    '256': ('Uganda', '🇺🇬'), '258': ('Mozambique', '🇲🇿'), '260': ('Zambia', '🇿🇲'), '263': ('Zimbabue', '🇿🇼'),
    '297': ('Aruba', '🇦🇼'), '299': ('Groenlandia', '🇬🇱'), '350': ('Gibraltar', '🇬🇮'), '351': ('Portugal', '🇵🇹'),
    '352': ('Luxemburgo', '🇱🇺'), '353': ('Irlanda', '🇮🇪'), '354': ('Islandia', '🇮🇸'), '355': ('Albania', '🇦🇱'),
    '356': ('Malta', '🇲🇹'), '357': ('Chipre', '🇨🇾'), '358': ('Finlandia', '🇫🇮'), '359': ('Bulgaria', '🇧🇬'),
    '370': ('Lituania', '🇱🇹'), '371': ('Letonia', '🇱🇻'), '372': ('Estonia', '🇪🇪'), '373': ('Moldavia', '🇲🇩'),
    '374': ('Armenia', '🇦🇲'), '375': ('Bielorrusia', '🇧🇾'), '376': ('Andorra', '🇦🇩'), '377': ('Mónaco', '🇲🇨'),
    '378': ('San Marino', '🇸🇲'), '380': ('Ucrania', '🇺🇦'), '381': ('Serbia', '🇷🇸'), '382': ('Montenegro', '🇲🇪'),
    '385': ('Croacia', '🇭🇷'), '386': ('Eslovenia', '🇸🇮'), '387': ('Bosnia y Herzegovina', '🇧🇦'), '389': ('Macedonia del Norte', '🇲🇰'),
    '420': ('Chequia', '🇨🇿'), '421': ('Eslovaquia', '🇸🇰'), '423': ('Liechtenstein', '🇱🇮'),
    '501': ('Belice', '🇧🇿'), '502': ('Guatemala', '🇬🇹'), '503': ('El Salvador', '🇸🇻'), '504': ('Honduras', '🇭🇳'),
    '505': ('Nicaragua', '🇳🇮'), '506': ('Costa Rica', '🇨🇷'), '507': ('Panamá', '🇵🇦'), '509': ('Haití', '🇭🇹'),
    '591': ('Bolivia', '🇧🇴'), '593': ('Ecuador', '🇪🇨'), '595': ('Paraguay', '🇵🇾'), '598': ('Uruguay', '🇺🇾'),
    '852': ('Hong Kong', '🇭🇰'), '853': ('Macao', '🇲🇴'), '855': ('Camboya', '🇰🇭'), '880': ('Bangladés', '🇧🇩'),
    '886': ('Taiwán', '🇹🇼'), '960': ('Maldivas', '🇲🇻'), '961': ('Líbano', '🇱🇧'), '962': ('Jordania', '🇯🇴'),
    '963': ('Siria', '🇸🇾'), '964': ('Irak', '🇮🇶'), '965': ('Kuwait', '🇰🇼'), '966': ('Arabia Saudí', '🇸🇦'),
    '968': ('Omán', '🇴🇲'), '971': ('Emiratos Árabes', '🇦🇪'), '972': ('Israel', '🇮🇱'), '973': ('Baréin', '🇧🇭'),
    '974': ('Catar', '🇶🇦'), '976': ('Mongolia', '🇲🇳'), '977': ('Nepal', '🇳🇵'), '992': ('Tayikistán', '🇹🇯'),
    '993': ('Turkmenistán', '🇹🇲'), '994': ('Azerbaiyán', '🇦🇿'), '995': ('Georgia', '🇬🇪'), '996': ('Kirguistán', '🇰🇬'),
    '998': ('Uzbekistán', '🇺🇿'), '1809': ('República Dominicana', '🇩🇴'), '1829': ('República Dominicana', '🇩🇴'),
    '1849': ('República Dominicana', '🇩🇴'), '1787': ('Puerto Rico', '🇵🇷'), '1939': ('Puerto Rico', '🇵🇷'),
  };
}
