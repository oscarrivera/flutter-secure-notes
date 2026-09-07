import 'package:flutter/material.dart';

import '../application/notes_service.dart';
import '../domain/failures.dart';
import '../domain/note.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    required this.notes,
    required this.note,
  });

  final NotesService notes;
  final Note note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    setState(() => _saving = true);
    try {
      await widget.notes.update(
        widget.note.id,
        title: _title.text,
        body: _body.text,
      );
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await widget.notes.delete(widget.note.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          return;
        }
        try {
          await widget.notes.update(
            widget.note.id,
            title: _title.text,
            body: _body.text,
          );
        } on AppFailure {
          // Sesión bloqueada al salir: el último guardado explícito prevalece.
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nota'),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Guardar',
              onPressed: _persist,
              icon: const Icon(Icons.check),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  hintText: 'Título',
                  border: InputBorder.none,
                ),
                style: Theme.of(context).textTheme.titleLarge,
                  textCapitalization: TextCapitalization.sentences,
                ),
              const Divider(),
              Expanded(
                child: TextField(
                  controller: _body,
                  decoration: const InputDecoration(
                    hintText: 'Escribe aquí. El cuerpo se cifra en reposo.',
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
