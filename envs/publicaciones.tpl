# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: publicaciones  bd=mysql-local  grupo=media  alta_privada=si
MYSQL_ROOT_PASSWORD={{GEN:hex64}}
MYSQL_PASSWORD={{GEN:hex64}}
PUBLIC_URL={{URL}}
MAIL_FROM=no-reply@hefesto-studio.cl
SMTP_HOST=smtp.resend.com
SMTP_USERNAME=resend
SMTP_PASSWORD={{RESEND_API_KEY}}
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
SMTP_PORT=465
SMTP_READY=true
APP_URL={{URL}}
APP_HOST={{HOST}}
