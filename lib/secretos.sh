#!/usr/bin/env bash
# secretos.sh: generación idempotente de secretos por app y sustitución de marcadores
# en plantillas envs/<slug>.tpl. Imprime JSON por stdout, listo para PATCH envs/bulk.
# shellcheck shell=bash
HTPASSWD="${HTPASSWD_BIN:-htpasswd}"

# secreto <slug> <VAR> <formato>: emite a stdout el valor; lo guarda en $ESTADO_DIR/<slug>.env.
# Formatos: hex64, hex32, hex96, b64-32, alnum24, bcrypt:<VAR_PLANO>.
secreto() {
  local slug="$1" var="$2" fmt="$3"
  local arch="$ESTADO_DIR/$slug.env"
  preparar_estado

  local actual
  if [ -f "$arch" ]; then
    actual="$(grep -E "^${var}=" "$arch" 2>/dev/null | head -1 | cut -d= -f2-)"
  fi
  if [ -n "${actual:-}" ]; then
    printf '%s' "$actual"; return 0
  fi

  local valor
  case "$fmt" in
    hex64) valor="$(openssl rand -hex 32)" ;;
    hex32) valor="$(openssl rand -hex 16)" ;;
    hex96) valor="$(openssl rand -hex 48)" ;;
    b64-32) valor="$(openssl rand -base64 32 | tr -d '\n=+/' | cut -c1-43)" ;;
    alnum24) valor="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-24)" ;;
    bcrypt:*)
      local var_plano="${fmt#bcrypt:}"
      local plano
      plano="$(secreto "$slug" "$var_plano" "alnum24")" || return 1
      valor="$(printf '%s\n' "$plano" | "$HTPASSWD" -niB usuario | cut -d: -f2-)"
      [ -n "$valor" ] || { error "htpasswd no generó hash" >&2; return 1; }
      ;;
    *) error "formato inválido: $fmt"; return 1 ;;
  esac

  ( umask 077
    local tmp; tmp="$(mktemp "$ESTADO_DIR/.tmp.XXXXXX")"
    if [ -f "$arch" ]; then
      grep -v "^${var}=" "$arch" >> "$tmp" || true
    fi
    printf '%s=%s\n' "$var" "$valor" >> "$tmp"
    mv "$tmp" "$arch"
    chmod 600 "$arch"
  )
  chmod 700 "$ESTADO_DIR"
  printf '%s' "$valor"
}

# expandir_marcador <slug> <VAR> <valor>: reemplaza los marcadores conocidos en el valor.
expandir_marcador() {
  local slug="$1" var="$2" valor="$3" db_slug
  db_slug="${slug//-/_}"
  valor="${valor//\$\{SUPABASE_DB_HOST:-supabase-db\}/${SUPABASE_DB_HOST:-supabase-db}}"
  valor="${valor//\$\{SUPABASE_INTERNAL_URL:-http://supabase-kong:8000\}/${SUPABASE_INTERNAL_URL:-http://supabase-kong:8000}}"
  valor="${valor//\{\{HOST\}\}/${slug}.$DOMINIO_BASE}"
  valor="${valor//\{\{URL\}\}/https://${slug}.$DOMINIO_BASE}"
  valor="${valor//\{\{DB_HOST\}\}/\$\{SUPABASE_DB_HOST:-supabase-db\}}"
  valor="${valor//\{\{DB_NAME\}\}/mvp_${db_slug}}"
  valor="${valor//\{\{SUPABASE_URL\}\}/\$\{SUPABASE_INTERNAL_URL:-http://supabase-kong:8000\}}"

  while [[ "$valor" =~ \{\{DB_PASSWORD\}\} ]]; do
    local dbp; dbp="$(secreto "$slug" DB_PASSWORD hex32)" || return 1
    valor="${valor/\{\{DB_PASSWORD\}\}/$dbp}"
  done
  while [[ "$valor" =~ \{\{GEN:([^}]+)\}\} ]]; do
    local fmt="${BASH_REMATCH[1]}" gen
    gen="$(secreto "$slug" "$var" "$fmt")" || return 1
    valor="${valor//\{\{GEN:${fmt}\}\}/${gen}}"
  done
  while [[ "$valor" =~ \{\{SUPABASE_SECRET_KEY\}\} ]]; do
    local kf="${SUPABASE_KEY_FILE:-$HOME/.config/hefesto/supabase-service-key}" perms
    [ -f "$kf" ] || { error "falta el archivo $kf"; return 1; }
    perms="$(stat -c %a "$kf")"
    [ "$((8#${perms} & 077))" -eq 0 ] || { error "$kf debe ser 0600"; return 1; }
    local contenido; contenido="$(cat "$kf")"
    valor="${valor//\{\{SUPABASE_SECRET_KEY\}\}/${contenido}}"
  done
  printf '%s' "$valor"
}

# render_env <slug>: imprime JSON {"data":[{key,value,is_literal:true,is_preview:false},...]}
# Arma el array con jq -n --arg para no interpolar valores en el texto.
render_env() {
  local slug="$1"
  local plantilla="${ENVS_DIR:-$RAIZ/envs}/$slug.tpl"
  [ -f "$plantilla" ] || { error "no existe plantilla $plantilla"; return 1; }

  local pares=()
  local linea raw var valor
  while IFS= read -r linea || [ -n "$linea" ]; do
    # quitar comentarios finales y espacios sobrantes
    raw="${linea%%#*}"
    raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$raw" ] && continue
    if [[ "$raw" =~ ^([A-Z][A-Z0-9_]{0,63})=(.*)$ ]]; then
      var="${BASH_REMATCH[1]}"; valor="${BASH_REMATCH[2]}"
    else
      error "clave inválida en $plantilla: $linea"; return 1
    fi
    if [[ "$valor" == *\{\{PENDIENTE\}\}* ]]; then
      error "$var en $slug marcado PENDIENTE"; return 1
    fi
    if ! expandir_marcador "$slug" "$var" "$valor" >/dev/null; then
      return 1
    fi
    local resuelto
    resuelto="$(expandir_marcador "$slug" "$var" "$valor")" || return 1
    pares+=("$var" "$resuelto")
  done < "$plantilla"

  if [ "${#pares[@]}" -eq 0 ]; then
    echo '{"data":[]}'; return 0
  fi

  local -a jq_args=()
  local i=0 k v arr
  while [ "$i" -lt "${#pares[@]}" ]; do
    k="${pares[i]}"; v="${pares[i+1]}"
    arr=$((i / 2))
    jq_args+=(--arg "k$arr" "$k" --arg "v$arr" "$v")
    i=$((i + 2))
  done

  jq -n "${jq_args[@]}" '
    [ range(0; ($ARGS.named | keys | map(select(startswith("k"))) | length)) as $idx
      | { key: $ARGS.named["k\($idx)"],
          value: $ARGS.named["v\($idx)"],
          is_literal: true,
          is_preview: false } ]
    | { data: . }
  '
}
