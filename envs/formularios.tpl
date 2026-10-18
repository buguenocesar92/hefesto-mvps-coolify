# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: formularios  bd=postgres-local  grupo=pesada  alta_privada=si
POSTGRES_PASSWORD={{GEN:hex64}}
AUTHZED_DATABASE_PASSWORD={{GEN:hex64}}
AUTHZED_TOKEN={{GEN:hex64}}
WEBAPP_URL={{URL}}
NEXTAUTH_URL={{URL}}
NEXTAUTH_SECRET={{GEN:hex64}}
ENCRYPTION_KEY={{GEN:hex64}}
CRON_SECRET={{GEN:hex64}}
HUB_API_KEY={{GEN:hex64}}
CUBEJS_API_SECRET={{GEN:hex64}}
OPERATOR_ACCOUNT_CREATED=false
# publicar: OPERATOR_ACCOUNT_CREATED=true
MAIL_FROM=no-reply@hefesto-studio.cl
SMTP_HOST=smtp.resend.com
SMTP_USER=resend
SMTP_PASSWORD={{RESEND_API_KEY}}
SMTP_PORT=465
SMTP_READY=true
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
