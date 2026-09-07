import '../domain/failures.dart';
import '../domain/note.dart';
import '../infrastructure/encrypted_notes_store.dart';
import 'lock_service.dart';

class NotesService {
  NotesService({
    required EncryptedNotesStore store,
    required LockService lock,
  })  : _store = store,
        _lock = lock;

  final EncryptedNotesStore _store;
  final LockService _lock;

  List<int> _requireKey() {
    _lock.lockIfIdle();
    final key = _lock.dataKey;
    if (key == null) {
      throw const LockedFailure();
    }
    return key;
  }

  Future<List<Note>> list() async {
    final key = _requireKey();
    _lock.recordActivity();
    return _store.list(key);
  }

  Future<Note?> getById(String id) async {
    final key = _requireKey();
    _lock.recordActivity();
    return _store.getById(id, key);
  }

  Future<Note> create({String title = '', String body = ''}) async {
    final key = _requireKey();
    final now = _lock.clock.now().toUtc();
    final note = Note(
      id: Note.newId(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    await _store.save(note, key);
    _lock.recordActivity();
    return note;
  }

  Future<Note> update(String id, {String? title, String? body}) async {
    final key = _requireKey();
    final existing = await _store.getById(id, key);
    if (existing == null) {
      throw const NoteNotFoundFailure();
    }
    final updated = existing.copyWith(
      title: title ?? existing.title,
      body: body ?? existing.body,
      updatedAt: _lock.clock.now().toUtc(),
    );
    await _store.save(updated, key);
    _lock.recordActivity();
    return updated;
  }

  Future<void> delete(String id) async {
    _requireKey();
    await _store.delete(id);
    _lock.recordActivity();
  }
}
