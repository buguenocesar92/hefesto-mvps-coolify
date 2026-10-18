# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: agenda  bd=mariadb-local  grupo=liviana  alta_privada=si
COMPOSE_PROJECT_NAME=mvp-agenda
DB_VOLUME=mvp-agenda-db
STORAGE_VOLUME=mvp-agenda-storage
AGENDA_HOST={{HOST}}
DB_PASSWORD={{GEN:hex64}}
DB_ROOT_PASSWORD={{GEN:hex64}}
ENCRYPTION_KEY={{GEN:hex64}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
