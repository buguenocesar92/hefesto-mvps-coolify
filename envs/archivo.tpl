# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: archivo  bd=supabase-pg  grupo=media  alta_privada=no
COMPOSE_PROJECT_NAME=mvp-archivo
VOLUME_PREFIX=mvp-archivo
ARCHIVE_HOST={{HOST}}
ADMIN_EMAIL={{ADMIN_EMAIL}}
ADMIN_PASSWORD={{GEN:hex64}}
PAPERLESS_SECRET_KEY={{GEN:hex64}}
BROKER_PASSWORD={{GEN:hex64}}
POSTGRES_HOST={{DB_HOST}}
POSTGRES_USERNAME=mvp_archivo_app
POSTGRES_PASSWORD={{GEN:hex64}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
DB_HOST={{DB_HOST}}
DB_NAME={{DB_NAME}}
DB_PASSWORD={{DB_PASSWORD}}
DB_SSLMODE=disable
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
