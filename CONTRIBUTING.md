# Contribuir

Cambios pequeños y revisables. Nada de refactors de paso.

## Tests

```bash
dart test
```

Cubre `domain` y `application` (PIN, KDF, lockout, idle, CRUD, cifrado en reposo). No hay tests de widgets.

## App

```bash
flutter pub get
flutter run
```

## Estilo

- `dart analyze` limpio en dominio/aplicación/infraestructura.
- Fallos de dominio: tipos en `failures.dart`, no `String` sueltos.
- No añadir red, analytics ni dependencias que pidan `INTERNET`.
