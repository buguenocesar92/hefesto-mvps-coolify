# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: ideas  bd=supabase-pg  grupo=liviana  alta_privada=si
DB_HOST={{DB_HOST}}
DB_PASSWORD={{DB_PASSWORD}}
JWT_SECRET={{GEN:hex96}}
BASE_URL={{URL}}
EMAIL_NOREPLY=no-reply@hefesto-studio.cl
SMTP_HOST=smtp.resend.com
SMTP_USERNAME=resend
SMTP_PASSWORD={{RESEND_API_KEY}}
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
SMTP_PORT=465
SMTP_READY=true
APP_URL={{URL}}
APP_HOST={{HOST}}
