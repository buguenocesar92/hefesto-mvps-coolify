# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: respaldos  bd=ninguna  grupo=media  alta_privada=si

KOPIA_PASSWORD={{GEN:base64-48}}
KOPIA_SERVER_USERNAME={{PENDIENTE}}
KOPIA_SERVER_PASSWORD={{GEN:base64-32}}
KOPIA_SERVER_CONTROL_PASSWORD={{GEN:base64-32}}
KOPIA_STORAGE_TYPE={{PENDIENTE}}
KOPIA_S3_ENDPOINT={{PENDIENTE}}
KOPIA_S3_REGION={{PENDIENTE}}
KOPIA_S3_ACCESS_KEY={{GEN:hex64}}
KOPIA_S3_SECRET_ACCESS_KEY={{GEN:hex64}}
KOPIA_TLS_FINGERPRINT={{PENDIENTE}}
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada
