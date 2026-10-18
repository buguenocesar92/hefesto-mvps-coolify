# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: basedatos  bd=postgres-local  grupo=pesada  alta_privada=si
SECRET_KEY={{GEN:b64-32}}
DATABASE_PASSWORD={{GEN:b64-32}}
REDIS_PASSWORD={{GEN:hex64}}
BASEROW_PUBLIC_URL={{URL}}
INITIAL_SETUP_COMPLETE=false
# publicar: INITIAL_SETUP_COMPLETE=true
APP_URL={{URL}}
APP_HOST={{HOST}}
