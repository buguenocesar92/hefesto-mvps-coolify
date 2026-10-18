# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: firmas  bd=supabase-pg  grupo=media  alta_privada=si
DB_HOST={{DB_HOST}}
DB_PASSWORD={{DB_PASSWORD}}
PUBLIC_URL={{URL}}
SECRET_KEY_BASE={{GEN:hex96}}
ENCRYPTION_SECRET={{GEN:hex64}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
SMTP_HOST=smtp.resend.com
SMTP_USERNAME=resend
SMTP_PASSWORD={{RESEND_API_KEY}}
SMTP_FROM=no-reply@hefesto-studio.cl
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
SMTP_PORT=465
SMTP_READY=true
APP_URL={{URL}}
APP_HOST={{HOST}}
