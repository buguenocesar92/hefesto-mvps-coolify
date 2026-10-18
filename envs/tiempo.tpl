# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: tiempo  bd=mariadb-local  grupo=media  alta_privada=si

COMPOSE_PROJECT_NAME={{PENDIENTE}}
VOLUME_PREFIX={{PENDIENTE}}
DB_PASSWORD={{DB_PASSWORD}}
DB_ROOT_PASSWORD={{GEN:hex64}}
APP_SECRET={{GEN:hex64}}
TRUSTED_HOSTS={{PENDIENTE}}
ADMINMAIL={{PENDIENTE}}
ADMINPASS={{PENDIENTE}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
