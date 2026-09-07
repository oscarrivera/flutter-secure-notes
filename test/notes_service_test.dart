import 'package:flutter_secure_notes/application/lock_service.dart';
import 'package:flutter_secure_notes/application/notes_service.dart';
import 'package:flutter_secure_notes/domain/failures.dart';
import 'package:flutter_secure_notes/domain/pin.dart';
import 'package:flutter_secure_notes/domain/repositories.dart';
import 'package:flutter_secure_notes/infrastructure/encrypted_notes_store.dart';
import 'package:flutter_secure_notes/infrastructure/secure_key_store.dart';
import 'package:test/test.dart';

class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

class Harness {
  Harness({
    required this.keys,
    required this.records,
    required this.clock,
    required this.lock,
    required this.notes,
  });

  final InMemorySecureKeyStore keys;
  final InMemoryStringStore records;
  final FakeClock clock;
  final LockService lock;
  final NotesService notes;
}

Harness buildHarness() {
  final keys = InMemorySecureKeyStore();
  final records = InMemoryStringStore();
  final clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
  final lock = LockService(
    keys: keys,
    clock: clock,
    kdf: const PinKdf(iterations: 32),
  );
  final notes = NotesService(
    store: EncryptedNotesStore(records: records),
    lock: lock,
  );
  return Harness(
    keys: keys,
    records: records,
    clock: clock,
    lock: lock,
    notes: notes,
  );
}

void main() {
  const pin = '123456';

  group('LockService', () {
    test('first run sets pin and unlocks', () async {
      final h = buildHarness();
      expect(await h.lock.hasPin(), isFalse);
      await h.lock.setInitialPin(pin);
      expect(await h.lock.hasPin(), isTrue);
      expect(h.lock.isUnlocked, isTrue);
      expect(h.lock.dataKey, isNotNull);
    });

    test('rejects malformed pin on setup', () async {
      final h = buildHarness();
      await expectLater(
        h.lock.setInitialPin('12345'),
        throwsA(isA<InvalidPinFailure>()),
      );
    });

    test('cannot set pin twice', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      h.lock.lock();
      await expectLater(
        h.lock.setInitialPin('654321'),
        throwsA(isA<PinAlreadySetFailure>()),
      );
    });

    test('unlock with wrong pin then correct pin', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      h.lock.lock();
      expect(h.lock.isUnlocked, isFalse);
      await expectLater(
        h.lock.unlock('000000'),
        throwsA(isA<PinMismatchFailure>()),
      );
      await h.lock.unlock(pin);
      expect(h.lock.isUnlocked, isTrue);
    });

    test('five failures lock for 30 seconds', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      h.lock.lock();
      for (var i = 0; i < 4; i++) {
        await expectLater(
          h.lock.unlock('000000'),
          throwsA(isA<PinMismatchFailure>()),
        );
      }
      await expectLater(
        h.lock.unlock('000000'),
        throwsA(isA<LockoutFailure>()),
      );
      await expectLater(
        h.lock.unlock(pin),
        throwsA(isA<LockoutFailure>()),
      );
      h.clock.advance(const Duration(seconds: 29));
      await expectLater(
        h.lock.unlock(pin),
        throwsA(isA<LockoutFailure>()),
      );
      h.clock.advance(const Duration(seconds: 1));
      await h.lock.unlock(pin);
      expect(h.lock.isUnlocked, isTrue);
    });

    test('lockout survives a new LockService on the same store', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      h.lock.lock();
      for (var i = 0; i < 5; i++) {
        try {
          await h.lock.unlock('000000');
        } on AppFailure {
          // expected
        }
      }
      final lock2 = LockService(
        keys: h.keys,
        clock: h.clock,
        kdf: const PinKdf(iterations: 32),
      );
      await expectLater(
        lock2.unlock(pin),
        throwsA(isA<LockoutFailure>()),
      );
    });
  });

  group('IdleLock', () {
    test('locks after two minutes without activity', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      expect(h.lock.idle.shouldLock, isFalse);
      h.clock.advance(const Duration(minutes: 2));
      expect(h.lock.idle.shouldLock, isTrue);
      h.lock.lockIfIdle();
      expect(h.lock.isUnlocked, isFalse);
    });

    test('activity resets the idle window', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      h.clock.advance(const Duration(minutes: 1, seconds: 50));
      h.lock.recordActivity();
      h.clock.advance(const Duration(minutes: 1, seconds: 50));
      expect(h.lock.idle.shouldLock, isFalse);
      h.clock.advance(const Duration(seconds: 10));
      expect(h.lock.idle.shouldLock, isTrue);
    });
  });

  group('NotesService', () {
    test('refuses CRUD while locked', () async {
      final h = buildHarness();
      await expectLater(h.notes.list(), throwsA(isA<LockedFailure>()));
      await expectLater(h.notes.create(), throwsA(isA<LockedFailure>()));
    });

    test('create, list, update, delete', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      final created = await h.notes.create(title: 'Alfa', body: 'secreto');
      expect(created.title, 'Alfa');
      var all = await h.notes.list();
      expect(all, hasLength(1));
      expect(all.single.body, 'secreto');

      h.clock.advance(const Duration(seconds: 5));
      final updated = await h.notes.update(
        created.id,
        title: 'Beta',
        body: 'otro',
      );
      expect(updated.title, 'Beta');
      expect(updated.body, 'otro');
      expect(updated.updatedAt.isAfter(created.updatedAt), isTrue);

      all = await h.notes.list();
      expect(all.single.title, 'Beta');

      await h.notes.delete(created.id);
      expect(await h.notes.list(), isEmpty);
    });

    test('note body is not stored in plaintext', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      await h.notes.create(title: 'Visible', body: 'cuerpo-super-secreto');
      final blob = h.records.value!;
      expect(blob, contains('Visible'));
      expect(blob, isNot(contains('cuerpo-super-secreto')));
      expect(blob, contains('cipherText'));
    });

    test('idle lock blocks list', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      await h.notes.create(title: 'x');
      h.clock.advance(const Duration(minutes: 2));
      await expectLater(h.notes.list(), throwsA(isA<LockedFailure>()));
    });

    test('update of unknown id fails', () async {
      final h = buildHarness();
      await h.lock.setInitialPin(pin);
      await expectLater(
        h.notes.update('missing', title: 'n'),
        throwsA(isA<NoteNotFoundFailure>()),
      );
    });
  });
}
