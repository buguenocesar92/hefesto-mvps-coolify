# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: actas  bd=supabase-pg  grupo=liviana  alta_privada=si

DOMAIN={{PENDIENTE}}
DB_HOST={{DB_HOST}}
DB_PASSWORD={{DB_PASSWORD}}
SESSION_SECRET={{GEN:hex64}}
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
