#!/usr/bin/env bash
# coolify: cliente mínimo de la API de Coolify v4. El token se lee de un archivo 0600 y viaja por un
# shellcheck shell=bash
# descriptor (-H @<(...)), nunca por argv ni por el entorno de hijos. Las respuestas no se imprimen
# salvo el cuerpo JSON por stdout para que el llamador lo procese con jq.
COOLIFY_URL="${COOLIFY_URL:-http://10.77.0.1:8000}"
COOLIFY_TOKEN_FILE="${COOLIFY_TOKEN_FILE:-$HOME/.config/hefesto/coolify-token}"
COOLIFY_PAUSA="${COOLIFY_PAUSA:-0.4}"   # 200 req/min de límite: 0.4 s deja margen
CURL="${CURL_BIN:-curl}"

coolify_validar() {
  [[ "$COOLIFY_URL" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] || { error "COOLIFY_URL inválida"; return 1; }
  [[ -f "$COOLIFY_TOKEN_FILE" ]] || { error "falta el token en $COOLIFY_TOKEN_FILE"; return 1; }
  (( (8#$(stat -c %a "$COOLIFY_TOKEN_FILE") & 8#077) == 0 )) || { error "$COOLIFY_TOKEN_FILE debe ser 0600"; return 1; }
}

# api <MÉTODO> <ruta> [archivo-json]: imprime el cuerpo de la respuesta; 0 si 2xx, 1 si no.
# Reintenta hasta 5 veces ante 429 respetando Retry-After (por defecto 5 s).
api() {
  local metodo="$1" ruta="$2" cuerpo="${3:-}" tmp codigo intento espera
  [[ "$metodo" =~ ^(GET|POST|PATCH|DELETE)$ ]] || { error "método inválido: $metodo"; return 1; }
  [[ "$ruta" =~ ^/[A-Za-z0-9/_?=\&.,:-]*$ ]] || { error "ruta inválida"; return 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/coolify.XXXXXX")"
  for intento in 1 2 3 4 5; do
    sleep "$COOLIFY_PAUSA"
    local -a args=(-sS -X "$metodo" --max-time 30 --max-redirs 0 -o "$tmp/cuerpo" -D "$tmp/cabeceras"
                   -w '%{http_code}' -H 'Accept: application/json')
    [[ -n "$cuerpo" ]] && args+=(-H 'Content-Type: application/json' --data-binary "@$cuerpo")
    codigo="$("$CURL" "${args[@]}" -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$COOLIFY_TOKEN_FILE")") \
              "$COOLIFY_URL/api/v1$ruta")" || codigo=000
    if [[ "$codigo" == 429 ]]; then
      espera="$(awk -F': ' 'tolower($1)=="retry-after"{gsub(/\r/,"",$2); print $2}' "$tmp/cabeceras" 2>/dev/null)"
      [[ "$espera" =~ ^[0-9]{1,3}$ ]] || espera=5
      log "429 en $metodo $ruta: espero ${espera}s (intento $intento)"; sleep "$espera"; continue
    fi
    break
  done
  cat "$tmp/cuerpo" 2>/dev/null || true
  rm -rf "$tmp"
  [[ "$codigo" =~ ^2 ]] || { error "$metodo $ruta → HTTP $codigo"; return 1; }
}
