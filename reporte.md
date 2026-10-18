# Variables pendientes

Las variables que la tabla de deducción no resuelve quedan como `{{PENDIENTE}}` en la
plantilla. `render_env` las anuncia y `desplegar.sh` marca la app como `NECESITA_DATOS`
sin llamar a la API para ella.

Formato: una línea `## <slug> · <VAR> · <motivo>` por variable pendiente. Las líneas
`- rol por convención: …` no son pendientes.

## SQL

`supabase-sql.sh` fija `\set app_user` con el rol que crea el `sql/01-*.sql` del kit
(rama coolify) y `\set app_pass` con el `DB_PASSWORD` (hex64) de la app. Si el kit crea
el rol con `:'app_user'`, se usa la convención `mvp_<slug>_app`. El SQL se emite con
envoltorio idempotente: `SELECT 'CREATE DATABASE …' WHERE NOT EXISTS (…) \gexec` para la
base y `DO $$ … IF NOT EXISTS (rol) … END $$` para envolver los `CREATE ROLE/USER` del kit,
así una segunda corrida de `aplicar-sql.sh` no rompe por duplicados.

## SMTP con Resend

Las plantillas que piden `SMTP_HOST`/`SMTP_USER`/`SMTP_USERNAME`/`SMTP_PASSWORD`/
`MAILER_DSN`/`MAILER_URL` ahora apuntan a Resend: `smtp.resend.com:465` con usuario
`resend`, contraseña `{{RESEND_API_KEY}}` (marcador que `render_env` resuelve desde
`$RESEND_ENV_FILE`, normalmente `~/.config/hefesto/resend.env`, modo 0600) y
`MAILER_DSN=smtps://resend:{{RESEND_API_KEY}}@smtp.resend.com:465`. La verificación
exige el token con `read:sensitive` para leer las envs del servicio Supabase, y se
guarda como secreto de root porque con `write` también puede ejecutar comandos en
los contenedores mediante scheduled tasks.

Excepciones (no se quiere enviar correo masivo desde un MVP):

- `marketing` (Mautic): `MAILER_DSN=null://null`, `SMTP_READY=false`.
- `boletines` (listmonk): `DELIVERY_ENABLED=false`, `SMTP_READY=false`.

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
