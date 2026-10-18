#!/usr/bin/env bash
# supabase-sql.sh [--apps a,b|--todas] [--por-app]: genera el SQL para aplicar dentro del
# contenedor supabase-db.
#   - sin --por-app: escribe $ESTADO_DIR/supabase.sql (0600) con todas las apps concatenadas.
#   - con --por-app: escribe $ESTADO_DIR/sql/<slug>.sql (0600), uno por app.
# Contenido por app (idempotente):
#   - SELECT 'CREATE DATABASE …' WHERE NOT EXISTS (…) \gexec  + \connect mvp_<slug>
#   - sql/01-*.sql del kit envuelto en DO $$ … IF NOT EXISTS (rol) … $$ para no romper
#     si el rol ya existe; \set app_user '<rol>'; \set app_pass '<DB_PASSWORD hex64>'.
#   - \connect postgres + supabase/migrations/*.sql (para bd=supabase-rest).
# Por stdout solo imprime la ruta del archivo y el conteo. Ningún secreto.
set -euo pipefail
# shellcheck shell=bash
RAIZ_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comun.sh
source "$RAIZ_LIB/lib/comun.sh"
# shellcheck source=lib/secretos.sh
source "$RAIZ_LIB/lib/secretos.sh"

APPS_FILE="${APPS_TSV:-$RAIZ_LIB/apps.tsv}"
REPOS_DIR="${REPOS_DIR:-$HOME/Dev}"
apps_seleccion=()
todas=0
por_app=0

while [ $# -gt 0 ]; do case "$1" in
  --apps) IFS=',' read -r -a apps_seleccion <<< "${2:-}"; shift 2 ;;
  --todas) todas=1; shift ;;
  --por-app) por_app=1; shift ;;
  *) echo "uso: $0 (--apps a,b|--todas) [--por-app]" >&2; exit 2 ;;
esac; done

[ "${#apps_seleccion[@]}" -gt 0 ] || [ "$todas" -eq 1 ] || { echo "falta --apps o --todas" >&2; exit 2; }

preparar_estado
if [ "$por_app" -eq 1 ]; then
  mkdir -p "$ESTADO_DIR/sql"
fi

# generar_bloque_app <slug> <repo> <base_dir> <bd> <archivo_salida>: escribe en $5 el SQL
# de una sola app, con envoltura idempotente para CREATE DATABASE y CREATE ROLE.
generar_bloque_app() {
  local slug="$1" repo="$2" base_dir="$3" bd="$4" salida="$5"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto_app.XXXXXX")"
  chmod 600 "$tmp"
  case "$bd" in
    supabase-pg)
      local db_name db_user db_pass rol_linea
      db_name="mvp_${slug//-/_}"
      if rol_linea="$(rol_bd_kit "$repo" "$base_dir" "$slug")"; then
        db_user="${rol_linea%%$'\t'*}"
      else
        db_user="mvp_${slug//-/_}_app"
        printf 'aviso: %s: no se pudo leer el rol del kit (rama coolify, sql/01-*.sql); uso %s\n' "$slug" "$db_user" >&2
      fi
      db_pass="$(secreto "$slug" DB_PASSWORD hex64)"
      {
        echo "-- Generado para $slug."
        echo "-- Aplicar dentro del contenedor supabase-db con: psql -U postgres -v ON_ERROR_STOP=1 -q -f $(basename "$salida")"
        echo ""
        # Envoltorio idempotente: solo crea la base si no existe (psql no tiene IF NOT EXISTS para CREATE DATABASE).
        printf "SELECT 'CREATE DATABASE %s' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='%s') \\gexec\n" "$db_name" "$db_name"
        echo "\\connect $db_name"
        echo "\\set app_user '$db_user'"
        echo "\\set app_pass '$db_pass'"
        echo ""
        # Extraer sql/01-*.sql del repo (rama coolify). Si no existen, no es error.
        repo_path="$REPOS_DIR/$repo"
        sql_tmp="$(mktemp -d "$ESTADO_DIR/sql.XXXXXX")"
        chmod 700 "$sql_tmp"
        case "$base_dir" in
          /|"") arc_prefix="" ;;
          *) arc_prefix="${base_dir#/}/" ;;
        esac
        if git -C "$repo_path" archive coolify -- "${arc_prefix}sql/" \
             2>/dev/null | tar -xf - -C "$sql_tmp" 2>/dev/null; then
          sql_root="$sql_tmp/${arc_prefix}sql"
          if [ -d "$sql_root" ]; then
            for f in "$sql_root"/01-*.sql; do
              [ -f "$f" ] || continue
              echo "-- origen: $repo/sql/$(basename "$f")"
              # Idempotente: solo crear el rol si no existe. psql expande :'app_user'/ :'app_pass'
              # solo fuera de bloques $$ (PL/pgSQL), por eso usamos \gset + \if + \endif en vez de DO $$.
              printf '%s\n' "SELECT NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') AS crear_rol \\gset"
              printf '%s\n' "\\if :crear_rol"
              cat "$f"
              printf '%s\n' "\\endif"
              echo ""
            done
          fi
        fi
        rm -rf "$sql_tmp"
      } >> "$tmp"
      ;;
    supabase-rest)
      repo_path="$REPOS_DIR/$repo"
      {
        echo "\\connect postgres"
        echo "-- migraciones rest de $repo"
        sql_tmp="$(mktemp -d "$ESTADO_DIR/sql.XXXXXX")"
        chmod 700 "$sql_tmp"
        case "$base_dir" in
          /|"") arc_prefix="" ;;
          *) arc_prefix="${base_dir#/}/" ;;
        esac
        if git -C "$repo_path" archive coolify -- "${arc_prefix}supabase/migrations/" \
             2>/dev/null | tar -xf - -C "$sql_tmp" 2>/dev/null; then
          mig_root="$sql_tmp/${arc_prefix}supabase/migrations"
          if [ -d "$mig_root" ]; then
            for f in "$mig_root"/*.sql; do
              [ -f "$f" ] || continue
              cat "$f"
              echo ""
            done
          fi
        fi
        rm -rf "$sql_tmp"
      } >> "$tmp"
      ;;
  esac
  mv "$tmp" "$salida"
  chmod 600 "$salida"
}

n=1
bases_pg=0
apps_rest=0
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  repo="$(printf '%s\n' "$linea" | cut -f2)"
  base_dir="$(printf '%s\n' "$linea" | cut -f3)"
  bd="$(printf '%s\n' "$linea" | cut -f8)"
  secrets="$(printf '%s\n' "$linea" | cut -f14)"
  : "${secrets:=}"
  if [ "$todas" -ne 1 ]; then
    keep=0
    for s in "${apps_seleccion[@]}"; do [ "$s" = "$slug" ] && keep=1; done
    [ "$keep" -eq 1 ] || continue
  fi

  case "$bd" in
    supabase-pg) bases_pg=$((bases_pg + 1)) ;;
    supabase-rest) apps_rest=$((apps_rest + 1)) ;;
  esac

  if [ "$por_app" -eq 1 ]; then
    salida="$ESTADO_DIR/sql/$slug.sql"
    generar_bloque_app "$slug" "$repo" "$base_dir" "$bd" "$salida"
    echo "$salida"
  fi
done < "$APPS_FILE"

if [ "$por_app" -eq 1 ]; then
  echo "bases=$bases_pg migraciones_rest=$apps_rest"
  exit 0
fi

# Sin --por-app: archivo único (compatibilidad con Tarea 5 / anteriores).
salida="$ESTADO_DIR/supabase.sql"
tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto_supabase.XXXXXX")"
chmod 600 "$tmp"
{
  echo "-- Generado por hefesto-mvps-coolify/supabase-sql.sh. NO commitear."
  echo "-- Aplicar dentro del contenedor supabase-db con: psql -U postgres -f supabase.sql"
  echo ""
} > "$tmp"

n=1
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  repo="$(printf '%s\n' "$linea" | cut -f2)"
  base_dir="$(printf '%s\n' "$linea" | cut -f3)"
  bd="$(printf '%s\n' "$linea" | cut -f8)"
  if [ "$todas" -ne 1 ]; then
    keep=0
    for s in "${apps_seleccion[@]}"; do [ "$s" = "$slug" ] && keep=1; done
    [ "$keep" -eq 1 ] || continue
  fi
  bloque_tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto_bloque.XXXXXX")"
  chmod 600 "$bloque_tmp"
  generar_bloque_app "$slug" "$repo" "$base_dir" "$bd" "$bloque_tmp"
  cat "$bloque_tmp" >> "$tmp"
  rm -f "$bloque_tmp"
done < "$APPS_FILE"

mv "$tmp" "$salida"
chmod 600 "$salida"
echo "$salida"
echo "bases=$bases_pg migraciones_rest=$apps_rest"