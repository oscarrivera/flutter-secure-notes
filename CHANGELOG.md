# Changelog

## 0.1.0

- MVP local: alta de PIN, desbloqueo, CRUD de notas.
- AES-256-GCM en cuerpos; DEK en almacén seguro de plataforma.
- PBKDF2-HMAC-SHA256 para el PIN; lockout 5 × 30 s; idle 2 min.
- Tests de dominio/aplicación ejecutables con `dart test`.
