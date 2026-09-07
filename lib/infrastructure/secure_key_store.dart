/// String KV used for the PIN digest, DEK, and lockout counters.
///
/// Production: wrap `FlutterSecureStorage` (Android Keystore / iOS Keychain)
/// with [DelegatingSecureKeyStore] in `app.dart`.
/// Tests: [InMemorySecureKeyStore].
abstract class SecureKeyStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class InMemorySecureKeyStore implements SecureKeyStore {
  InMemorySecureKeyStore([Map<String, String>? seed]) : _data = {...?seed};

  final Map<String, String> _data;

  Map<String, String> get snapshot => Map.unmodifiable(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

/// Adapts any async string map (including FlutterSecureStorage) without
/// importing Flutter in this library.
class DelegatingSecureKeyStore implements SecureKeyStore {
  DelegatingSecureKeyStore({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<void> Function(String key) delete,
  })  : _read = read,
        _write = write,
        _delete = delete;

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  @override
  Future<String?> read(String key) => _read(key);

  @override
  Future<void> write(String key, String value) => _write(key, value);

  @override
  Future<void> delete(String key) => _delete(key);
}
