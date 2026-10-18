# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: metricas  bd=supabase-pg  grupo=liviana  alta_privada=si
DB_HOST={{DB_HOST}}
DB_PASSWORD={{GEN:hex64}}
APP_SECRET={{GEN:hex64}}
TWO_FACTOR_ENCRYPTION_KEY={{GEN:hex64}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
