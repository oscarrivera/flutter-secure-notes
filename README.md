# Notas cifradas

Aplicación Flutter de notas locales cifradas. Sin backend, sin cuenta, sin sincronización.

El PIN de 6 dígitos autentica la sesión. El cuerpo de cada nota se cifra con AES-256-GCM. La clave de datos (DEK) vive en el almacén seguro de la plataforma (`flutter_secure_storage`: Android Keystore / iOS Keychain).

## Arquitectura

Capas sin fugas de UI hacia el dominio:

```
lib/
  main.dart
  app.dart                          # composición, cableado de producción
  domain/                           # entidades, PIN/KDF, fallos, puertos
  application/                      # LockService, IdleLock, NotesService
  infrastructure/                   # KeyStore, AES-GCM, blob JSON
  presentation/                     # lock, lista, editor
test/
  pin_test.dart
  notes_service_test.dart
```

Dependencias cruzadas: `presentation` → `application` → `domain`. `infrastructure` implementa puertos usados por `application`. Los tests de dominio/aplicación no importan Flutter.

## Cómo ejecutar

Requisitos: Flutter 3.19+ (Dart ≥ 3.3).

Si faltan los directorios de plataforma (iOS, etc.):

```bash
flutter create . --project-name flutter_secure_notes --org com.oscarrivera --platforms=android,ios
```

Eso no debe pisar `lib/` ni el `AndroidManifest.xml` de este repositorio (sin permiso `INTERNET`).

```bash
flutter pub get
flutter run
```

Tests de dominio (sin widgets; no hace falta emulador):

```bash
dart test
```

Si `dart pub get` exige el SDK de Flutter, usa `flutter pub get` y después `dart test`.

El manifiesto de Android no declara `INTERNET`. Hot reload en debug puede requerir ese permiso; no se añade a propósito.

## Limitaciones (por diseño)

- No hay sync ni backup en la nube.
- No hay recuperación de PIN. Si lo olvidas, el contenido queda inaccesible.
- No hay modo web. El almacén de notas usa `dart:io`.
- Los títulos y fechas van en claro en el fichero de notas; solo el cuerpo va cifrado.
- Un PIN de 6 dígitos no es una contraseña. Es un cerrojo de sesión. Ver [SECURITY.md](SECURITY.md).

## Modelo de amenaza (resumen)

| Escenario | Qué cubre esta app |
| --- | --- |
| Teléfono robado, no root, bloqueo de sistema activo | PIN de la app + Keystore/Keychain + cifrado del cuerpo. El ladrón sin desbloquear el SO no extrae la DEK. |
| Dispositivo rooteado / jailbreak / backup forense con secretos de Keystore | Fuera de alcance. La DEK y el hash del PIN son extraíbles; el PIN (10⁶ valores) se fuerza en frío. |

No hay superficie de red: el manifiesto de Android no declara `INTERNET`.
