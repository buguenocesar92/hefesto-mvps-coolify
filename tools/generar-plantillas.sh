#!/usr/bin/env bash
# generar-plantillas.sh: crea/actualiza envs/<slug>.tpl a partir de apps.tsv.
# Idempotente. Las variables que la tabla de deducción no resuelve quedan como {{PENDIENTE}}
# y solo declarar_pendiente las anota en reporte.md.
# Sobreescribibles (tests): APPS_TSV, ENVS_DIR (salida), REPORTE, REPOS_DIR.
set -euo pipefail
# shellcheck shell=bash
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/comun.sh
source "$RAIZ/lib/comun.sh"
ENVS_SALIDA="${ENVS_DIR:-$RAIZ/envs}"
REPORTE="${REPORTE:-$RAIZ/reporte.md}"
REPOS_DIR="${REPOS_DIR:-$HOME/Dev}"
mkdir -p "$ENVS_SALIDA"
: > "$REPORTE"

# partir_col14 <texto>: separa por las comas que no están dentro de paréntesis; una parte por línea.
partir_col14() {
  printf '%s' "$1" | LC_ALL=C awk '
{
  n = 0; s = ""
  for (i = 1; i <= length($0); i++) {
    c = substr($0, i, 1)
    if (c == "(") n++
    else if (c == ")" && n > 0) n--
    if (c == "," && n == 0) { print s; s = "" } else s = s c
  }
  print s
}
'
}

# normalizar_formato <formato-crudo> <VAR>: imprime el formato que entiende secreto(), o
# COPIA:<VAR_FUENTE>; sale 1 si no hay equivalente. No escribe en el reporte.
normalizar_formato() {
  local f="$1" var="$2"
  case "$f" in
    hex64|hex32|hex96|b64-32|alnum24|laravel|bcrypt:*|pbkdf2:*) printf '%s' "$f" ;;
    base64-32|base64_32) printf 'b64-32' ;;
    base64-48|base64_48|hex48|hex128) printf 'hex96' ;;
    uuid4|uuid) printf 'hex32' ;;
    bcrypt*) printf 'bcrypt:%s_PASSWORD' "${var%_HASH}" ;;
    'base64:+base64-32') printf 'laravel' ;;
    'base64(salt'*'pbkdf2_sha256'*) printf 'pbkdf2:%s_PLANO' "$var" ;;
    copia-de-*)
      [[ "${f#copia-de-}" =~ ^[A-Z][A-Z0-9_]*$ ]] || return 1
      printf 'COPIA:%s' "${f#copia-de-}" ;;
    *) return 1 ;;
  esac
}

anotar_pendiente() { echo "## $1 · $2 · $3" >> "$REPORTE"; }

emitir_cabecera() {
  if [ -s "$REPORTE" ]; then return 0; fi
  cat >> "$REPORTE" <<'EOF'
# Variables pendientes

Las variables que la tabla de deducción no resuelve quedan como `{{PENDIENTE}}` en la
plantilla. `render_env` las anuncia y `desplegar.sh` marca la app como `NECESITA_DATOS`
sin llamar a la API para ella.

Formato: una línea `## <slug> · <VAR> · <motivo>` por variable pendiente. Las líneas
`- rol por convención: …` no son pendientes.

## SQL

`supabase-sql.sh` fija `\set app_user` con el rol que crea el `sql/01-*.sql` del kit
(rama coolify) y `\set app_pass` con el `DB_PASSWORD` (hex64) de la app. Si el kit crea
el rol con `:'app_user'`, se usa la convención `mvp_<slug>_app`.

EOF
}

encabezado_plantilla() {
  cat > "$p" <<EOF
# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: $slug  bd=$bd  grupo=$grupo  alta_privada=$alta_privada
EOF
}

declarar_y_emitir() {
  local var="$1" valor="$2"
  if [ -z "${ya[$var]:-}" ]; then
    ya["$var"]=1
    printf '%s=%s\n' "$var" "$valor" >> "$p"
  fi
}
declarar_pendiente() {
  local var="$1" motivo="$2"
  if [ -z "${ya[$var]:-}" ]; then
    declarar_y_emitir "$var" "{{PENDIENTE}}"
    anotar_pendiente "$slug" "$var" "$motivo"
  fi
}
emitir_publicar() {
  if [ -z "${ya_publicar[$1]:-}" ]; then
    ya_publicar["$1"]=1
    printf '# publicar: %s=true\n' "$1" >> "$p"
  fi
}
# emitir_secreto_interno <VAR>: formato de la columna 14 (o copia), si no la heurística por sufijo.
emitir_secreto_interno() {
  local var="$1" f="${fmt_secreto[$1]:-}"
  if [[ "$f" == COPIA:* ]]; then
    declarar_y_emitir "$var" "{{${f}}}"
  elif [ -n "$f" ]; then
    declarar_y_emitir "$var" "{{GEN:$f}}"
  elif [ -n "${fmt_invalido[$var]:-}" ]; then
    declarar_pendiente "$var" "formato de secreto no soportado: ${fmt_invalido[$var]}"
  elif [[ "$var" == *_HASH ]]; then
    declarar_y_emitir "$var" "{{GEN:bcrypt:${var%_HASH}_PASSWORD}}"
  elif [[ "$var" == *_PASSWORD || "$var" == *_SECRET || "$var" == *_KEY || "$var" == *_TOKEN || "$var" == *_AUTH || "$var" == SALT* ]]; then
    declarar_y_emitir "$var" "{{GEN:hex32}}"
  else
    declarar_pendiente "$var" "no reconocido por la tabla de deducción"
  fi
}

n=1
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  repo="$(printf '%s\n' "$linea" | cut -f2)"
  base_dir="$(printf '%s\n' "$linea" | cut -f3)"
  bd="$(printf '%s\n' "$linea" | cut -f8)"
  grupo="$(printf '%s\n' "$linea" | cut -f9)"
  alta_privada="$(printf '%s\n' "$linea" | cut -f10)"
  necesita_smtp="$(printf '%s\n' "$linea" | cut -f11)"
  cambios="$(printf '%s\n' "$linea" | cut -f12)"
  vars="$(printf '%s\n' "$linea" | cut -f13)"
  secretos="$(printf '%s\n' "$linea" | cut -f14)"

  p="$ENVS_SALIDA/$slug.tpl"
  encabezado_plantilla
  emitir_cabecera
  declare -A ya=() ya_publicar=() fmt_secreto=() fmt_invalido=()

  # Columna 14 (secretos_generables) → formato normalizado o inválido, por variable.
  if [ -n "$secretos" ]; then
    mapfile -t pares < <(partir_col14 "$secretos")
    for par in "${pares[@]}"; do
      par="$(printf '%s' "$par" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ "$par" == *=* ]] || continue
      nombre="${par%%=*}"; nombre="$(printf '%s' "$nombre" | tr -d ' ')"
      resto="${par#*=}"
      fmt_raw="$(printf '%s' "$resto" | sed -E 's/[[:space:]].*//')"
      if fmt="$(normalizar_formato "$fmt_raw" "$nombre")"; then
        fmt_secreto["$nombre"]="$fmt"
      else
        fmt_invalido["$nombre"]="$fmt_raw"
      fi
    done
  fi

  # Columna 13 (variables_obligatorias): tabla de deducción, gana la primera regla.
  if [ -n "$vars" ]; then
    IFS=',' read -r -a lista <<< "$vars"
    for v in "${lista[@]}"; do
      nombre_base="$(printf '%s' "$v" | sed 's/^[[:space:]]*//' | grep -oE '^[A-Z][A-Z0-9_]{0,63}' || true)"
      [ -z "$nombre_base" ] && continue
      case "$nombre_base" in
        SUPABASE_DEDICATED_CONFIRMED|SUPABASE_DATA_API_DISABLED)
          declarar_y_emitir "$nombre_base" "true" ;;
        SMTP_READY)
          declarar_y_emitir "$nombre_base" "false" ;;
        INITIAL_SETUP_COMPLETE|OPERATOR_ACCOUNT_CREATED)
          declarar_y_emitir "$nombre_base" "false"
          if [ "$alta_privada" = "si" ]; then emitir_publicar "$nombre_base"; fi ;;
        COMPOSE_PROJECT_NAME|VOLUME_PREFIX)
          declarar_y_emitir "$nombre_base" "mvp-$slug" ;;
        DB_VOLUME|STORAGE_VOLUME|REDIS_VOLUME|CONFIG_VOLUME|DATA_VOLUME)
          parte="$(printf '%s' "${nombre_base%_VOLUME}" | tr '[:upper:]' '[:lower:]')"
          declarar_y_emitir "$nombre_base" "mvp-$slug-$parte" ;;
        PUBLIC_URL|PUBLIC_ORIGIN|APP_URL|APP_ORIGIN|BASE_URL|SITE_URL|WEBAPP_URL|NEXTAUTH_URL|MOODLE_URL|BASEROW_PUBLIC_URL|APPSMITH_BASE_URL|*_PUBLIC_URL)
          if [[ "$cambios" == *"$nombre_base con barra final"* ]]; then
            declarar_y_emitir "$nombre_base" "{{URL}}/"
          else
            declarar_y_emitir "$nombre_base" "{{URL}}"
          fi ;;
        APP_HOST|WIKI_HOST|VAULT_HOST|SURVEY_HOST|CHAT_HOST|NEWS_HOST|CRM_HOST|BI_HOST|ARCHIVE_HOST|ASSETS_HOST|AGENDA_HOST|LINKS_HOST|MARKETING_HOST|SITE_HOSTNAME|TRUSTED_HOSTS|DOMAIN)
          declarar_y_emitir "$nombre_base" "{{HOST}}" ;;
        PANEL_HOST)
          declarar_y_emitir "$nombre_base" "{{HOST:panel-enlaces}}" ;;
        SITE_URL_SCHEMA) declarar_y_emitir "$nombre_base" "https" ;;
        SITE_ADDRESS)    declarar_y_emitir "$nombre_base" ":80" ;;
        DB_HOST|POSTGRES_HOST)
          if [ "$bd" = "supabase-pg" ]; then declarar_y_emitir "$nombre_base" "{{DB_HOST}}"
          elif [ -n "${fmt_secreto[$nombre_base]:-}" ]; then declarar_y_emitir "$nombre_base" "{{GEN:${fmt_secreto[$nombre_base]}}}"
          else declarar_pendiente "$nombre_base" "host de BD (bd=$bd)"; fi ;;
        DB_PASSWORD|POSTGRES_PASSWORD)
          if [ "$bd" = "supabase-pg" ]; then declarar_y_emitir "$nombre_base" "{{DB_PASSWORD}}"
          else emitir_secreto_interno "$nombre_base"; fi ;;
        DB_NAME|POSTGRES_DB|POSTGRES_DATABASE)
          if [ "$bd" = "supabase-pg" ]; then declarar_y_emitir "$nombre_base" "{{DB_NAME}}"
          else declarar_pendiente "$nombre_base" "nombre de BD (bd=$bd)"; fi ;;
        DB_USER|POSTGRES_USERNAME)
          if [ "$bd" != "supabase-pg" ]; then
            declarar_pendiente "$nombre_base" "usuario de BD (bd=$bd)"
          elif rol_linea="$(rol_bd_kit "$repo" "$base_dir" "$slug")"; then
            rol="${rol_linea%%$'\t'*}"
            declarar_y_emitir "$nombre_base" "$rol"
            if [ "${rol_linea#*$'\t'}" = "convencion" ]; then
              printf -- "- rol por convención: %s → %s (el kit crea el rol con :'app_user')\n" "$slug" "$rol" >> "$REPORTE"
            fi
          else
            declarar_pendiente "$nombre_base" "rol no encontrado en sql/01-*.sql de la rama coolify de $repo"
          fi ;;
        ADMIN_EMAIL|ADMINMAIL|OWNER_EMAIL|INITIAL_ADMIN_EMAIL|SUPPORT_EMAIL|ALLOWED_EMAILS|POSTMASTER|SIGNOZ_USER_ROOT_EMAIL|APPSMITH_ADMIN_EMAILS|INITIAL_ADMIN_ACCOUNT)
          declarar_y_emitir "$nombre_base" "{{ADMIN_EMAIL}}" ;;
        MAIL_FROM|SMTP_FROM|NOREPLY_EMAIL|EMAIL_NOREPLY|MAILER_SENDER_EMAIL)
          declarar_y_emitir "$nombre_base" "no-reply@$DOMINIO_BASE" ;;
        SMTP_HOST|SMTP_ADDRESS) declarar_y_emitir "$nombre_base" "smtp.invalid" ;;
        SMTP_PORT) declarar_y_emitir "$nombre_base" "465" ;;
        SMTP_USER|SMTP_USERNAME|SMTP_PASSWORD) declarar_y_emitir "$nombre_base" "desactivado" ;;
        MAILER_DSN|MAILER_URL) declarar_y_emitir "$nombre_base" "null://null" ;;
        BASIC_AUTH_USER|NR_ADMIN_USER|NR_HTTP_USER|KOPIA_SERVER_USERNAME|CLICKHOUSE_USER|MINIO_ROOT_USER)
          declarar_y_emitir "$nombre_base" "hefesto" ;;
        TRUSTED_PROXIES|APP_TRUSTED_PROXIES|TRUSTED_PROXY|GOKAPI_TRUSTED_PROXIES|APP_PROXIES)
          declarar_y_emitir "$nombre_base" "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" ;;
        SIGNOZ_USER_ROOT_ENABLED) declarar_y_emitir "$nombre_base" "true" ;;
        META_*|WHATSAPP_*|KOPIA_S3_*|INVOICE_NINJA_*|N8N_*|BITWARDEN_*|AUDIO_TRANSCRIBE_*|RCLONE_*)
          declarar_pendiente "$nombre_base" "credencial externa" ;;
        SUPABASE_PUBLISHABLE_KEY|SUPABASE_ANON_KEY) declarar_y_emitir "$nombre_base" "{{SUPABASE_ANON_KEY}}" ;;
        SUPABASE_SECRET_KEY) declarar_y_emitir "$nombre_base" "{{SUPABASE_SECRET_KEY}}" ;;
        SUPABASE_URL) declarar_y_emitir "$nombre_base" "{{SUPABASE_URL}}" ;;
        *) emitir_secreto_interno "$nombre_base" ;;
      esac
    done
  fi

  # Completar según bd.
  case "$bd" in
    supabase-pg)
      declarar_y_emitir "DB_HOST" "{{DB_HOST}}"
      declarar_y_emitir "DB_NAME" "{{DB_NAME}}"
      declarar_y_emitir "DB_PASSWORD" "{{DB_PASSWORD}}"
      declarar_y_emitir "DB_SSLMODE" "disable"
      declarar_y_emitir "SUPABASE_DEDICATED_CONFIRMED" "true"
      declarar_y_emitir "SUPABASE_DATA_API_DISABLED" "true" ;;
    supabase-rest)
      declarar_y_emitir "STORAGE_BACKEND" "supabase" ;;
  esac
  # SMTP apagado (no hay proveedor) y mínimos comunes.
  if [ "$necesita_smtp" != "no" ]; then declarar_y_emitir "SMTP_READY" "false"; fi
  declarar_y_emitir "INITIAL_SETUP_COMPLETE" "false"
  if [ "$alta_privada" = "si" ]; then emitir_publicar "INITIAL_SETUP_COMPLETE"; fi
  declarar_y_emitir "APP_URL" "{{URL}}"
  declarar_y_emitir "APP_HOST" "{{HOST}}"

  unset ya ya_publicar fmt_secreto fmt_invalido
done < "$APPS_TSV"

total="$(find "$ENVS_SALIDA" -maxdepth 1 -name '*.tpl' | wc -l)"
pendientes="$( { grep -hc '{{PENDIENTE}}' "$ENVS_SALIDA"/*.tpl 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}' )"
{
  echo ""
  echo "---"
  echo ""
  echo "Total de plantillas: $total"
  echo "Líneas {{PENDIENTE}}: $pendientes"
} >> "$REPORTE"

echo "Plantillas generadas: $total"
echo "{{PENDIENTE}}: $pendientes (ver $REPORTE)"
