# Variables pendientes

Las variables que la tabla de deducción no resuelve quedan como
`{{PENDIENTE}}` en la plantilla. `render_env` las anuncia y
`desplegar.sh` marca la app como `NECESITA_DATOS`.

## SQL

El kit (plan B) crea un rol por app y le inyecta la contraseña con
`\\set app_pass '$db_pass'` (variable psql). Por ahora este script
deja la sustitución en `\set app_pass '$db_pass'`; ajustar si el
kit usa `app_user`/`app_pass` con otra convención.

## APP_KEY (activos): formato 'base64:+base64-32' ambiguo; queda PENDIENTE
## LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID (ia-trazas): formato 'copia-de-MINIO_ROOT_USER' sin equivalente automático; queda PENDIENTE
## LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID (ia-trazas): formato 'copia-de-MINIO_ROOT_USER' sin equivalente automático; queda PENDIENTE
## ia-trazas · CLICKHOUSE_USER · no reconocido por la tabla de deducción
## ia-trazas · MINIO_ROOT_USER · no reconocido por la tabla de deducción
## ia-trazas · LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID · no reconocido por la tabla de deducción
## ia-trazas · LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID · no reconocido por la tabla de deducción
## sinsímbolos) (observabilidad): formato 'sin' no soportado; queda PENDIENTE
## respaldos · KOPIA_STORAGE_TYPE · no reconocido por la tabla de deducción
## respaldos · KOPIA_S3_ENDPOINT · credencial externa
## respaldos · KOPIA_S3_REGION · credencial externa
## respaldos · KOPIA_S3_ACCESS_KEY · credencial externa
## respaldos · KOPIA_S3_SECRET_ACCESS_KEY · credencial externa
## respaldos · KOPIA_TLS_FINGERPRINT · no reconocido por la tabla de deducción
## gateway-start.sh:4) (secretos): formato 'gateway-start.sh:4)' no soportado; queda PENDIENTE
## ops/start.sh:4) (utilidades): formato 'ops/start.sh:4)' no soportado; queda PENDIENTE
## SALTED_PASS (vigilancia): formato 'base64(salt32+pbkdf2_sha256(clave' no soportado; queda PENDIENTE
## salt (vigilancia): formato 'salt' no soportado; queda PENDIENTE
## 100000))(scripts/configure.py:7-8) (vigilancia): formato '100000))' no soportado; queda PENDIENTE
## APP_KEY (wiki): formato 'base64:+base64-32' ambiguo; queda PENDIENTE
## ordenia · DATABASE_URL · no reconocido por la tabla de deducción
## ordenia · N8N_INGEST_TOKEN · credencial externa
## ordenia · META_VERIFY_TOKEN · credencial externa
## ordenia · META_ACCESS_TOKEN · credencial externa
## ordenia · WHATSAPP_PHONE_NUMBER_ID · credencial externa

---

Total de plantillas: 54
Líneas {{PENDIENTE}}: 15
