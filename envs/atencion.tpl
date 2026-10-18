# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: atencion  bd=supabase-pg  grupo=pesada  alta_privada=si
COMPOSE_PROJECT_NAME=mvp-atencion
STORAGE_VOLUME=mvp-atencion-storage
REDIS_VOLUME=mvp-atencion-redis
CHAT_HOST={{HOST}}
SECRET_KEY_BASE={{GEN:hex96}}
REDIS_PASSWORD={{GEN:hex64}}
POSTGRES_HOST={{DB_HOST}}
POSTGRES_USERNAME=mvp_atencion_app
POSTGRES_PASSWORD={{GEN:hex64}}
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
