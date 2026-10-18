# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: flujos  bd=ninguna  grupo=liviana  alta_privada=no
NR_CREDENTIAL_SECRET={{GEN:hex64}}
NR_ADMIN_HASH={{GEN:bcrypt:NR_ADMIN_PASSWORD}}
NR_HTTP_HASH={{GEN:bcrypt:NR_HTTP_PASSWORD}}
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
