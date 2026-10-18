# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: tiempo  bd=mariadb-local  grupo=media  alta_privada=si
COMPOSE_PROJECT_NAME=mvp-tiempo
VOLUME_PREFIX=mvp-tiempo
DB_PASSWORD={{GEN:hex64}}
DB_ROOT_PASSWORD={{GEN:hex64}}
APP_SECRET={{GEN:hex64}}
TRUSTED_HOSTS={{HOST}}
ADMINMAIL={{ADMIN_EMAIL}}
ADMINPASS={{GEN:hex96}}
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
