# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: observabilidad  bd=postgres-local  grupo=pesada  alta_privada=si

POSTGRES_PASSWORD={{GEN:hex64}}
SIGNOZ_USER_ROOT_ENABLED={{PENDIENTE}}
SIGNOZ_USER_ROOT_EMAIL={{PENDIENTE}}
SIGNOZ_USER_ROOT_PASSWORD={{GEN:hex32}}
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
