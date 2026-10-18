#!/usr/bin/env bash
# instalar-supabase.sh [--dry-run|--ejecutar]
# Crea o reusa el servicio Supabase de un clic en Coolify, fija la red interna,
# configura el SMTP de GoTrue con Resend, arranca el servicio y deja los secretos
# del servicio (service_role, anon, postgres) en archivos 0600.
# Por stdout solo imprime el uuid, el estado final y las rutas de los archivos.
set -euo pipefail
# shellcheck shell=bash
RAIZ_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comun.sh
source "$RAIZ_LIB/lib/comun.sh"
# shellcheck source=lib/coolify.sh
source "$RAIZ_LIB/lib/coolify.sh"

RESEND_ENV_FILE="${RESEND_ENV_FILE:-$HOME/.config/hefesto/resend.env}"
SUPABASE_KEY_FILE="${SUPABASE_KEY_FILE:-$HOME/.config/hefesto/supabase-service-key}"
SUPABASE_ANON_KEY_FILE="${SUPABASE_ANON_KEY_FILE:-$HOME/.config/hefesto/supabase-anon-key}"
SUPABASE_UUID_FILE="${SUPABASE_UUID_FILE:-$ESTADO_DIR/supabase.uuid}"
SUPABASE_POSTGRES_PASS="${SUPABASE_POSTGRES_PASS:-$ESTADO_DIR/supabase-postgres.pass}"
SERVICE_NAME="mvp-supabase"
ESPERA_SONDEO="${ESPERA_SONDEO:-10}"
MAX_INTENTOS_INICIO="${MAX_INTENTOS_INICIO:-60}"

uso() {
  cat >&2 <<USO
uso: $(basename "$0") [--dry-run|--ejecutar]
  --dry-run   imprime el plan y no hace POST ni PATCH (defecto)
  --ejecutar  llama a la API de Coolify y deja los secretos en disco
USO
}

MODO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODO="${MODO:-dry}"; shift ;;
    --ejecutar) MODO="${MODO:-ejecutar}"; shift ;;
    -h|--help) uso; exit 0 ;;
    *) error "argumento desconocido: $1"; uso; exit 2 ;;
  esac
done
[ -n "$MODO" ] || MODO="dry"

# leer_resend_api_key: toma el valor de RESEND_API_KEY del archivo $RESEND_ENV_FILE;
# si no existe, el primer valor que empiece con re_ (línea con formato CLAVE=valor). Nunca imprime la clave.
leer_resend_api_key() {
  [ -f "$RESEND_ENV_FILE" ] || { error "no encuentro la API key de Resend en $RESEND_ENV_FILE"; return 1; }
  local k=""
  k="$(grep -E '^RESEND_API_KEY=' "$RESEND_ENV_FILE" | head -1 | cut -d= -f2- || true)"
  if [ -z "$k" ]; then
    k="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=re_' "$RESEND_ENV_FILE" | head -1 | cut -d= -f2- || true)"
  fi
  [ -n "$k" ] || { error "no encuentro la API key de Resend en $RESEND_ENV_FILE"; return 1; }
  printf '%s' "$k"
}

# escribir_secreto <ruta> <valor>: crea el archivo con umask 077 y permisos 0600 atómicos.
escribir_secreto() {
  local ruta="$1" valor="$2"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto_secreto.XXXXXX")"
  printf '%s' "$valor" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ruta"
  chmod 600 "$ruta"
}

preparar_estado

# --dry-run: solo imprime el plan. Hace una sola GET /version si hay token.
if [ "$MODO" = "dry" ]; then
  if [ -f "${COOLIFY_TOKEN_FILE:-/nada}" ]; then
    api GET /version >/dev/null 2>&1 || true
  fi
  if [ -f "$SUPABASE_UUID_FILE" ]; then
    uuid_reuso="$(cat "$SUPABASE_UUID_FILE")"
    printf 'supabase: reusar uuid=%s (existe %s)\n' "$uuid_reuso" "$SUPABASE_UUID_FILE"
  else
    printf 'supabase: crear servicio type=supabase name=%s dominio=%s\n' "$SERVICE_NAME" "supabase.$DOMINIO_BASE"
  fi
  printf 'supabase: PATCH connect_to_docker_network:true\n'
  printf 'supabase: PATCH envs/bulk SMTP_HOST=smtp.resend.com PORT=465 USER=resend (PASS desde %s)\n' "$RESEND_ENV_FILE"
  printf 'supabase: POST /start y esperar status=running\n'
  printf 'supabase: escribir %s, %s, %s (0600)\n' "$SUPABASE_KEY_FILE" "$SUPABASE_ANON_KEY_FILE" "$SUPABASE_POSTGRES_PASS"
  exit 0
fi

# --ejecutar
if ! coolify_validar; then exit 1; fi

server_uuid="$(coolify_server_uuid)" || exit 1
proj_uuid="$(coolify_proyecto_mvps)" || exit 1
log "proyecto mvps: $proj_uuid"

# Resolver el uuid del servicio Supabase.
supa_uuid=""
if [ -f "$SUPABASE_UUID_FILE" ]; then
  supa_uuid="$(cat "$SUPABASE_UUID_FILE")"
  if [ -n "$supa_uuid" ]; then
    log "supabase: reusando uuid=$supa_uuid"
  fi
fi
if [ -z "$supa_uuid" ]; then
  body="$(mktemp "${TMPDIR:-/tmp}/hefesto_supa_body.XXXXXX")"
  jq -n --arg p "$proj_uuid" --arg s "$server_uuid" --arg n "$SERVICE_NAME" \
       --arg dom "supabase.$DOMINIO_BASE" \
    '{type:"supabase", name:$n, project_uuid:$p, server_uuid:$s,
      environment_name:"production", instant_deploy:false,
      urls:[{name:"supabase-kong", url:("http://" + $dom)}]}' > "$body"
  supa_resp="$(api POST /services "$body")" || { error "no se pudo crear el servicio Supabase"; rm -f "$body"; exit 1; }
  rm -f "$body"
  supa_uuid="$(printf '%s' "$supa_resp" | jq -r '.uuid')"
  if [ -z "$supa_uuid" ] || [ "$supa_uuid" = "null" ]; then
    error "servicio Supabase sin uuid en la respuesta"; exit 1
  fi
  printf '%s\n' "$supa_uuid" > "$SUPABASE_UUID_FILE"
  chmod 600 "$SUPABASE_UUID_FILE"
fi

# Conectar a la red interna de Coolify.
patch_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_supa_patch.XXXXXX")"
printf '{"connect_to_docker_network":true}' > "$patch_body"
api PATCH "/services/$supa_uuid" "$patch_body" >/dev/null || {
  error "PATCH connect_to_docker_network falló"; rm -f "$patch_body"; exit 1; }
rm -f "$patch_body"

# SMTP de GoTrue con Resend.
resend_key="$(leer_resend_api_key)" || exit 1
smtp_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_supa_smtp.XXXXXX")"
smtp_pass_val="$resend_key"
jq -n --arg hp "smtp.resend.com" --argjson pt 465 --arg u "resend" --arg pw "$smtp_pass_val" \
     --arg ae "no-reply@$DOMINIO_BASE" --arg sn "Hefesto" \
  '{data:[
    {key:"SMTP_HOST", value:$hp, is_literal:true, is_preview:false},
    {key:"SMTP_PORT", value:($pt|tostring), is_literal:true, is_preview:false},
    {key:"SMTP_USER", value:$u, is_literal:true, is_preview:false},
    {key:"SMTP_PASS", value:$pw, is_literal:true, is_preview:false},
    {key:"SMTP_ADMIN_EMAIL", value:$ae, is_literal:true, is_preview:false},
    {key:"SMTP_SENDER_NAME", value:$sn, is_literal:true, is_preview:false}
  ]}' > "$smtp_body"
api PATCH "/services/$supa_uuid/envs/bulk" "$smtp_body" >/dev/null || {
  error "PATCH envs/bulk SMTP falló"; rm -f "$smtp_body"; exit 1; }
rm -f "$smtp_body"

# Arrancar el servicio y esperar a que pase a running.
api POST "/services/$supa_uuid/start" >/dev/null || { error "start falló"; exit 1; }

esperado_running=0
n=0
while [ "$n" -lt "$MAX_INTENTOS_INICIO" ]; do
  n=$((n + 1))
  sleep "$ESPERA_SONDEO"
  st="$(api GET "/services/$supa_uuid" | jq -r '.status // ""' || true)"
  case "$st" in
    running*) esperado_running=1; break ;;
  esac
done
if [ "$esperado_running" -ne 1 ]; then
  error "el servicio Supabase no pasó a running tras $MAX_INTENTOS_INICIO intentos (status='$st')"
  exit 1
fi
log "supabase: status=$st"

# Leer las envs y escribir los archivos (0600). Si llegan vacías o enmascaradas, error.
envs="$(api GET "/services/$supa_uuid/envs")" || { error "no se pudieron leer las envs"; exit 1; }
svc_key="$(printf '%s' "$envs" | jq -r '.[] | select(.key=="SERVICE_SUPABASESERVICE_KEY") | .value // ""')"
anon_key="$(printf '%s' "$envs" | jq -r '.[] | select(.key=="SERVICE_SUPABASEANON_KEY") | .value // ""')"
pg_pass="$(printf '%s' "$envs" | jq -r '.[] | select(.key=="SERVICE_PASSWORD_POSTGRES") | .value // ""')"
if [ -z "$svc_key" ] || [ "$svc_key" = "null" ]; then
  error "SERVICE_SUPABASESERVICE_KEY vacío o nulo: el token necesita read:sensitive"; exit 1
fi
if [ -z "$anon_key" ] || [ "$anon_key" = "null" ]; then
  error "SERVICE_SUPABASEANON_KEY vacío o nulo: el token necesita read:sensitive"; exit 1
fi
if [ -z "$pg_pass" ] || [ "$pg_pass" = "null" ]; then
  error "SERVICE_PASSWORD_POSTGRES vacío o nulo: el token necesita read:sensitive"; exit 1
fi

escribir_secreto "$SUPABASE_KEY_FILE" "$svc_key"
escribir_secreto "$SUPABASE_ANON_KEY_FILE" "$anon_key"
escribir_secreto "$SUPABASE_POSTGRES_PASS" "$pg_pass"

# Salida: solo uuid, status y rutas de los archivos.
printf 'supabase: uuid=%s status=%s\n' "$supa_uuid" "$st"
printf 'supabase: secreto=%s\n' "$SUPABASE_KEY_FILE"
printf 'supabase: secreto=%s\n' "$SUPABASE_ANON_KEY_FILE"
printf 'supabase: secreto=%s\n' "$SUPABASE_POSTGRES_PASS"