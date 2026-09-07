import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// 6-digit PIN. Online lockout is enforced in the application layer; this
/// type only validates format. A 6-digit space is ~20 bits — see SECURITY.md.
abstract final class PinPolicy {
  static const length = 6;
  static final RegExp _digits = RegExp(r'^\d{6}$');

  static bool isValid(String pin) => _digits.hasMatch(pin);
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var acc = 0;
  for (var i = 0; i < a.length; i++) {
    acc |= a[i] ^ b[i];
  }
  return acc == 0;
}

class PinRecord {
  const PinRecord({
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.hash,
  });

  final String kdf;
  final int iterations;
  final List<int> salt;
  final List<int> hash;

  Map<String, Object> toJson() => {
        'kdf': kdf,
        'iterations': iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
      };

  factory PinRecord.fromJson(Map<String, dynamic> json) {
    return PinRecord(
      kdf: json['kdf'] as String,
      iterations: json['iterations'] as int,
      salt: base64Decode(json['salt'] as String),
      hash: base64Decode(json['hash'] as String),
    );
  }

  String encode() => jsonEncode(toJson());

  static PinRecord decode(String raw) {
    return PinRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// PBKDF2-HMAC-SHA256 via package `cryptography`.
///
/// Production default: 100_000 iterations, 16-byte salt, 256-bit output.
/// Tests should pass a low [iterations] value.
class PinKdf {
  const PinKdf({this.iterations = 100000, this.bits = 256});

  static const algorithmId = 'pbkdf2-hmac-sha256';
  static const saltLength = 16;

  final int iterations;
  final int bits;

  Pbkdf2 _algorithm(int iters) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iters,
        bits: bits,
      );

  Future<PinRecord> hash(String pin, {List<int>? salt}) async {
    final s = salt ?? _salt();
    final key = await _algorithm(iterations).deriveKeyFromPassword(
      password: pin,
      nonce: s,
    );
    return PinRecord(
      kdf: algorithmId,
      iterations: iterations,
      salt: s,
      hash: await key.extractBytes(),
    );
  }

  Future<bool> verify(String pin, PinRecord record) async {
    if (record.kdf != algorithmId) {
      return false;
    }
    final key = await _algorithm(record.iterations).deriveKeyFromPassword(
      password: pin,
      nonce: record.salt,
    );
    return constantTimeEquals(await key.extractBytes(), record.hash);
  }

  List<int> _salt() {
    final r = Random.secure();
    return List<int>.generate(saltLength, (_) => r.nextInt(256));
  }
}
