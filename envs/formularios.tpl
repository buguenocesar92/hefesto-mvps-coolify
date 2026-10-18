# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: formularios  bd=postgres-local  grupo=pesada  alta_privada=si

POSTGRES_PASSWORD={{GEN:hex64}}
AUTHZED_DATABASE_PASSWORD={{GEN:hex64}}
AUTHZED_TOKEN={{GEN:hex64}}
WEBAPP_URL={{PENDIENTE}}
NEXTAUTH_URL={{PENDIENTE}}
NEXTAUTH_SECRET={{GEN:hex64}}
ENCRYPTION_KEY={{GEN:hex64}}
CRON_SECRET={{GEN:hex64}}
HUB_API_KEY={{GEN:hex64}}
CUBEJS_API_SECRET={{GEN:hex64}}
OPERATOR_ACCOUNT_CREATED={{PENDIENTE}}
SMTP_READY={{PENDIENTE}}
MAIL_FROM={{PENDIENTE}}
SMTP_HOST={{PENDIENTE}}
SMTP_USER={{PENDIENTE}}
SMTP_PASSWORD={{GEN:hex64}}
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
