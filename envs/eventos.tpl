# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: eventos  bd=supabase-pg  grupo=pesada  alta_privada=si
PUBLIC_URL={{URL}}
DB_HOST={{DB_HOST}}
DB_PASSWORD={{DB_PASSWORD}}
DJANGO_SECRET={{GEN:hex64}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
MAIL_FROM=no-reply@hefesto-studio.cl
SMTP_HOST=smtp.resend.com
SMTP_USER=resend
SMTP_PASSWORD={{RESEND_API_KEY}}
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
SMTP_PORT=465
SMTP_READY=true
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
