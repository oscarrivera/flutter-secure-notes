# Seguridad

## Qué se guarda

| Dato | Dónde | Protección |
| --- | --- | --- |
| Hash del PIN | `flutter_secure_storage` | PBKDF2-HMAC-SHA256, 100_000 iteraciones, sal de 16 bytes, comparación en tiempo constante |
| DEK AES-256 | `flutter_secure_storage` | Keystore (Android) / Keychain (iOS) |
| Contador de fallos y fin de lockout | `flutter_secure_storage` | Evita resetear el bloqueo matando el proceso |
| Cuerpos de notas | Fichero JSON en documentos de la app | AES-256-GCM (nonce aleatorio + MAC) |
| Títulos y timestamps | Mismo fichero | **Texto claro** (metadatos) |

En tests, `InMemorySecureKeyStore` y `InMemoryStringStore` sustituyen la plataforma. No hay Keystore en `dart test`.

## KDF y cifrado

- PIN: PBKDF2-HMAC-SHA256 (`package:cryptography`), 256 bits de salida.
- Notas: AES-GCM 256 bits, una DEK aleatoria distinta del hash del PIN.
- El PIN no envuelve la DEK. El PIN es un cerrojo de aplicación; la DEK la guarda el almacén de la plataforma.

Un PIN de 6 dígitos tiene ~20 bits. El KDF no lo convierte en una contraseña fuerte. El lockout (5 fallos → 30 s) solo frena ataques en línea contra la UI.

## Lockout e idle

- 5 PIN incorrectos: bloqueo de 30 s (también el PIN correcto). Persistido.
- Idle: 2 minutos sin actividad (`IdleLock` en la capa de aplicación). El `RootGate` registra punteros y comprueba cada 5 s; al volver de background se reevalúa.

## Android `FLAG_SECURE`

Pendiente / plataforma. No hay method channel. Para impedir capturas de pantalla hay que poner `WindowManager.LayoutParams.FLAG_SECURE` en la `Activity` (o equivalente iOS `isSecureTextEntry` / `screen capture` notifications). Queda fuera de este MVP.

El manifiesto sí desactiva backup (`android:allowBackup="false"`). No declara `INTERNET`.

## Amenazas

**Teléfono robado, sin root, SO bloqueado.** El atacante no entra en Keystore ni en el fichero de la app. Esta es la hipótesis de diseño.

**Root / jailbreak / depuración con el proceso vivo.** La DEK está en memoria mientras la sesión está abierta. Tras `lock()`, se intenta poner a cero el buffer. No es una garantía frente a un atacante con el mismo UID.

**Copia del fichero `notes_v1.json` sin la DEK.** Los cuerpos no son recuperables (AES-GCM). Los títulos sí.

**Fuerza bruta del hash de PIN extraído.** Factible. No uses este PIN como secreto de alto valor.

## Fuera de alcance

Analytics, crash reporting, red, cuentas, sync, backup cloud, share sheet, widgets, notificaciones.
