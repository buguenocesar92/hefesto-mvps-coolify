#!/usr/bin/env bash
# supabase-sql.sh [--apps a,b|--todas]: escribe $ESTADO_DIR/supabase.sql (0600) con
#   - CREATE DATABASE mvp_<slug>; + \connect mvp_<slug>
#   - sql/01-*.sql del repo (rama coolify) con la clave del rol vía \set de psql
#   - bloque \connect postgres + supabase/migrations/*.sql (rama coolify)
# Por stdout solo imprime la ruta del archivo y el conteo de bases. Ningún secreto.
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

while [ $# -gt 0 ]; do case "$1" in
  --apps) IFS=',' read -r -a apps_seleccion <<< "${2:-}"; shift 2 ;;
  --todas) todas=1; shift ;;
  *) echo "uso: $0 (--apps a,b|--todas)" >&2; exit 2 ;;
esac; done

[ "${#apps_seleccion[@]}" -gt 0 ] || [ "$todas" -eq 1 ] || { echo "falta --apps o --todas" >&2; exit 2; }

preparar_estado
salida="$ESTADO_DIR/supabase.sql"
tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto_supabase.XXXXXX")"
chmod 600 "$tmp"

# Cabecera
{
  echo "-- Generado por hefesto-mvps-coolify/supabase-sql.sh. NO commitear."
  echo "-- Aplicar dentro del contenedor supabase-db con: psql -U postgres -f supabase.sql"
  echo ""
} > "$tmp"

bases_pg=0
apps_rest=0

# Usar cut por columna para evitar el bug de IFS=tab que colapsa campos vacíos.
n=1
while IFS= read -r linea || [ -n "$linea" ]; do
  n=$((n + 1))
  [ "$n" -eq 2 ] && continue
  slug="$(printf '%s\n' "$linea" | cut -f1)"
  [ -z "$slug" ] && continue
  repo="$(printf '%s\n' "$linea" | cut -f2)"
  bd="$(printf '%s\n' "$linea" | cut -f8)"
  secrets="$(printf '%s\n' "$linea" | cut -f14)"
  # secrets no se usa directamente: las claves se generan con secreto <slug> DB_PASSWORD hex32.
  : "${secrets:=}"
  if [ "$todas" -ne 1 ]; then
    keep=0
    for s in "${apps_seleccion[@]}"; do [ "$s" = "$slug" ] && keep=1; done
    [ "$keep" -eq 1 ] || continue
  fi
  case "$bd" in
    supabase-pg)
      db_name="mvp_${slug//-/_}"
      db_user="mvp_${slug//-/_}_app"
      db_pass="$(secreto "$slug" DB_PASSWORD hex32)"
      {
        echo "CREATE DATABASE $db_name;"
        echo "\\connect $db_name"
        echo "\\set app_user '$db_user'"
        echo "\\set app_pass '$db_pass'"
        echo ""
        # Inyectar sql/01-*.sql del repo (rama coolify)
        repo_path="$REPOS_DIR/$repo"
        if [ -d "$repo_path/coolify/sql" ]; then
          for f in "$repo_path/coolify/sql"/01-*.sql; do
            [ -f "$f" ] || continue
            echo "-- origen: $repo/sql/$(basename "$f")"
            cat "$f"
            echo ""
          done
        fi
      } >> "$tmp"
      bases_pg=$((bases_pg + 1))
      ;;
    supabase-rest)
      repo_path="$REPOS_DIR/$repo"
      {
        echo "\\connect postgres"
        echo "-- migraciones rest de $repo"
        if [ -d "$repo_path/coolify/supabase/migrations" ]; then
          for f in "$repo_path/coolify/supabase/migrations"/*.sql; do
            [ -f "$f" ] || continue
            cat "$f"
            echo ""
          done
        fi
      } >> "$tmp"
      apps_rest=$((apps_rest + 1))
      ;;
  esac
done < "$APPS_FILE"

mv "$tmp" "$salida"
chmod 600 "$salida"

echo "$salida"
echo "bases=$bases_pg migraciones_rest=$apps_rest"
