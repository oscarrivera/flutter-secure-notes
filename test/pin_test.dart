import 'package:flutter_secure_notes/domain/failures.dart';
import 'package:flutter_secure_notes/domain/pin.dart';
import 'package:test/test.dart';

void main() {
  const kdf = PinKdf(iterations: 32);

  group('PinPolicy', () {
    test('accepts exactly 6 digits', () {
      expect(PinPolicy.isValid('000000'), isTrue);
      expect(PinPolicy.isValid('123456'), isTrue);
      expect(PinPolicy.length, 6);
    });

    test('rejects other lengths and non-digits', () {
      expect(PinPolicy.isValid(''), isFalse);
      expect(PinPolicy.isValid('12345'), isFalse);
      expect(PinPolicy.isValid('1234567'), isFalse);
      expect(PinPolicy.isValid('12345a'), isFalse);
      expect(PinPolicy.isValid('12345 '), isFalse);
      expect(PinPolicy.isValid('12 456'), isFalse);
    });
  });

  group('PinKdf PBKDF2-HMAC-SHA256', () {
    test('same pin + salt yields the same hash', () async {
      const salt = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
      final a = await kdf.hash('123456', salt: salt);
      final b = await kdf.hash('123456', salt: salt);
      expect(a.hash, b.hash);
      expect(a.kdf, PinKdf.algorithmId);
      expect(a.iterations, 32);
    });

    test('random salt makes two hashes of the same pin differ', () async {
      final a = await kdf.hash('123456');
      final b = await kdf.hash('123456');
      expect(a.salt, isNot(equals(b.salt)));
      expect(a.hash, isNot(equals(b.hash)));
    });

    test('verify accepts the original pin and rejects another', () async {
      final record = await kdf.hash('654321');
      expect(await kdf.verify('654321', record), isTrue);
      expect(await kdf.verify('654322', record), isFalse);
      expect(await kdf.verify('000000', record), isFalse);
    });

    test('round-trips through JSON', () async {
      final record = await kdf.hash('111222');
      final restored = PinRecord.decode(record.encode());
      expect(await kdf.verify('111222', restored), isTrue);
    });
  });

  group('constantTimeEquals', () {
    test('compares equal and unequal lists', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  test('InvalidPinFailure is an AppFailure', () {
    const f = InvalidPinFailure();
    expect(f, isA<AppFailure>());
    expect(f.message, contains('6'));
  });
}
