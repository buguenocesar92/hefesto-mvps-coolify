# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: firmas  bd=supabase-pg  grupo=media  alta_privada=si

DB_HOST={{DB_HOST}}
DB_PASSWORD={{DB_PASSWORD}}
PUBLIC_URL={{PENDIENTE}}
SECRET_KEY_BASE={{GEN:hex128}}
ENCRYPTION_SECRET={{GEN:hex64}}
SUPABASE_DEDICATED_CONFIRMED={{PENDIENTE}}
SUPABASE_DATA_API_DISABLED={{PENDIENTE}}
INITIAL_SETUP_COMPLETE={{PENDIENTE}}
SMTP_READY={{PENDIENTE}}
SMTP_HOST={{PENDIENTE}}
SMTP_USERNAME={{PENDIENTE}}
SMTP_PASSWORD={{GEN:hex64}}
SMTP_FROM={{PENDIENTE}}
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
