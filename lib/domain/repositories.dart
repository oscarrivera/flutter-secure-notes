/// Wall clock. Injected so lockout and idle timeout are unit-testable.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Opaque UTF-8 blob (encrypted notes file).
abstract class StringStore {
  Future<String?> read();

  Future<void> write(String value);
}

class InMemoryStringStore implements StringStore {
  InMemoryStringStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
