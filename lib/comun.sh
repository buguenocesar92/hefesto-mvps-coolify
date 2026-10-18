#!/usr/bin/env bash
# comun: utilidades compartidas de hefesto-mvps-coolify (se carga con source).
# shellcheck shell=bash
RAIZ="${RAIZ:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
APPS_TSV="${APPS_TSV:-$RAIZ/apps.tsv}"
ESTADO_DIR="${HEFESTO_MVPS_ESTADO:-$HOME/.local/state/hefesto-mvps}"
DOMINIO_BASE="${DOMINIO_BASE:-hefesto-studio.cl}"
error() { printf 'error: %s\n' "$*" >&2; }
log()   { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; }
# fila <slug>: imprime la fila TSV de la app (sin header) o sale 1 si no existe.
fila() { awk -F'\t' -v s="$1" 'NR>1 && $1==s {print; f=1} END{exit !f}' "$APPS_TSV"; }
# campo <slug> <n>: columna n (1-based) de la app.
campo() { fila "$1" | awk -F'\t' -v n="$2" '{print $n}'; }
slug_valido() { [[ "$1" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; }
preparar_estado() { ( umask 077; mkdir -p "$ESTADO_DIR" ); chmod 700 "$ESTADO_DIR"; }

# rol_bd_kit <repo> <base_dir> <slug>: lee el primer CREATE ROLE/USER de <base_dir>/sql/01-*.sql en la
# rama coolify de $REPOS_DIR/<repo>. Imprime "<rol>\tkit", o "mvp_<slug_>_app\tconvencion" si el kit
# usa una variable psql (:'app_user'). Sale 1 si no hay rama, ni sql/, ni un nombre válido.
rol_bd_kit() {
  local repo="$1" base="$2" slug="$3" pref tmp tok
  case "$base" in /|"") pref="" ;; *) pref="${base#/}/" ;; esac
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/rolkit.XXXXXX")"
  if ! git -C "${REPOS_DIR:-$HOME/Dev}/$repo" archive coolify -- "${pref}sql/" 2>/dev/null \
       | tar -xf - -C "$tmp" 2>/dev/null; then
    rm -rf "$tmp"; return 1
  fi
  tok="$( { cat "$tmp/${pref}sql"/01-*.sql 2>/dev/null | grep -ioE 'create[[:space:]]+(role|user)[[:space:]]+[^[:space:];]+' \
          | head -1 | awk '{print $3}'; } 2>/dev/null || true)"
  rm -rf "$tmp"
  case "$tok" in
    "") return 1 ;;
    :*) printf '%s\tconvencion\n' "mvp_${slug//-/_}_app" ;;
    *) tok="${tok//\"/}"
       [[ "$tok" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || return 1
       printf '%s\tkit\n' "$tok" ;;
  esac
}
