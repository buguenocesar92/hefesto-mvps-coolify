# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: enlaces  bd=supabase-pg  grupo=liviana  alta_privada=si
COMPOSE_PROJECT_NAME=mvp-enlaces
POSTGRES_HOST={{DB_HOST}}
POSTGRES_USERNAME=mvp_enlaces_app
POSTGRES_PASSWORD={{GEN:hex64}}
LINKS_HOST={{HOST}}
PANEL_HOST={{HOST:panel-enlaces}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
TRUSTED_PROXIES=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
DB_HOST={{DB_HOST}}
DB_NAME={{DB_NAME}}
DB_PASSWORD={{DB_PASSWORD}}
DB_SSLMODE=disable
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
