import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/failures.dart';
import '../domain/note.dart';
import '../domain/repositories.dart';

/// AES-256-GCM for note **bodies**. Titles and timestamps stay in plaintext
/// in the blob (needed for the list UI without a second index). See SECURITY.md.
class EncryptedNotesStore {
  EncryptedNotesStore({
    required StringStore records,
    AesGcm? aes,
  })  : _records = records,
        _aes = aes ?? AesGcm.with256bits();

  static const fileVersion = 1;

  final StringStore _records;
  final AesGcm _aes;

  Future<List<Note>> list(List<int> dek) async {
    final file = await _load();
    final out = <Note>[];
    for (final raw in file.notes) {
      out.add(await _decrypt(raw, dek));
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<Note?> getById(String id, List<int> dek) async {
    final file = await _load();
    for (final raw in file.notes) {
      if (raw['id'] == id) {
        return _decrypt(raw, dek);
      }
    }
    return null;
  }

  Future<void> save(Note note, List<int> dek) async {
    final file = await _load();
    final encrypted = await _encrypt(note, dek);
    final notes = [...file.notes];
    final idx = notes.indexWhere((n) => n['id'] == note.id);
    if (idx >= 0) {
      notes[idx] = encrypted;
    } else {
      notes.add(encrypted);
    }
    await _persist(_NotesFile(version: fileVersion, notes: notes));
  }

  Future<void> delete(String id) async {
    final file = await _load();
    final notes = file.notes.where((n) => n['id'] != id).toList();
    await _persist(_NotesFile(version: fileVersion, notes: notes));
  }

  Future<_NotesFile> _load() async {
    final raw = await _records.read();
    if (raw == null || raw.isEmpty) {
      return const _NotesFile(version: fileVersion, notes: []);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['version'] as int? ?? 0;
      if (version != fileVersion) {
        throw const CryptoFailure('Versión de almacén no soportada.');
      }
      final notes = (json['notes'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return _NotesFile(version: version, notes: notes);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const CryptoFailure('Almacén de notas ilegible.');
    }
  }

  Future<void> _persist(_NotesFile file) async {
    await _records.write(
      jsonEncode({
        'version': file.version,
        'notes': file.notes,
      }),
    );
  }

  Future<Map<String, dynamic>> _encrypt(Note note, List<int> dek) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(note.body),
      secretKey: SecretKey(dek),
      nonce: nonce,
    );
    return {
      'id': note.id,
      'title': note.title,
      'createdAt': note.createdAt.toUtc().toIso8601String(),
      'updatedAt': note.updatedAt.toUtc().toIso8601String(),
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<Note> _decrypt(Map<String, dynamic> raw, List<int> dek) async {
    try {
      final box = SecretBox(
        base64Decode(raw['cipherText'] as String),
        nonce: base64Decode(raw['nonce'] as String),
        mac: Mac(base64Decode(raw['mac'] as String)),
      );
      final clear = await _aes.decrypt(
        box,
        secretKey: SecretKey(dek),
      );
      return Note(
        id: raw['id'] as String,
        title: raw['title'] as String,
        body: utf8.decode(clear),
        createdAt: DateTime.parse(raw['createdAt'] as String).toUtc(),
        updatedAt: DateTime.parse(raw['updatedAt'] as String).toUtc(),
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const CryptoFailure();
    }
  }
}

class _NotesFile {
  const _NotesFile({required this.version, required this.notes});

  final int version;
  final List<Map<String, dynamic>> notes;
}

class FileStringStore implements StringStore {
  FileStringStore(this.file);

  final File file;

  @override
  Future<String?> read() async {
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }
}

/// 256-bit DEK helper (AES-GCM key).
Future<Uint8List> newDek() async {
  final key = await AesGcm.with256bits().newSecretKey();
  return Uint8List.fromList(await key.extractBytes());
}
