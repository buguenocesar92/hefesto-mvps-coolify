#!/usr/bin/env bash
# aplicar-sql.sh (--apps a,b|--todas) [--dry-run|--ejecutar]
# Por cada app genera el SQL con supabase-sql.sh --por-app, crea una scheduled task
# en el servicio Supabase de Coolify (enabled:false, container:supabase-db), la ejecuta,
# sondea las executions y registra SQL_OK/SQL_ERROR en $ESTADO_DIR/sql.tsv (0600).
# Por stdout solo emite el slug y el resultado. Ningún secreto en logs/salida/URL.
set -euo pipefail
# shellcheck shell=bash
RAIZ_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comun.sh
source "$RAIZ_LIB/lib/comun.sh"
# shellcheck source=lib/coolify.sh
source "$RAIZ_LIB/lib/coolify.sh"

SUPABASE_UUID_FILE="${SUPABASE_UUID_FILE:-$ESTADO_DIR/supabase.uuid}"
APPS_FILE="${APPS_TSV:-$RAIZ_LIB/apps.tsv}"
SQL_TSV="$ESTADO_DIR/sql.tsv"
ESPERA_SONDEO="${ESPERA_SONDEO:-10}"
MAX_INTENTOS="${MAX_INTENTOS:-30}"

uso() {
  cat >&2 <<USO
uso: $(basename "$0") (--apps a,b|--todas) [--dry-run|--ejecutar]
  --apps a,b    aplica SQL solo a esas apps
  --todas       aplica SQL a todas las apps
  --dry-run     imprime el plan (defecto)
  --ejecutar    llama a la API de Coolify
USO
}

apps_seleccion=()
todas=0
MODO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apps) IFS=',' read -r -a apps_seleccion <<< "${2:-}"; shift 2 ;;
    --todas) todas=1; shift ;;
    --dry-run) MODO="${MODO:-dry}"; shift ;;
    --ejecutar) MODO="${MODO:-ejecutar}"; shift ;;
    -h|--help) uso; exit 0 ;;
    *) error "argumento desconocido: $1"; uso; exit 2 ;;
  esac
done
[ -n "$MODO" ] || MODO="dry"
[ "${#apps_seleccion[@]}" -gt 0 ] || [ "$todas" -eq 1 ] || { error "falta --apps o --todas"; uso; exit 2; }

preparar_estado

# Construir la lista de slugs a aplicar.
slugs=()
n=1
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  if [ "$todas" -ne 1 ]; then
    keep=0
    for s in "${apps_seleccion[@]}"; do [ "$s" = "$slug" ] && keep=1; done
    [ "$keep" -eq 1 ] || continue
  fi
  slugs+=("$slug")
done < "$APPS_FILE"

if [ "${#slugs[@]}" -eq 0 ]; then
  echo "nada que aplicar" >&2; exit 0
fi

# --dry-run: solo imprime el plan y sale.
if [ "$MODO" = "dry" ]; then
  if [ -f "${COOLIFY_TOKEN_FILE:-/nada}" ]; then
    api GET /version >/dev/null 2>&1 || true
  fi
  for slug in "${slugs[@]}"; do
    printf 'sql: %s (archivo %s/sql/%s.sql)\n' "$slug" "$ESTADO_DIR" "$slug"
  done
  printf 'sql: scheduled task container=supabase-db enabled=false en %s\n' "$SUPABASE_UUID_FILE"
  exit 0
fi

# --ejecutar
if ! coolify_validar; then exit 1; fi
[ -f "$SUPABASE_UUID_FILE" ] || { error "falta $SUPABASE_UUID_FILE; correr instalar-supabase.sh --ejecutar primero"; exit 1; }
supa_uuid="$(cat "$SUPABASE_UUID_FILE")"

# sql.tsv: encabezado (solo si existe/lo vamos a crear).
( umask 077
  [ -f "$SQL_TSV" ] || printf 'slug\testado\tfecha\n' > "$SQL_TSV"
  chmod 600 "$SQL_TSV" 2>/dev/null || true
)

# 1) Generar todos los SQL por app.
"$RAIZ_LIB/supabase-sql.sh" --todas --por-app >/dev/null

# 2) Por cada app, crear la scheduled task, ejecutarla, esperar y borrar.
fallos=0
for slug in "${slugs[@]}"; do
  sql_arch="$ESTADO_DIR/sql/$slug.sql"
  [ -f "$sql_arch" ] || { error "no se generó $sql_arch"; fallos=$((fallos+1)); continue; }

  sql_b64="$(base64 -w0 "$sql_arch")"

  # Armar el comando. psql corre con -q para no imprimir filas; el grep filtra ERROR/FATAL;
  # al final se imprime FIN_OK para que la ejecución pueda distinguir éxito de fallo.
  # El comando viaja dentro del cuerpo JSON, no en la URL.
  cmd="$(printf "printf '%%s' '%s' | base64 -d | psql -U postgres -v ON_ERROR_STOP=1 -q 2>&1 | grep -E 'ERROR|FATAL' || true; echo FIN_OK" "$sql_b64")"

  # 2a) Crear la task (enabled:false).
  task_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_task_body.XXXXXX")"
  jq -n --arg c "$cmd" --argjson t 600 \
    '{name:("aplicar-sql-" + "X"), command:$c, frequency:"0 0 1 1 *", container:"supabase-db", timeout:$t, enabled:false}' \
    > "$task_body"
  task_resp="$(api POST "/services/$supa_uuid/scheduled-tasks" "$task_body")" || {
    error "no se pudo crear la task para $slug"; rm -f "$task_body"; fallos=$((fallos+1)); continue; }
  rm -f "$task_body"
  task_uuid="$(printf '%s' "$task_resp" | jq -r '.uuid // ""')"
  if [ -z "$task_uuid" ] || [ "$task_uuid" = "null" ]; then
    error "task sin uuid para $slug"; fallos=$((fallos+1)); continue
  fi

  # 2b) Ejecutar la task.
  exec_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_exec_body.XXXXXX")"
  printf '{}' > "$exec_body"
  api POST "/services/$supa_uuid/scheduled-tasks/$task_uuid/execute" "$exec_body" >/dev/null || {
    error "no se pudo ejecutar la task para $slug"; rm -f "$exec_body"; api PATCH "/services/$supa_uuid/scheduled-tasks/$task_uuid" <(printf '{"enabled":false}') >/dev/null 2>&1 || true; fallos=$((fallos+1)); continue; }
  rm -f "$exec_body"

  # 2c) Sondear executions hasta encontrar un message con FIN_OK (sin ERROR/FATAL).
  estado="SQL_ERROR"
  msg=""
  n=0
  while [ "$n" -lt "$MAX_INTENTOS" ]; do
    n=$((n+1))
    sleep "$ESPERA_SONDEO"
    resp="$(api GET "/services/$supa_uuid/scheduled-tasks/$task_uuid/executions")" || continue
    msg="$(printf '%s' "$resp" | jq -r '.message // ""')"
    if [[ "$msg" == *"FIN_OK"* ]] && [[ "$msg" != *"ERROR"* ]] && [[ "$msg" != *"FATAL"* ]]; then
      estado="SQL_OK"; break
    fi
    if [[ "$msg" == *"ERROR"* ]] || [[ "$msg" == *"FATAL"* ]]; then
      estado="SQL_ERROR"; break
    fi
  done

  # Filtrar líneas ERROR/FATAL para imprimir, sin claves (psql corrió con -q).
  if [ "$estado" = "SQL_ERROR" ]; then
    lineas_err="$(printf '%s\n' "$msg" | grep -E 'ERROR|FATAL' || true)"
    printf '%s %s\n%s' "$slug" "$estado" "$lineas_err"
    fallos=$((fallos+1))
  else
    printf '%s %s\n' "$slug" "$estado"
  fi

  # 2d) Borrar (o deshabilitar) la task.
  if ! api DELETE "/services/$supa_uuid/scheduled-tasks/$task_uuid" >/dev/null 2>&1; then
    disable_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_disable.XXXXXX")"
    printf '{"enabled":false}' > "$disable_body"
    api PATCH "/services/$supa_uuid/scheduled-tasks/$task_uuid" "$disable_body" >/dev/null 2>&1 || true
    rm -f "$disable_body"
    log "$slug: DELETE falló, task deshabilitada"
  fi

  # 2e) Registrar en sql.tsv (0600).
  fecha="$(date '+%F %T')"
  tmp_tsv="$(mktemp "$ESTADO_DIR/.sql_tsv.XXXXXX")"
  ( umask 077
    if [ -f "$SQL_TSV" ]; then
      awk -F'\t' -v s="$slug" '$1 != s' "$SQL_TSV" >> "$tmp_tsv"
    fi
    printf '%s\t%s\t%s\n' "$slug" "$estado" "$fecha" >> "$tmp_tsv"
    mv "$tmp_tsv" "$SQL_TSV"
    chmod 600 "$SQL_TSV" 2>/dev/null || true
  )
done

exit $(( fallos > 0 ? 1 : 0 ))