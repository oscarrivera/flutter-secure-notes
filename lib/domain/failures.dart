/// Failures of the application layer. Callers map them to UI copy.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class InvalidPinFailure extends AppFailure {
  const InvalidPinFailure() : super('El PIN debe tener exactamente 6 dígitos.');
}

final class PinMismatchFailure extends AppFailure {
  const PinMismatchFailure() : super('PIN incorrecto.');
}

final class PinAlreadySetFailure extends AppFailure {
  const PinAlreadySetFailure() : super('Ya hay un PIN configurado.');
}

final class PinNotSetFailure extends AppFailure {
  const PinNotSetFailure() : super('No hay un PIN configurado.');
}

final class LockoutFailure extends AppFailure {
  LockoutFailure(this.remaining)
      : super(
          'Demasiados intentos. Espera ${remaining.inSeconds} s.',
        );

  final Duration remaining;
}

final class LockedFailure extends AppFailure {
  const LockedFailure() : super('La sesión está bloqueada.');
}

final class NoteNotFoundFailure extends AppFailure {
  const NoteNotFoundFailure() : super('Nota no encontrada.');
}

final class CryptoFailure extends AppFailure {
  const CryptoFailure([super.message = 'Fallo de cifrado o integridad.']);
}
