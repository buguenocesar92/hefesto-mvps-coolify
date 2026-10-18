# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: observabilidad  bd=postgres-local  grupo=pesada  alta_privada=si
POSTGRES_PASSWORD={{GEN:hex64}}
SIGNOZ_USER_ROOT_ENABLED=true
SIGNOZ_USER_ROOT_EMAIL={{ADMIN_EMAIL}}
SIGNOZ_USER_ROOT_PASSWORD={{GEN:hex32}}
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
