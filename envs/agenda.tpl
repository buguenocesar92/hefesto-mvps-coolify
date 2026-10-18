# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: agenda  bd=mariadb-local  grupo=liviana  alta_privada=si

COMPOSE_PROJECT_NAME={{PENDIENTE}}
DB_VOLUME={{PENDIENTE}}
STORAGE_VOLUME={{PENDIENTE}}
AGENDA_HOST={{PENDIENTE}}
DB_PASSWORD={{DB_PASSWORD}}
DB_ROOT_PASSWORD={{GEN:hex64}}
ENCRYPTION_KEY={{GEN:hex64}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
