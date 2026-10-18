#!/usr/bin/env bash
# generar-plantillas.sh: crea/actualiza envs/<slug>.tpl a partir de apps.tsv.
# Idempotente. Si deja {{PENDIENTE}}, lo anota en envs/.pendientes.txt.
set -euo pipefail
# shellcheck shell=bash
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$RAIZ/envs"
PENDIENTES="$RAIZ/envs/.pendientes.txt"
: > "$PENDIENTES"

n=1
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  bd="$(printf '%s\n' "$linea" | cut -f8)"
  grupo="$(printf '%s\n' "$linea" | cut -f9)"
  alta_privada="$(printf '%s\n' "$linea" | cut -f10)"
  necesita_smtp="$(printf '%s\n' "$linea" | cut -f11)"
  vars="$(printf '%s\n' "$linea" | cut -f13)"
  secretos="$(printf '%s\n' "$linea" | cut -f14)"

  p="$RAIZ/envs/$slug.tpl"
  : > "$p"
  {
    echo "# Plantilla generada para hefesto-mvps-coolify."
    echo "# Regenerar con tools/generar-plantillas.sh si cambia apps.tsv."
    echo "# App: $slug  bd=$bd  grupo=$grupo  alta_privada=$alta_privada"
    echo ""
  } >> "$p"

  declare -A fmt_secreto=()
  if [ -n "$secretos" ]; then
    IFS=',' read -r -a pares <<< "$secretos"
    for par in "${pares[@]}"; do
      par="$(printf '%s' "$par" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -z "$par" ] && continue
      nombre="${par%%=*}"; nombre="$(printf '%s' "$nombre" | tr -d ' ')"
      resto="${par#*=}"
      fmt="$(printf '%s' "$resto" | sed -E 's/[[:space:]].*//')"
      [ -n "$nombre" ] && [ -n "$fmt" ] && fmt_secreto["$nombre"]="$fmt"
    done
  fi

  declare -A ya=()
  emitir() { ya["$1"]=1; echo "$1=$2" >> "$p"; }
  anotar() { echo "$slug $1 ($2)" >> "$PENDIENTES"; }

  if [ -n "$vars" ]; then
    IFS=',' read -r -a lista <<< "$vars"
    for v in "${lista[@]}"; do
      v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -z "$v" ] && continue
      # apps.tsv lleva descripciones embebidas: "ADMIN_PASSWORD(solo bootstrap)" o
      # "KOPIA_TLS_FINGERPRINT(solo con compose.tls.yaml)". El nombre base válido según
      # el regex `[A-Z][A-Z0-9_]{0,63}`; las descripciones son info, no forman parte.
      nombre_base="$(printf '%s' "$v" | grep -oE '^[A-Z][A-Z0-9_]{0,63}' || true)"
      [ -z "$nombre_base" ] && continue
      case "$nombre_base" in
        SUPABASE_URL)        emitir "$nombre_base" "{{SUPABASE_URL}}" ;;
        SUPABASE_SECRET_KEY) emitir "$nombre_base" "{{SUPABASE_SECRET_KEY}}" ;;
        DB_HOST)             emitir "$nombre_base" "{{DB_HOST}}" ;;
        DB_NAME)             emitir "$nombre_base" "{{DB_NAME}}" ;;
        DB_PASSWORD)         emitir "$nombre_base" "{{DB_PASSWORD}}" ;;
        APP_KEY)
          if [ -n "${fmt_secreto[$nombre_base]:-}" ]; then emitir "$nombre_base" "{{GEN:${fmt_secreto[$nombre_base]}}}"
          else emitir "$nombre_base" "{{GEN:b64-32}}"; fi ;;
        *)
          if [[ "$nombre_base" == *_PASSWORD || "$nombre_base" == *_SECRET || "$nombre_base" == *_KEY || "$nombre_base" == *_TOKEN || "$nombre_base" == *_HASH || "$nombre_base" == SECRET_KEY_BASE || "$nombre_base" == DATABASE_PASSWORD || "$nombre_base" == REDIS_PASSWORD || "$nombre_base" == CRON_KEY ]]; then
            if [ -n "${fmt_secreto[$nombre_base]:-}" ]; then emitir "$nombre_base" "{{GEN:${fmt_secreto[$nombre_base]}}}"
            else emitir "$nombre_base" "{{GEN:hex64}}"; fi
          elif [[ "$nombre_base" == *_URL || "$nombre_base" == *_HOST || "$nombre_base" == *_HOSTNAME || "$nombre_base" == PUBLIC_ORIGIN || "$nombre_base" == SITE_ADDRESS || "$nombre_base" == MAIL_FROM ]]; then
            emitir "$nombre_base" "{{PENDIENTE}}"; anotar "$nombre_base" "URL pública, decidir"
          elif [[ "$nombre_base" == COMPOSE_PROJECT_NAME || "$nombre_base" == VOLUME_PREFIX || "$nombre_base" == *_USERNAME || "$nombre_base" == *_USER || "$nombre_base" == INSTANCE_ID || "$nombre_base" == PANEL_HOST || "$nombre_base" == TRUSTED_PROXIES || "$nombre_base" == SITE_URL_SCHEMA || "$nombre_base" == BASIC_AUTH_USER ]]; then
            emitir "$nombre_base" "{{PENDIENTE}}"; anotar "$nombre_base" "nombre/volumen/role, decidir"
          elif [[ "$nombre_base" == *_EMAIL || "$nombre_base" == *_EMAILS ]]; then
            emitir "$nombre_base" "{{PENDIENTE}}"; anotar "$nombre_base" "email de admin, decidir"
          elif [[ "$nombre_base" == DB_VOLUME || "$nombre_base" == STORAGE_VOLUME || "$nombre_base" == REDIS_VOLUME || "$nombre_base" == DB_SSLMODE || "$nombre_base" == SUPABASE_DEDICATED_CONFIRMED || "$nombre_base" == SUPABASE_DATA_API_DISABLED || "$nombre_base" == SMTP_READY || "$nombre_base" == INITIAL_SETUP_COMPLETE ]]; then
            emitir "$nombre_base" "{{PENDIENTE}}"; anotar "$nombre_base" "config opcional, decidir"
          else
            emitir "$nombre_base" "{{PENDIENTE}}"; anotar "$nombre_base" "no reconocido"
          fi
          ;;
      esac
    done
  fi

  case "$bd" in
    supabase-pg)
      [ -z "${ya[DB_HOST]:-}" ] && emitir "DB_HOST" "{{DB_HOST}}"
      [ -z "${ya[DB_NAME]:-}" ] && emitir "DB_NAME" "{{DB_NAME}}"
      [ -z "${ya[DB_PASSWORD]:-}" ] && emitir "DB_PASSWORD" "{{DB_PASSWORD}}"
      [ -z "${ya[DB_SSLMODE]:-}" ] && emitir "DB_SSLMODE" "disable"
      [ -z "${ya[SUPABASE_DEDICATED_CONFIRMED]:-}" ] && emitir "SUPABASE_DEDICATED_CONFIRMED" "true"
      [ -z "${ya[SUPABASE_DATA_API_DISABLED]:-}" ] && emitir "SUPABASE_DATA_API_DISABLED" "true"
      ;;
    supabase-rest)
      [ -z "${ya[STORAGE_BACKEND]:-}" ] && emitir "STORAGE_BACKEND" "supabase"
      ;;
  esac

  if [ "$necesita_smtp" != "no" ]; then
    [ -z "${ya[SMTP_READY]:-}" ] && emitir "SMTP_READY" "false"
  fi

  [ -z "${ya[INITIAL_SETUP_COMPLETE]:-}" ] && emitir "INITIAL_SETUP_COMPLETE" "false"
  [ -z "${ya[APP_URL]:-}" ] && emitir "APP_URL" "{{URL}}"
  [ -z "${ya[APP_HOST]:-}" ] && emitir "APP_HOST" "{{HOST}}"

  if [ "$alta_privada" = "si" ]; then
    echo "# publicar: poner INITIAL_SETUP_COMPLETE=true después del alta privada" >> "$p"
  fi

  unset ya fmt_secreto
done < "$RAIZ/apps.tsv"

total="$(find "$RAIZ/envs" -maxdepth 1 -name '*.tpl' 2>/dev/null | wc -l)"
echo "Plantillas generadas: $total"
if [ -s "$PENDIENTES" ]; then
  np="$(wc -l < "$PENDIENTES")"
  echo "{{PENDIENTE}}: $np (ver $PENDIENTES)"
fi
