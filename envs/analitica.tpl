# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: analitica  bd=supabase-pg  grupo=pesada  alta_privada=si
COMPOSE_PROJECT_NAME=mvp-analitica
BI_HOST={{HOST}}
POSTGRES_HOST={{DB_HOST}}
POSTGRES_USERNAME=metabase_app
POSTGRES_PASSWORD={{DB_PASSWORD}}
MB_ENCRYPTION_SECRET_KEY={{GEN:b64-32}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
DB_HOST={{DB_HOST}}
DB_NAME={{DB_NAME}}
DB_PASSWORD={{DB_PASSWORD}}
DB_SSLMODE=disable
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
