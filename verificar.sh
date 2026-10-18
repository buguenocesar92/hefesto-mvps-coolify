#!/usr/bin/env bash
# verificar.sh: para cada app con dominio (DESPLEGADA), hace curl al host público y
# opcionalmente GET /applications/{uuid} → .status. Códigos 200, 301, 302, 401, 403
# cuentan como "responde". Imprime TSV y lo guarda en $ESTADO_DIR/verificacion.tsv.
set -euo pipefail
# shellcheck shell=bash
RAIZ_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comun.sh
source "$RAIZ_LIB/lib/comun.sh"
# shellcheck source=lib/coolify.sh
source "$RAIZ_LIB/lib/coolify.sh"

ESTADO_DIR="${HEFESTO_MVPS_ESTADO:-$HOME/.local/state/hefesto-mvps}"
[ -f "$ESTADO_DIR/apps.tsv" ] || { echo "no existe $ESTADO_DIR/apps.tsv" >&2; exit 1; }

CURL_BIN="${CURL_BIN:-curl}"
salida="$ESTADO_DIR/verificacion.tsv"
tmp="$(mktemp "${TMPDIR:-/tmp}/hefesto_verif.XXXXXX")"
chmod 600 "$tmp"

printf 'slug\turl\thttp\tstatus_coolify\n' > "$tmp"

[ -f "${COOLIFY_TOKEN_FILE:-/nada}" ] && con_token=1 || con_token=0
if [ "$con_token" -eq 1 ]; then coolify_validar || true; fi

while IFS=$'\t' read -r slug _uuid estado url _fecha; do
  [ "$slug" = "slug" ] && continue
  [ "$estado" = "DESPLEGADA" ] || continue
  [ -n "$url" ] || continue
  http="$("$CURL_BIN" -s -o /dev/null -w '%{http_code}' --max-time 15 "${url%/}/")" || http="000"
  st=""
  if [ "$con_token" -eq 1 ]; then
    st="$(api GET "/applications/$_uuid" | jq -r '.status // ""')" || st=""
  fi
  printf '%s\t%s\t%s\t%s\n' "$slug" "$url" "$http" "$st" >> "$tmp"
done < "$ESTADO_DIR/apps.tsv"

mv "$tmp" "$salida"
chmod 600 "$salida"

cat "$salida"
awk -F'\t' 'NR>1 && $3 ~ /^(200|301|302|401|403)$/ {print $1"	"$2"	"$3"	"$4"	responde"; next} NR>1 {print $1"	"$2"	"$3"	"$4"	cae"}' "$salida" | tail -n +1
