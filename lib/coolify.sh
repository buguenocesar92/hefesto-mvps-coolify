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

# coolify_server_uuid: imprime el uuid del primer server configurado. Sale 1 si no hay.
# Si $COOLIFY_SERVER_UUID está definido, lo respeta.
coolify_server_uuid() {
  if [ -n "${COOLIFY_SERVER_UUID:-}" ]; then
    printf '%s' "$COOLIFY_SERVER_UUID"; return 0
  fi
  local servers server_uuid
  servers="$(api GET /servers)" || { error "no se pudo listar servers"; return 1; }
  server_uuid="$(printf '%s' "$servers" | jq -r '.[0].uuid')"
  if [ -z "$server_uuid" ] || [ "$server_uuid" = "null" ]; then
    error "no hay servers configurados"; return 1
  fi
  printf '%s' "$server_uuid"
}

# coolify_proyecto_mvps: imprime el uuid del proyecto "mvps" o lo crea si no existe.
coolify_proyecto_mvps() {
  local proyectos proj_uuid body proj_resp
  proyectos="$(api GET /projects)" || proyectos="[]"
  proj_uuid="$(printf '%s' "$proyectos" | jq -r --arg n "mvps" '.[] | select(.name==$n) | .uuid' | head -1)"
  if [ -n "$proj_uuid" ] && [ "$proj_uuid" != "null" ]; then
    printf '%s' "$proj_uuid"; return 0
  fi
  body="$(mktemp "${TMPDIR:-/tmp}/hefesto_body.XXXXXX")"
  printf '{"name":"mvps","description":"MVPs desplegados desde hefesto-mvps-coolify"}' > "$body"
  proj_resp="$(api POST /projects "$body")" || { error "no se pudo crear el proyecto"; rm -f "$body"; return 1; }
  rm -f "$body"
  proj_uuid="$(printf '%s' "$proj_resp" | jq -r '.uuid')"
  if [ -z "$proj_uuid" ] || [ "$proj_uuid" = "null" ]; then
    error "no se pudo obtener uuid del proyecto mvps"; return 1
  fi
  printf '%s' "$proj_uuid"
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
