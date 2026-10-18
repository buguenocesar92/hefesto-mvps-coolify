# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: marketing  bd=mysql-local  grupo=pesada  alta_privada=si
MARKETING_HOST={{HOST}}
ADMIN_EMAIL={{ADMIN_EMAIL}}
ADMIN_PASSWORD={{GEN:hex64}}
DB_PASSWORD={{GEN:hex64}}
DB_ROOT_PASSWORD={{GEN:hex64}}
TRUSTED_PROXIES=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
MAIL_FROM=no-reply@hefesto-studio.cl
MAILER_DSN=null://null
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
