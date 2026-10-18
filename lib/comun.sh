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
