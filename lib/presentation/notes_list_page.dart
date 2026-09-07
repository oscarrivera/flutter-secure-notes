import 'package:flutter/material.dart';

import '../application/lock_service.dart';
import '../application/notes_service.dart';
import '../domain/failures.dart';
import '../domain/note.dart';
import 'note_editor_page.dart';

class NotesListPage extends StatefulWidget {
  const NotesListPage({
    super.key,
    required this.notes,
    required this.lock,
    required this.onLock,
  });

  final NotesService notes;
  final LockService lock;
  final VoidCallback onLock;

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  late Future<List<Note>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.notes.list();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.notes.list();
    });
  }

  String _format(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _create() async {
    try {
      final note = await widget.notes.create();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteEditorPage(notes: widget.notes, note: note),
        ),
      );
      await _reload();
    } on AppFailure catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      widget.onLock();
    }
  }

  Future<void> _open(Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorPage(notes: widget.notes, note: note),
      ),
    );
    await _reload();
  }

  Future<void> _delete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: Text(
          note.title.isEmpty ? '¿Eliminar esta nota?' : '¿Eliminar «${note.title}»?',
        ),
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
      await widget.notes.delete(note.id);
      await _reload();
    } on AppFailure catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas cifradas'),
        actions: [
          IconButton(
            tooltip: 'Bloquear',
            onPressed: () {
              widget.lock.lock();
              widget.onLock();
            },
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'Nueva nota',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Note>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            final msg = snap.error is AppFailure
                ? (snap.error! as AppFailure).message
                : 'Error al cargar';
            return Center(child: Text(msg));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snap.data!;
          if (notes.isEmpty) {
            return const Center(child: Text('No hay notas.'));
          }
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final note = notes[i];
              final title = note.title.trim().isEmpty ? 'Sin título' : note.title;
              return ListTile(
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_format(note.updatedAt)),
                onTap: () => _open(note),
                trailing: IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(note),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
