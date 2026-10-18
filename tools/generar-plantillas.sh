#!/usr/bin/env bash
# generar-plantillas.sh: crea/actualiza envs/<slug>.tpl a partir de apps.tsv.
# Idempotente. Las variables que la tabla de deducción no resuelve quedan como
# {{PENDIENTE}} y se anotan en reporte.md, junto con la nota sobre el SQL.
set -euo pipefail
# shellcheck shell=bash
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$RAIZ/envs"
REPORTE="$RAIZ/reporte.md"
: > "$REPORTE"

DOMINIO_BASE="${DOMINIO_BASE:-hefesto-studio.cl}"

# normalizar_formato: el plan solo acepta hex64, hex32, hex96, b64-32, alnum24,
# bcrypt:<VAR_PLANO>. Si la columna 14 trae otra cosa (base64-32, hex128, etc.)
# se mapea al equivalente válido o se deja como PENDIENTE.
normalizar_formato() {
  local f="$1" var="$2"
  case "$f" in
    hex64|hex32|hex96|b64-32|alnum24|bcrypt:*) printf '%s' "$f"; return 0 ;;
    "base64-32"|"base64_32") printf '%s' "b64-32"; return 0 ;;
    "base64-48"|"base64_48") printf '%s' "hex96"; return 0 ;;
    hex48|hex128) printf '%s' "hex96"; return 0 ;;
    uuid4|uuid) printf '%s' "hex32"; return 0 ;;
    "bcrypt-cost12-de-clave-aleatoria"|"bcrypt-de-clave-basic-auth"|"bcrypt(coste")
      printf '%s' "bcrypt:BASIC_AUTH_PASSWORD"; return 0 ;;
    "copia-de-MINIO_ROOT_PASSWORD")
      # Es la MISMA contraseña que MINIO_ROOT_PASSWORD. Si MINIO_ROOT_PASSWORD ya
      # tiene formato en la columna 14, lo reusamos; si no, hex32.
      local fuente=""
      for par2 in "${pares[@]}"; do
        n2="${par2%%=*}"; n2="$(printf '%s' "$n2" | tr -d ' ')"
        [ "$n2" = "MINIO_ROOT_PASSWORD" ] && fuente="$par2" && break
      done
      if [ -n "$fuente" ]; then
        local fmt_fuente; fmt_fuente="$(printf '%s' "$fuente" | sed -E 's/.*=//; s/[[:space:]].*//')"
        local nf; nf="$(normalizar_formato "$fmt_fuente" "MINIO_ROOT_PASSWORD" 2>/dev/null || true)"
        [ -n "$nf" ] && { printf '%s' "$nf"; return 0; }
      fi
      echo "## $var ($slug): formato '$f' sin MINIO_ROOT_PASSWORD en columna 14; queda PENDIENTE" >> "$REPORTE"
      printf ''; return 1 ;;
    "copia-de-MINIO_ROOT_USER")
      echo "## $var ($slug): formato '$f' sin equivalente automático; queda PENDIENTE" >> "$REPORTE"
      printf ''; return 1 ;;
    "base64:+base64-32")
      echo "## $var ($slug): formato 'base64:+base64-32' ambiguo; queda PENDIENTE" >> "$REPORTE"
      printf ''; return 1 ;;
    *)
      echo "## $var ($slug): formato '$f' no soportado; queda PENDIENTE" >> "$REPORTE"
      printf ''; return 1 ;;
  esac
}

# anotar_pendiente: registra en reporte.md una variable que quedó {{PENDIENTE}}.
anotar_pendiente() {
  local slug="$1" var="$2" motivo="$3"
  echo "## $slug · $var · $motivo" >> "$REPORTE"
}

# emitir_pagina: agrega cabecera del reporte si aún no se hizo.
emitir_cabecera() {
  if [ ! -s "$REPORTE" ]; then
    {
      echo "# Variables pendientes"
      echo ""
      echo "Las variables que la tabla de deducción no resuelve quedan como"
      echo "\`{{PENDIENTE}}\` en la plantilla. \`render_env\` las anuncia y"
      echo "\`desplegar.sh\` marca la app como \`NECESITA_DATOS\`."
      echo ""
      echo "## SQL"
      echo ""
      echo "El kit (plan B) crea un rol por app y le inyecta la contraseña con"
      printf '%s\n' "\`\\\set app_pass '\$db_pass'\` (variable psql). Por ahora este script"
      printf '%s\n' "deja la sustitución en \`\\set app_pass '\$db_pass'\`; ajustar si el"
      printf '%s\n' "kit usa \`app_user\`/\`app_pass\` con otra convención."
      echo ""
    } >> "$REPORTE"
  fi
}

# encabezado de la plantilla.
encabezado_plantilla() {
  local p="$1" bd="$2" grupo="$3" alta_privada="$4"
  cat > "$p" <<EOF
# Plantilla generada para hefesto-mvps-coolify.
# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv.
# App: $slug  bd=$bd  grupo=$grupo  alta_privada=$alta_privada
EOF
}

n=1
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  : "$(printf '%s\n' "$linea" | cut -f2)"  # columna 2: repo (no se usa en este script)
  bd="$(printf '%s\n' "$linea" | cut -f8)"
  grupo="$(printf '%s\n' "$linea" | cut -f9)"
  alta_privada="$(printf '%s\n' "$linea" | cut -f10)"
  necesita_smtp="$(printf '%s\n' "$linea" | cut -f11)"
  vars="$(printf '%s\n' "$linea" | cut -f13)"
  secretos="$(printf '%s\n' "$linea" | cut -f14)"

  p="$RAIZ/envs/$slug.tpl"
  encabezado_plantilla "$p" "$bd" "$grupo" "$alta_privada"
  emitir_cabecera

  # secretos_generables (columna 14) → mapa nombre→formato normalizado.
  declare -A fmt_secreto=()
  if [ -n "$secretos" ]; then
    IFS=',' read -r -a pares <<< "$secretos"
    for par in "${pares[@]}"; do
      par="$(printf '%s' "$par" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -z "$par" ] && continue
      nombre="${par%%=*}"; nombre="$(printf '%s' "$nombre" | tr -d ' ')"
      resto="${par#*=}"
      fmt_raw="$(printf '%s' "$resto" | sed -E 's/[[:space:]].*//')"
      fmt="$(normalizar_formato "$fmt_raw" "$nombre" 2>/dev/null || true)"
      [ -n "$fmt" ] && fmt_secreto["$nombre"]="$fmt"
    done
  fi

  declarar_y_emitir() {
    local var="$1" valor="$2"
    if [ -z "${ya[$var]:-}" ]; then
      ya["$var"]=1
      printf '%s=%s\n' "$var" "$valor" >> "$p"
    fi
  }
  declarar_pendiente() {
    local var="$1" motivo="$2"
    declarar_y_emitir "$var" "{{PENDIENTE}}"
    anotar_pendiente "$slug" "$var" "$motivo"
  }
  declarar_gen() {
    local var="$1" formato="$2"
    declarar_y_emitir "$var" "{{GEN:$formato}}"
  }

  declare -A ya=()

  # 1) procesar la columna 13 (variables_obligatorias).
  if [ -n "$vars" ]; then
    IFS=',' read -r -a lista <<< "$vars"
    for v in "${lista[@]}"; do
      v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -z "$v" ] && continue
      nombre_base="$(printf '%s' "$v" | grep -oE '^[A-Z][A-Z0-9_]{0,63}' || true)"
      [ -z "$nombre_base" ] && continue
      case "$nombre_base" in
          # Tabla de deducción (orden importa; la primera regla que coincide gana).
          SUPABASE_DEDICATED_CONFIRMED|SUPABASE_DATA_API_DISABLED)
            declarar_y_emitir "$nombre_base" "true" ;;
          SMTP_READY)
            declarar_y_emitir "$nombre_base" "false" ;;
          INITIAL_SETUP_COMPLETE|OPERATOR_ACCOUNT_CREATED)
            if [ "$alta_privada" = "si" ]; then
              declarar_y_emitir "$nombre_base" "false"
              echo "# publicar: $nombre_base=true" >> "$p"
            else
              declarar_y_emitir "$nombre_base" "false"
            fi ;;
          COMPOSE_PROJECT_NAME) declarar_y_emitir "$nombre_base" "mvp-$slug" ;;
          VOLUME_PREFIX)        declarar_y_emitir "$nombre_base" "mvp-$slug" ;;
          DB_VOLUME|STORAGE_VOLUME|REDIS_VOLUME|CONFIG_VOLUME|DATA_VOLUME)
            parte="$(printf '%s' "$nombre_base" | tr '[:upper:]' '[:lower:]' | sed 's/_volume$//')"
            declarar_y_emitir "$nombre_base" "mvp-$slug-$parte" ;;
          PUBLIC_URL|PUBLIC_ORIGIN|APP_URL|APP_ORIGIN|BASE_URL|SITE_URL|WEBAPP_URL|NEXTAUTH_URL|MOODLE_URL|BASEROW_PUBLIC_URL|APPSMITH_BASE_URL)
            declarar_y_emitir "$nombre_base" "{{URL}}" ;;
          *_PUBLIC_URL)
            declarar_y_emitir "$nombre_base" "{{URL}}" ;;
          APP_HOST|WIKI_HOST|VAULT_HOST|SURVEY_HOST|CHAT_HOST|NEWS_HOST|CRM_HOST|BI_HOST|ARCHIVE_HOST|ASSETS_HOST|AGENDA_HOST|LINKS_HOST|MARKETING_HOST|SITE_HOSTNAME|TRUSTED_HOSTS|DOMAIN)
            declarar_y_emitir "$nombre_base" "{{HOST}}" ;;
          PANEL_HOST)
            declarar_y_emitir "$nombre_base" "{{HOST:panel-enlaces}}" ;;
          SITE_URL_SCHEMA) declarar_y_emitir "$nombre_base" "https" ;;
          SITE_ADDRESS)    declarar_y_emitir "$nombre_base" ":80" ;;
          DB_HOST|POSTGRES_HOST)
            if [ "$bd" = "supabase-pg" ]; then declarar_y_emitir "$nombre_base" "{{DB_HOST}}"
            elif [ -n "${fmt_secreto[$nombre_base]:-}" ]; then
              declarar_y_emitir "$nombre_base" "{{GEN:${fmt_secreto[$nombre_base]}}}"
            else
              declarar_pendiente "$nombre_base" "host de BD (bd=$bd)"; fi ;;
          DB_NAME|POSTGRES_DB|POSTGRES_DATABASE)
            if [ "$bd" = "supabase-pg" ]; then declarar_y_emitir "$nombre_base" "{{DB_NAME}}"
            else declarar_pendiente "$nombre_base" "nombre de BD (bd=$bd)"; fi ;;
          DB_USER|POSTGRES_USERNAME)
            if [ "$bd" = "supabase-pg" ]; then
              declarar_y_emitir "$nombre_base" "mvp_${slug//-/_}_app"
            else declarar_pendiente "$nombre_base" "usuario de BD (bd=$bd)"; fi ;;
          ADMIN_EMAIL|ADMINMAIL|OWNER_EMAIL|INITIAL_ADMIN_EMAIL|SUPPORT_EMAIL|ALLOWED_EMAILS|POSTMASTER|SIGNOZ_USER_ROOT_EMAIL|APPSMITH_ADMIN_EMAILS|INITIAL_ADMIN_ACCOUNT)
            declarar_y_emitir "$nombre_base" "{{ADMIN_EMAIL}}" ;;
          MAIL_FROM|SMTP_FROM|NOREPLY_EMAIL|EMAIL_NOREPLY|MAILER_SENDER_EMAIL)
            declarar_y_emitir "$nombre_base" "no-reply@$DOMINIO_BASE" ;;
          SMTP_HOST|SMTP_ADDRESS)
            declarar_y_emitir "$nombre_base" "smtp.invalid" ;;
          SMTP_PORT) declarar_y_emitir "$nombre_base" "465" ;;
          SMTP_USER|SMTP_USERNAME|SMTP_PASSWORD)
            declarar_y_emitir "$nombre_base" "desactivado" ;;
          MAILER_DSN|MAILER_URL)
            declarar_y_emitir "$nombre_base" "null://null" ;;
          BASIC_AUTH_USER|NR_ADMIN_USER|NR_HTTP_USER|KOPIA_SERVER_USERNAME)
            declarar_y_emitir "$nombre_base" "hefesto" ;;
          TRUSTED_PROXIES|APP_TRUSTED_PROXIES|TRUSTED_PROXY|GOKAPI_TRUSTED_PROXIES|APP_PROXIES)
            declarar_y_emitir "$nombre_base" "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" ;;
          SIGNOZ_USER_ROOT_ENABLED)
            declarar_y_emitir "$nombre_base" "true" ;;
          SUPABASE_PUBLISHABLE_KEY|SUPABASE_ANON_KEY)
            declarar_y_emitir "$nombre_base" "{{SUPABASE_ANON_KEY}}" ;;
          SUPABASE_SECRET_KEY)
            declarar_y_emitir "$nombre_base" "{{SUPABASE_SECRET_KEY}}" ;;
          SUPABASE_URL)
            declarar_y_emitir "$nombre_base" "{{SUPABASE_URL}}" ;;
          META_*|WHATSAPP_*|KOPIA_S3_*|INVOICE_NINJA_*|N8N_*|BITWARDEN_*|AUDIO_TRANSCRIBE_*|RCLONE_*)
            declarar_pendiente "$nombre_base" "credencial externa" ;;
          *)
            # Secreto interno (columna 14): si está mapeado, usa su formato; si no,
            # hex32. Para *_HASH y BASIC_AUTH_HASH: bcrypt del _PASSWORD correspondiente.
            if [ -n "${fmt_secreto[$nombre_base]:-}" ]; then
              declarar_y_emitir "$nombre_base" "{{GEN:${fmt_secreto[$nombre_base]}}}"
            elif [[ "$nombre_base" == *_HASH ]]; then
              var_plano="${nombre_base%_HASH}_PASSWORD"
              declarar_y_emitir "$nombre_base" "{{GEN:bcrypt:$var_plano}}"
            elif [[ "$nombre_base" == *_PASSWORD || "$nombre_base" == *_SECRET || "$nombre_base" == *_KEY || "$nombre_base" == *_TOKEN || "$nombre_base" == *_AUTH || "$nombre_base" == SALT* ]]; then
              declarar_y_emitir "$nombre_base" "{{GEN:hex32}}"
            else
              declarar_pendiente "$nombre_base" "no reconocido por la tabla de deducción"
            fi ;;
        esac
    done
  fi

  # 2) completar según bd.
  case "$bd" in
    supabase-pg)
      declarar_y_emitir "DB_HOST" "{{DB_HOST}}"
      declarar_y_emitir "DB_NAME" "{{DB_NAME}}"
      declarar_y_emitir "DB_PASSWORD" "{{DB_PASSWORD}}"
      declarar_y_emitir "DB_SSLMODE" "disable"
      declarar_y_emitir "SUPABASE_DEDICATED_CONFIRMED" "true"
      declarar_y_emitir "SUPABASE_DATA_API_DISABLED" "true"
      ;;
    supabase-rest)
      declarar_y_emitir "STORAGE_BACKEND" "supabase"
      ;;
  esac

  # 3) SMTP apagado por defecto (no hay proveedor).
  if [ "$necesita_smtp" != "no" ]; then
    declarar_y_emitir "SMTP_READY" "false"
  fi

  # 4) Variables mínimas que toda app debe tener.
  declarar_y_emitir "INITIAL_SETUP_COMPLETE" "false"
  if [ "$alta_privada" = "si" ]; then
    echo "# publicar: INITIAL_SETUP_COMPLETE=true" >> "$p"
  fi
  declarar_y_emitir "APP_URL" "{{URL}}"
  declarar_y_emitir "APP_HOST" "{{HOST}}"

  unset ya fmt_secreto
done < "$RAIZ/apps.tsv"

total="$(find "$RAIZ/envs" -maxdepth 1 -name '*.tpl' 2>/dev/null | wc -l)"
pendientes="$( { grep -hc '{{PENDIENTE}}' "$RAIZ/envs/"*.tpl 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}' )"
{
  echo ""
  echo "---"
  echo ""
  echo "Total de plantillas: $total"
  echo "Líneas {{PENDIENTE}}: $pendientes"
} >> "$REPORTE"

echo "Plantillas generadas: $total"
echo "{{PENDIENTE}}: $pendientes (ver $REPORTE)"