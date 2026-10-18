# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: wiki  bd=mariadb-local  grupo=media  alta_privada=si
COMPOSE_PROJECT_NAME=mvp-wiki
DB_VOLUME=mvp-wiki-db
CONFIG_VOLUME=mvp-wiki-config
WIKI_HOST={{HOST}}
APP_KEY={{GEN:laravel}}
DB_PASSWORD={{GEN:hex64}}
DB_ROOT_PASSWORD={{GEN:hex64}}
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
