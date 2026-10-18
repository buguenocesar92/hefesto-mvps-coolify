# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: firmas  bd=supabase-pg  grupo=media  alta_privada=si
DB_HOST={{DB_HOST}}
DB_PASSWORD={{GEN:hex64}}
PUBLIC_URL={{URL}}
SECRET_KEY_BASE={{GEN:hex96}}
ENCRYPTION_SECRET={{GEN:hex64}}
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
SMTP_READY=false
SMTP_HOST=smtp.invalid
SMTP_USERNAME=desactivado
SMTP_PASSWORD=desactivado
SMTP_FROM=no-reply@hefesto-studio.cl
DB_NAME={{DB_NAME}}
DB_SSLMODE=disable
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
