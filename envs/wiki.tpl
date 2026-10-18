# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: wiki  bd=mariadb-local  grupo=media  alta_privada=si

COMPOSE_PROJECT_NAME={{PENDIENTE}}
DB_VOLUME={{PENDIENTE}}
CONFIG_VOLUME={{PENDIENTE}}
WIKI_HOST={{PENDIENTE}}
APP_KEY={{GEN:base64:+base64-32}}
DB_PASSWORD={{DB_PASSWORD}}
DB_ROOT_PASSWORD={{GEN:hex64}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
