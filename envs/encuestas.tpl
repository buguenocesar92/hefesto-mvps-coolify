# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: encuestas  bd=mariadb-local  grupo=media  alta_privada=no
COMPOSE_PROJECT_NAME=mvp-encuestas
VOLUME_PREFIX=mvp-encuestas
SURVEY_HOST={{HOST}}
DB_PASSWORD={{GEN:hex64}}
DB_ROOT_PASSWORD={{GEN:hex64}}
ADMIN_EMAIL={{ADMIN_EMAIL}}
ADMIN_PASSWORD={{GEN:hex96}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
