import 'dart:convert';
import 'dart:typed_data';

import '../domain/failures.dart';
import '../domain/pin.dart';
import '../domain/repositories.dart';
import '../infrastructure/encrypted_notes_store.dart';
import '../infrastructure/secure_key_store.dart';

abstract final class VaultKeys {
  static const pin = 'pin.v1';
  static const dek = 'dek.v1';
  static const failures = 'pin.failures';
  static const lockoutUntil = 'pin.lockoutUntil';
}

/// Idle auto-lock. Default timeout: 2 minutes. Unit-testable via [Clock].
class IdleLock {
  IdleLock({
    required this.clock,
    this.timeout = const Duration(minutes: 2),
  });

  final Clock clock;
  final Duration timeout;
  DateTime? _lastActivity;

  void recordActivity() {
    _lastActivity = clock.now();
  }

  void clear() {
    _lastActivity = null;
  }

  bool get shouldLock {
    final last = _lastActivity;
    if (last == null) {
      return false;
    }
    return clock.now().difference(last) >= timeout;
  }
}

/// PIN gate, lockout, session DEK, idle lock.
class LockService {
  LockService({
    required SecureKeyStore keys,
    required Clock clock,
    PinKdf kdf = const PinKdf(),
    this.maxAttempts = 5,
    this.lockoutDuration = const Duration(seconds: 30),
    Duration idleTimeout = const Duration(minutes: 2),
  })  : _keys = keys,
        _clock = clock,
        _kdf = kdf,
        idle = IdleLock(clock: clock, timeout: idleTimeout);

  static const pinLength = PinPolicy.length;

  final SecureKeyStore _keys;
  final Clock _clock;
  final PinKdf _kdf;
  final int maxAttempts;
  final Duration lockoutDuration;
  final IdleLock idle;

  Clock get clock => _clock;

  Uint8List? _dek;
  int _failures = 0;
  DateTime? _lockoutUntil;
  bool _throttleLoaded = false;

  bool get isUnlocked => _dek != null;

  /// In-memory DEK. Null when locked. Caller must not persist this.
  List<int>? get dataKey => _dek == null ? null : Uint8List.fromList(_dek!);

  Future<bool> hasPin() async {
    final raw = await _keys.read(VaultKeys.pin);
    return raw != null && raw.isNotEmpty;
  }

  Future<void> setInitialPin(String pin) async {
    if (!PinPolicy.isValid(pin)) {
      throw const InvalidPinFailure();
    }
    if (await hasPin()) {
      throw const PinAlreadySetFailure();
    }
    final record = await _kdf.hash(pin);
    await _keys.write(VaultKeys.pin, record.encode());
    final dek = await newDek();
    await _keys.write(VaultKeys.dek, base64Encode(dek));
    await _resetThrottle();
    _setSession(dek);
  }

  Future<void> unlock(String pin) async {
    await _loadThrottle();
    _throwIfLockedOut();
    if (!PinPolicy.isValid(pin)) {
      throw const InvalidPinFailure();
    }
    final raw = await _keys.read(VaultKeys.pin);
    if (raw == null || raw.isEmpty) {
      throw const PinNotSetFailure();
    }
    final record = PinRecord.decode(raw);
    final ok = await _kdf.verify(pin, record);
    if (!ok) {
      await _registerFailure();
      return;
    }
    await _resetThrottle();
    final dekRaw = await _keys.read(VaultKeys.dek);
    if (dekRaw == null) {
      throw const CryptoFailure('Falta la clave de datos.');
    }
    _setSession(Uint8List.fromList(base64Decode(dekRaw)));
  }

  void lock() {
    _dek?.fillRange(0, _dek!.length, 0);
    _dek = null;
    idle.clear();
  }

  void recordActivity() {
    if (isUnlocked) {
      idle.recordActivity();
    }
  }

  void lockIfIdle() {
    if (isUnlocked && idle.shouldLock) {
      lock();
    }
  }

  Duration? lockoutRemaining() {
    final until = _lockoutUntil;
    if (until == null) {
      return null;
    }
    final left = until.difference(_clock.now());
    if (left <= Duration.zero) {
      return null;
    }
    return left;
  }

  void _setSession(Uint8List dek) {
    _dek = dek;
    idle.recordActivity();
  }

  void _throwIfLockedOut() {
    final left = lockoutRemaining();
    if (left != null) {
      throw LockoutFailure(left);
    }
    _lockoutUntil = null;
  }

  Future<void> _registerFailure() async {
    _failures += 1;
    if (_failures >= maxAttempts) {
      _lockoutUntil = _clock.now().add(lockoutDuration);
      _failures = 0;
      await _persistThrottle();
      throw LockoutFailure(lockoutDuration);
    }
    await _persistThrottle();
    throw const PinMismatchFailure();
  }

  Future<void> _loadThrottle() async {
    if (_throttleLoaded) {
      return;
    }
    _throttleLoaded = true;
    _failures = int.tryParse(await _keys.read(VaultKeys.failures) ?? '') ?? 0;
    final until = await _keys.read(VaultKeys.lockoutUntil);
    if (until != null && until.isNotEmpty) {
      _lockoutUntil = DateTime.tryParse(until);
    }
  }

  Future<void> _persistThrottle() async {
    await _keys.write(VaultKeys.failures, '$_failures');
    final until = _lockoutUntil;
    if (until == null) {
      await _keys.delete(VaultKeys.lockoutUntil);
    } else {
      await _keys.write(VaultKeys.lockoutUntil, until.toIso8601String());
    }
  }

  Future<void> _resetThrottle() async {
    _failures = 0;
    _lockoutUntil = null;
    _throttleLoaded = true;
    await _persistThrottle();
  }
}
