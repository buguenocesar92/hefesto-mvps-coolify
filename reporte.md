# Variables pendientes

Las variables que la tabla de deducción no resuelve quedan como `{{PENDIENTE}}` en la
plantilla. `render_env` las anuncia y `desplegar.sh` marca la app como `NECESITA_DATOS`
sin llamar a la API para ella.

Formato: una línea `## <slug> · <VAR> · <motivo>` por variable pendiente. Las líneas
`- rol por convención: …` no son pendientes.

## SQL

`supabase-sql.sh` fija `\set app_user` con el rol que crea el `sql/01-*.sql` del kit
(rama coolify) y `\set app_pass` con el `DB_PASSWORD` (hex64) de la app. Si el kit crea
el rol con `:'app_user'`, se usa la convención `mvp_<slug>_app`.

## respaldos · KOPIA_STORAGE_TYPE · no reconocido por la tabla de deducción
## respaldos · KOPIA_S3_ENDPOINT · credencial externa
## respaldos · KOPIA_S3_REGION · credencial externa
## respaldos · KOPIA_S3_ACCESS_KEY · credencial externa
## respaldos · KOPIA_S3_SECRET_ACCESS_KEY · credencial externa
## respaldos · KOPIA_TLS_FINGERPRINT · no reconocido por la tabla de deducción
## ordenia · DATABASE_URL · no reconocido por la tabla de deducción
## ordenia · N8N_INGEST_TOKEN · credencial externa
## ordenia · META_VERIFY_TOKEN · credencial externa
## ordenia · META_ACCESS_TOKEN · credencial externa
## ordenia · WHATSAPP_PHONE_NUMBER_ID · credencial externa

---

Total de plantillas: 54
Líneas {{PENDIENTE}}: 11
