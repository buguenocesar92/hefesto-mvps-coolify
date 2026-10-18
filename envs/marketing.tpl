# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: marketing  bd=mysql-local  grupo=pesada  alta_privada=si

MARKETING_HOST={{PENDIENTE}}
ADMIN_EMAIL={{PENDIENTE}}
ADMIN_PASSWORD={{GEN:hex64}}
DB_PASSWORD={{DB_PASSWORD}}
DB_ROOT_PASSWORD={{GEN:hex64}}
TRUSTED_PROXIES={{PENDIENTE}}
MAIL_FROM={{PENDIENTE}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
