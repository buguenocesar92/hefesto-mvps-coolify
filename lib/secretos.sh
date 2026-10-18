#!/usr/bin/env bash
# secretos.sh: generación idempotente de secretos por app y sustitución de marcadores
# en plantillas envs/<slug>.tpl. Imprime JSON por stdout, listo para PATCH envs/bulk.
# shellcheck shell=bash
HTPASSWD="${HTPASSWD_BIN:-htpasswd}"
PYTHON="${PYTHON_BIN:-python3}"

# secreto <slug> <VAR> <formato>: emite a stdout el valor; lo guarda en $ESTADO_DIR/<slug>.env.
# Formatos: hex64, hex32, hex96, b64-32, alnum24, laravel, bcrypt:<VAR_PLANO>, pbkdf2:<VAR_PLANO>.
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
    laravel) valor="base64:$(openssl rand -base64 32)" ;;
    pbkdf2:*)
      local var_plano_p="${fmt#pbkdf2:}" plano_p sal
      plano_p="$(secreto "$slug" "$var_plano_p" "alnum24")" || return 1
      sal="$(openssl rand -hex 32)"
      valor="$(printf '%s\n%s\n' "$plano_p" "$sal" | "$PYTHON" -I -c 'import sys,hashlib,base64
p,s=sys.stdin.read().split("\n")[:2]
s=bytes.fromhex(s)
print(base64.b64encode(s+hashlib.pbkdf2_hmac("sha256",p.encode(),s,100000)).decode())')" || return 1
      [ -n "$valor" ] || { error "pbkdf2 no generó valor"; return 1; }
      ;;
    bcrypt:*)
      local var_plano="${fmt#bcrypt:}"
      local plano
      plano="$(secreto "$slug" "$var_plano" "alnum24")" || return 1
      valor="$(printf '%s\n' "$plano" | "$HTPASSWD" -n -i -B -C 12 usuario | cut -d: -f2-)"
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

# obtener_resend_key [archivo]: imprime a stdout la primera clave de Resend que empiece por `re_`
# del archivo (por defecto $RESEND_ENV_FILE o $HOME/.config/hefesto/resend.env). Acepta tanto
# `RESEND_API_KEY=re_xxx` como una variable cualquiera `OTRA=re_xxx`; ignora comentarios y líneas
# vacías. Sale 1 si no encuentra ninguna.
obtener_resend_key() {
  local rf="${1:-${RESEND_ENV_FILE:-$HOME/.config/hefesto/resend.env}}"
  local rkey
  rkey="$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*re_' "$rf" 2>/dev/null \
    | head -1 | sed -E 's/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*//')" || true
  if [ -z "$rkey" ]; then return 1; fi
  printf '%s' "$rkey"
}

# expandir_marcador <slug> <VAR> <valor>: reemplaza los marcadores conocidos en el valor.
expandir_marcador() {
  local slug="$1" var="$2" valor="$3" db_slug
  db_slug="${slug//-/_}"
  # Si existe $ESTADO_DIR/supabase.uuid, los hosts internos usan el uuid real del servicio.
  local supa_uuid="" db_host_real="supabase-db" kong_url_real="http://supabase-kong:8000"
  if [ -n "${SUPABASE_UUID_FILE:-}" ] && [ -f "$SUPABASE_UUID_FILE" ]; then
    supa_uuid="$(cat "$SUPABASE_UUID_FILE" 2>/dev/null || true)"
  elif [ -f "${ESTADO_DIR:-/nada}/supabase.uuid" ]; then
    supa_uuid="$(cat "${ESTADO_DIR:-/nada}/supabase.uuid" 2>/dev/null || true)"
  fi
  if [ -n "$supa_uuid" ]; then
    db_host_real="supabase-db-$supa_uuid"
    kong_url_real="http://supabase-kong-$supa_uuid:8000"
  fi
  valor="${valor//\{\{HOST\}\}/${slug}.$DOMINIO_BASE}"
  while [[ "$valor" =~ \{\{HOST:([a-z0-9-]+)\}\} ]]; do
    valor="${valor//"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}.$DOMINIO_BASE"}"
  done
  valor="${valor//\{\{URL\}\}/https://${slug}.$DOMINIO_BASE}"
  valor="${valor//\{\{DB_HOST\}\}/${SUPABASE_DB_HOST:-$db_host_real}}"
  valor="${valor//\{\{DB_NAME\}\}/mvp_${db_slug}}"
  valor="${valor//\{\{SUPABASE_URL\}\}/${SUPABASE_INTERNAL_URL:-$kong_url_real}}"

  while [[ "$valor" =~ \{\{DB_PASSWORD\}\} ]]; do
    local dbp; dbp="$(secreto "$slug" DB_PASSWORD hex64)" || return 1
    valor="${valor/\{\{DB_PASSWORD\}\}/$dbp}"
  done
  while [[ "$valor" =~ \{\{GEN:([^}]+)\}\} ]]; do
    local fmt="${BASH_REMATCH[1]}" gen
    gen="$(secreto "$slug" "$var" "$fmt")" || return 1
    valor="${valor//\{\{GEN:${fmt}\}\}/${gen}}"
  done

  if [[ "$valor" =~ \{\{ADMIN_EMAIL\}\} ]]; then
    local ae="${HEFESTO_ADMIN_EMAIL:-}"
    if [ -z "$ae" ]; then error "$var: HEFESTO_ADMIN_EMAIL no definido"; return 1; fi
    if ! printf '%s' "$ae" | grep -qE '^[^@ ]+@[^@ ]+\.[a-z]{2,}$'; then
      error "$var: HEFESTO_ADMIN_EMAIL con formato inválido"; return 1
    fi
    valor="${valor//\{\{ADMIN_EMAIL\}\}/${ae}}"
  fi

  if [[ "$valor" =~ \{\{SUPABASE_SECRET_KEY\}\} ]]; then
    local kf="${SUPABASE_KEY_FILE:-$HOME/.config/hefesto/supabase-service-key}" perms contenido
    [ -f "$kf" ] || { error "falta el archivo $kf"; return 1; }
    perms="$(stat -c %a "$kf")"
    [ "$((8#${perms} & 077))" -eq 0 ] || { error "$kf debe ser 0600"; return 1; }
    contenido="$(cat "$kf")"
    valor="${valor//\{\{SUPABASE_SECRET_KEY\}\}/${contenido}}"
  fi

  if [[ "$valor" =~ \{\{RESEND_API_KEY\}\} ]]; then
    local rf="${RESEND_ENV_FILE:-$HOME/.config/hefesto/resend.env}" rkey
    [ -f "$rf" ] || { error "no encuentro la API key de Resend en $rf"; return 1; }
    if ! rkey="$(obtener_resend_key "$rf")"; then
      error "no encuentro la API key de Resend en $rf"; return 1
    fi
    valor="${valor//\{\{RESEND_API_KEY\}\}/${rkey}}"
  fi

  if [[ "$valor" =~ \{\{SUPABASE_ANON_KEY\}\} ]]; then
    local akf="${SUPABASE_ANON_KEY_FILE:-$HOME/.config/hefesto/supabase-anon-key}" aperms acontenido
    [ -f "$akf" ] || { error "falta el archivo $akf"; return 1; }
    aperms="$(stat -c %a "$akf")"
    [ "$((8#${aperms} & 077))" -eq 0 ] || { error "$akf debe ser 0600"; return 1; }
    acontenido="$(cat "$akf")"
    valor="${valor//\{\{SUPABASE_ANON_KEY\}\}/${acontenido}}"
  fi
  printf '%s' "$valor"
}

# render_env <slug>: imprime JSON {"data":[{key,value,is_literal:true,is_preview:false},...]}
# Arma el array con jq -n --arg para no interpolar valores en el texto.
render_env() {
  local slug="$1"
  local plantilla="${ENVS_DIR:-$RAIZ/envs}/$slug.tpl"
  [ -f "$plantilla" ] || { error "no existe plantilla $plantilla"; return 1; }

  local pares=()
  local pendientes=()
  local -A resueltos=()
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
      pendientes+=("$var")
      printf 'pendiente: %s=%s\n' "$slug" "$var" >&2
      continue
    fi
    while [[ "$valor" =~ \{\{COPIA:([A-Z][A-Z0-9_]*)\}\} ]]; do
      local fuente="${BASH_REMATCH[1]}" marca="${BASH_REMATCH[0]}"
      if [ -z "${resueltos[$fuente]+x}" ]; then
        error "$var: {{COPIA:$fuente}} necesita que $fuente aparezca antes en $plantilla"; return 1
      fi
      valor="${valor//"$marca"/"${resueltos[$fuente]}"}"
    done
    if ! expandir_marcador "$slug" "$var" "$valor" >/dev/null; then
      return 1
    fi
    local resuelto
    resuelto="$(expandir_marcador "$slug" "$var" "$valor")" || return 1
    pares+=("$var" "$resuelto")
    resueltos["$var"]="$resuelto"
  done < "$plantilla"

  if [ "${#pendientes[@]}" -gt 0 ]; then
    return 1
  fi

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
