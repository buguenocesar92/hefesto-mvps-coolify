# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: basedatos  bd=postgres-local  grupo=pesada  alta_privada=si

SECRET_KEY={{GEN:base64-32}}
DATABASE_PASSWORD={{GEN:base64-32}}
REDIS_PASSWORD={{GEN:hex64}}
BASEROW_PUBLIC_URL={{PENDIENTE}}
SMTP_READY=false
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
