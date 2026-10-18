# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: analitica  bd=supabase-pg  grupo=pesada  alta_privada=si

COMPOSE_PROJECT_NAME={{PENDIENTE}}
BI_HOST={{PENDIENTE}}
POSTGRES_HOST={{PENDIENTE}}
POSTGRES_USERNAME={{PENDIENTE}}
POSTGRES_PASSWORD={{GEN:hex64}}
MB_ENCRYPTION_SECRET_KEY={{GEN:base64-32}}
SUPABASE_DEDICATED_CONFIRMED={{PENDIENTE}}
SUPABASE_DATA_API_DISABLED={{PENDIENTE}}
DB_HOST={{DB_HOST}}
DB_NAME={{DB_NAME}}
DB_PASSWORD={{DB_PASSWORD}}
DB_SSLMODE=disable
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
