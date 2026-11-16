import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

class AgendaTab extends StatefulWidget {
  const AgendaTab({super.key, required this.onCall});
  final ValueChanged<String> onCall;
  @override
  State<AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<AgendaTab> {
  final _search = TextEditingController();
  final app = AppController.I;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit([Contact? c]) => showDialog(context: context, builder: (_) => ContactDialog(contact: c));

  @override
  Widget build(BuildContext context) {
    final list = app.contacts.search(_search.text);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Row(children: [
          const Expanded(child: Text('Agenda de Contactos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          Tactile(onTap: _edit, child: const Text('+ Nuevo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NxColors.goldDark))),
          const SizedBox(width: 10),
          const Text('Directorio Local', style: TextStyle(fontSize: 11, color: NxColors.gray400)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Buscar por nombre, empresa o extensión...',
            fillColor: NxColors.surface,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(children: [
              const Icon(Icons.people_outline, size: 32, color: NxColors.gray400),
              const SizedBox(height: 8),
              Text(app.contacts.contacts.isEmpty ? 'La agenda está vacía' : 'Sin resultados', style: const TextStyle(color: NxColors.gray500, fontSize: 12)),
            ]),
          ),
        for (final c in list) ...[
          _ContactRow(contact: c, onCall: () => widget.onCall(c.number), onEdit: () => _edit(c), onFavorite: () => app.contacts.toggleFavorite(c)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onCall, required this.onEdit, required this.onFavorite});
  final Contact contact;
  final VoidCallback onCall, onEdit, onFavorite;

  @override
  Widget build(BuildContext context) => Tactile(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: NxColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: NxColors.border)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(contact.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 5),
                  Tactile(
                    onTap: onFavorite,
                    child: Text(contact.favorite ? '★' : '☆', style: TextStyle(fontSize: 12, color: contact.favorite ? NxColors.gold : NxColors.gray400)),
                  ),
                ]),
                if (contact.company.isNotEmpty) Text(contact.company, style: const TextStyle(fontSize: 11, color: NxColors.gray500)),
                const SizedBox(height: 2),
                Text(contact.number, style: const TextStyle(fontFamily: kMono, fontSize: 12, color: NxColors.gray700)),
              ]),
            ),
            NxButton(label: 'Llamar', tone: NxTone.dark, height: 32, radius: 12, onTap: onCall),
          ]),
        ),
      );
}

class ContactDialog extends StatefulWidget {
  const ContactDialog({super.key, this.contact, this.initialNumber});
  final Contact? contact;
  final String? initialNumber;
  @override
  State<ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<ContactDialog> {
  final app = AppController.I;
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _number = TextEditingController(text: widget.contact?.number ?? widget.initialNumber ?? '');
  late final _company = TextEditingController(text: widget.contact?.company ?? '');
  late bool _fav = widget.contact?.favorite ?? false;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _number.text.trim().isEmpty) return;
    final c = widget.contact ?? app.contacts.create();
    c
      ..name = _name.text.trim()
      ..number = _number.text.trim()
      ..company = _company.text.trim()
      ..favorite = _fav;
    await app.contacts.upsert(c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.contact == null ? 'Nuevo contacto' : 'Editar contacto'),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              style: const TextStyle(fontFamily: kMono),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9*#+ ]'))],
              decoration: const InputDecoration(labelText: 'Número / extensión'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _company, decoration: const InputDecoration(labelText: 'Empresa / departamento')),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _fav,
              onChanged: (v) => setState(() => _fav = v),
              title: const Text('Favorito'),
            ),
          ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(children: [
            if (widget.contact != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: NxColors.red),
                onPressed: () async {
                  await app.contacts.remove(widget.contact!);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Eliminar'),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: NxColors.muted))),
            const SizedBox(width: 8),
            SizedBox(width: 110, child: DarkButton(height: 38, fontSize: 13, label: 'Guardar', onPressed: _save)),
          ]),
        ],
      );
}
