import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/links.dart';
import '../core/updates.dart';
import 'logo.dart';
import 'splash.dart' show kBuild;
import 'theme.dart';
import 'widgets.dart';

/// Autor de la aplicación (sello personal: se mantiene aunque el código sea abierto).
const kAuthorName = 'Yandry Hernández Acosta';
const kAuthorLinkedIn = 'https://www.linkedin.com/in/yandryhn/';
const kRepoUrl = 'https://github.com/Noryxs-SoftPhone/Noryxs-SoftPhone';

/// Fecha de compilación (la pone la CI o el script de compilación con --dart-define=BUILD_DATE).
const kBuildDate = String.fromEnvironment('BUILD_DATE', defaultValue: '');

/// Ajustes › Acerca de: la app, su compilación, su autor, tecnología, privacidad y licencias.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static String get _platform {
    final os = Platform.isMacOS
        ? 'macOS'
        : Platform.isWindows
            ? 'Windows'
            : Platform.isLinux
                ? 'Linux'
                : Platform.isIOS
                    ? 'iOS'
                    : Platform.operatingSystem;
    final v = Platform.operatingSystemVersion.replaceAll(RegExp(r'\s+'), ' ');
    return '$os · $v';
  }

  static String get _dart => Platform.version.split(' ').first;
  static String get _build => kBuild.length > 10 ? kBuild.substring(0, 10) : kBuild;

  /// Texto para soporte: versión, compilación, sistema y líneas.
  static String supportInfo() {
    final app = AppController.I;
    final b = StringBuffer()
      ..writeln('NORYXS $kAppVersion (build $_build${kBuildDate.isEmpty ? '' : ', $kBuildDate'})')
      ..writeln('${tr('Sistema')}: $_platform')
      ..writeln('Dart $_dart · PJSIP 2.17 · whisper.cpp 1.9.5')
      ..writeln('${tr('Transcripción')}: ${app.transcripts.available ? tr('disponible') : tr('no disponible')}');
    for (final l in app.lines.lines) {
      b.writeln('${tr('Línea {0}', [l.number])}: ${l.extension} @ ${l.account.server} (${l.account.transportLabel}) · ${l.reg.label}');
    }
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppController.I;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 20), children: [
      // ---- La app
      Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2C2D33), Color(0xFF16171B), Color(0xFF0E0F12)]),
          border: Border.all(color: const Color(0x55C5A059)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(children: [
          const NoryxsLogo(size: 54, glow: 0.4),
          const SizedBox(height: 10),
          const GoldText('NORYXS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 5)),
          const SizedBox(height: 2),
          const Text('VIRTUAL SIP TERMINAL', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, letterSpacing: 3.5, color: Color(0xFF9A9CA3))),
          const SizedBox(height: 2),
          Text(tr('Teléfono IP virtual multilínea para FreePBX / Asterisk'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(tr('Versión {0}', [kAppVersion]),
                style: const TextStyle(fontFamily: kMono, fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // ---- Compilación
      _Card(title: tr('Compilación'), children: [
        _kv(tr('Versión'), kAppVersion),
        _kv(tr('Compilación'), _build),
        if (kBuildDate.isNotEmpty) _kv(tr('Fecha de compilación'), kBuildDate),
        _kv(tr('Sistema'), _platform),
        _kv(tr('Motor de voz'), 'PJSIP 2.17'),
        _kv(tr('Transcripción'), app.transcripts.available ? 'whisper.cpp 1.9.5 · Base' : tr('No disponible en este equipo')),
        _kv(tr('Interfaz'), 'Flutter · Dart $_dart'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: NxButton(
            label: tr('Copiar información'),
            icon: Icons.copy_rounded,
            iconColor: NxColors.goldDark,
            tone: NxTone.white,
            height: 30,
            radius: 10,
            fontSize: 11,
            tooltip: tr('Versión, sistema y estado de las líneas, para soporte'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: supportInfo()));
              app.showToast(tr('Información copiada al portapapeles'));
            },
          ),
        ),
      ]),

      // ---- Autor
      _Card(title: tr('Creado por'), children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [NxColors.gold, NxColors.goldDark]),
            ),
            child: const Text('YH', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(kAuthorName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(tr('Administrador de sistemas y telecomunicaciones'), style: TextStyle(fontSize: 11, color: NxColors.goldDark, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          tr('Ideó, diseñó y desarrolló NORYXS de principio a fin: el motor de telefonía en C sobre PJSIP, la aplicación de escritorio y la integración con FreePBX, a partir de la experiencia diaria administrando centralitas y puestos de trabajo.'),
          style: TextStyle(fontSize: 11.5, height: 1.45, color: NxColors.gray600),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _linkChip(Icons.work_outline_rounded, 'LinkedIn', kAuthorLinkedIn),
          _linkChip(Icons.code_rounded, tr('Código en GitHub'), kRepoUrl),
        ]),
      ]),

      // ---- Qué hace
      _Card(title: tr('Qué incluye'), children: [
        for (final f in [
          tr('Varias líneas SIP y varias llamadas a la vez, con retención, transferencias y conferencia a 3'),
          tr('Teclas BLF, aparcamiento, buzón, desvíos y No molestar por línea'),
          tr('Panel de cola de FreePBX con colas por línea'),
          tr('Grabación, reproducción y transcripción local de las llamadas'),
          tr('Historial con notas, etiquetas, pendientes de devolver y buscador'),
          tr('Reducción de ruido, volumen automático y aviso de mala conexión'),
          tr('WhatsApp con plantillas, clic para llamar y atajos globales'),
          tr('Castellano, catalán e inglés; modo claro y oscuro'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: 4, height: 4, decoration: BoxDecoration(color: NxColors.gold, shape: BoxShape.circle))),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: TextStyle(fontSize: 11.5, height: 1.35, color: NxColors.gray700))),
            ]),
          ),
      ]),

      // ---- Privacidad
      _Card(title: tr('Privacidad'), children: [
        Text(
          tr('Todo funciona en este ordenador y en la centralita: sin servidores externos ni nube. Las contraseñas se guardan en el almacén seguro del sistema; las notas y transcripciones, cifradas. El audio de las llamadas nunca sale del equipo.'),
          style: TextStyle(fontSize: 11.5, height: 1.45, color: NxColors.gray600),
        ),
      ]),

      // ---- Licencias
      _Card(title: tr('Licencias y agradecimientos'), children: [
        _kv('NORYXS', 'GPL-2.0-or-later'),
        _kv('PJSIP', 'GPL-2.0 · Teluu'),
        _kv('whisper.cpp / ggml', 'MIT · ggml.ai'),
        _kv('OpenSSL', 'Apache-2.0'),
        _kv('Opus', 'BSD'),
        _kv('Inter · JetBrains Mono', 'SIL OFL 1.1'),
        _kv('Flutter', 'BSD-3-Clause · Google'),
      ]),

      const SizedBox(height: 8),
      Center(
        child: Text('© ${DateTime.now().year} $kAuthorName · ${tr('Software libre (GPL)')}',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: NxColors.gray400)),
      ),
    ]);
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 11, color: NxColors.gray500))),
          Expanded(child: SelectableText(v, style: TextStyle(fontFamily: kMono, fontSize: 11, color: NxColors.text))),
        ]),
      );

  static Widget _linkChip(IconData icon, String label, String url) => Tactile(
        tooltip: url,
        onTap: () => openLink(url),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: NxColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: NxColors.goldBorder)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: NxColors.goldDark),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NxColors.goldDark)),
            const SizedBox(width: 4),
            Icon(Icons.north_east_rounded, size: 11, color: NxColors.gray400),
          ]),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: NxColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: NxColors.gray400)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );
}
