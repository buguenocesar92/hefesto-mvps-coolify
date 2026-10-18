# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: crm  bd=mariadb-local  grupo=media  alta_privada=no
CRM_HOST={{HOST}}
DB_PASSWORD={{GEN:hex64}}
DB_ROOT_PASSWORD={{GEN:hex64}}
ADMIN_PASSWORD={{GEN:hex64}}
INSTANCE_ID={{GEN:hex64}}
CRON_KEY={{GEN:hex64}}
INITIAL_SETUP_COMPLETE=false
APP_URL={{URL}}
APP_HOST={{HOST}}
