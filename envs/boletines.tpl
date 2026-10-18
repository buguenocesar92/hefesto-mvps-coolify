# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: boletines  bd=supabase-pg  grupo=liviana  alta_privada=no
COMPOSE_PROJECT_NAME=mvp-boletines
VOLUME_PREFIX=mvp-boletines
NEWS_HOST={{HOST}}
POSTGRES_HOST={{DB_HOST}}
POSTGRES_USERNAME=mvp_boletines_app
POSTGRES_PASSWORD={{GEN:hex64}}
ADMIN_PASSWORD={{GEN:hex96}}
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
