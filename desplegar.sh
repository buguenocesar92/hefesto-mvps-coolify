#!/usr/bin/env bash
# desplegar.sh (--apps a,b | --grupo liviana|media|pesada | --todas) [--dry-run|--ejecutar] [--publicar]
# Crea o actualiza aplicaciones de Coolify desde apps.tsv.
set -eo pipefail
# shellcheck shell=bash
RAIZ_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comun.sh
source "$RAIZ_LIB/lib/comun.sh"
# shellcheck source=lib/coolify.sh
source "$RAIZ_LIB/lib/coolify.sh"
# shellcheck source=lib/secretos.sh
source "$RAIZ_LIB/lib/secretos.sh"

APPS_FILE="${APPS_TSV:-$RAIZ_LIB/apps.tsv}"
REPOS_DIR="${REPOS_DIR:-$HOME/Dev}"
PUBLICAR=0
MODO=""

log_aplicacion() { log "$1"; }
resumen_estado() {
  local s
  if [ -f "$ESTADO_DIR/apps.tsv" ]; then
    awk -F'\t' 'NR>0 {print $3}' "$ESTADO_DIR/apps.tsv" | sort | uniq -c | sed 's/^/  /'
  fi
}

error() { printf 'error: %s\n' "$*" >&2; }
uso() {
  cat >&2 <<USO
uso: $(basename "$0") (--apps a,b | --grupo liviana|media|pesada | --todas)
                      [--dry-run|--ejecutar] [--publicar]
USO
}

# parse argumentos
apps_seleccion=()
grupo_seleccion=""
todas=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apps) IFS=',' read -r -a apps_seleccion <<< "${2:-}"; shift 2 ;;
    --grupo) grupo_seleccion="${2:-}"; shift 2 ;;
    --todas) todas=1; shift ;;
    --dry-run) MODO="${MODO:-dry}"; shift ;;
    --ejecutar) MODO="${MODO:-ejecutar}"; shift ;;
    --publicar) PUBLICAR=1; shift ;;
    -h|--help) uso; exit 0 ;;
    *) error "argumento desconocido: $1"; uso; exit 2 ;;
  esac
done

[ -n "$MODO" ] || { error "falta --dry-run o --ejecutar"; uso; exit 2; }
[ "${#apps_seleccion[@]}" -gt 0 ] || [ -n "$grupo_seleccion" ] || [ "$todas" -eq 1 ] || {
  error "falta --apps, --grupo o --todas"; uso; exit 2; }

preparar_estado
# Solo crear/asegurar el archivo si no existe — nunca truncar.
[ -f "$ESTADO_DIR/apps.tsv" ] || : > "$ESTADO_DIR/apps.tsv"
chmod 600 "$ESTADO_DIR/apps.tsv" 2>/dev/null || true

# valida cada app seleccionada.
seleccionar_apps() {
  if [ "${#apps_seleccion[@]}" -gt 0 ]; then
    for s in "${apps_seleccion[@]}"; do printf '%s\n' "$s"; done
    return
  fi
  if [ "$todas" -eq 1 ]; then
    awk -F'\t' 'NR>1 {print $1}' "$APPS_FILE"
    return
  fi
  if [ -n "$grupo_seleccion" ]; then
    awk -F'\t' -v g="$grupo_seleccion" 'NR>1 && $9==g {print $1}' "$APPS_FILE"
    return
  fi
}

# registrar en estado: <slug><TAB><uuid><TAB><estado><TAB><url opcional><TAB><fecha>
registrar_estado() {
  local slug="$1" uuid="$2" estado="$3" url="${4:-}"
  local fecha; fecha="$(date '+%F %T')"
  local tmp; tmp="$(mktemp "$ESTADO_DIR/.apps.XXXXXX")"
  ( umask 077
    if [ -f "$ESTADO_DIR/apps.tsv" ]; then
      awk -F'\t' -v s="$slug" '$1 != s' "$ESTADO_DIR/apps.tsv" >> "$tmp"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$slug" "$uuid" "$estado" "$url" "$fecha" >> "$tmp"
    mv "$tmp" "$ESTADO_DIR/apps.tsv"
    chmod 600 "$ESTADO_DIR/apps.tsv" 2>/dev/null || true
  )
}

# valida el slug contra apps.tsv
validar_app() {
  local slug="$1"
  slug_valido "$slug" || { error "slug inválido: $slug"; return 1; }
  fila "$slug" >/dev/null || { error "no existe app $slug en apps.tsv"; return 1; }
}

validar_compose_app() {
  local slug="$1" repo="$2" base_dir="$3" compose_file="$4"
  local repo_path="$REPOS_DIR/$repo"
  [ -d "$repo_path" ] || { error "no existe repo local: $repo_path"; return 1; }
  local tmpdir; tmpdir="$(mktemp -d "$ESTADO_DIR/compose.XXXXXX")"
  chmod 700 "$tmpdir"
  if ! git -C "$repo_path" archive coolify -- "$base_dir" 2>"$tmpdir/.giterr" | tar -xf - -C "$tmpdir" --strip-components=1 2>"$tmpdir/.tarerr"; then
    error "git archive falló para $repo: giterr=$(cat "$tmpdir/.giterr" 2>/dev/null) tarerr=$(cat "$tmpdir/.tarerr" 2>/dev/null)"
    rm -rf "$tmpdir"; return 1
  fi
  if [ "$base_dir" = "/" ] || [ -z "$base_dir" ]; then
    local proyecto_dir="$tmpdir"
  else
    local base_norm="${base_dir#/}"; local proyecto_dir="$tmpdir/$base_norm"
  fi
  if ! "$RAIZ_LIB/validar-compose.sh" "$proyecto_dir" "$compose_file"; then
    rm -rf "$tmpdir"; return 1
  fi
  rm -rf "$tmpdir"
  return 0
}

ver_uuid_app() {
  awk -F'\t' -v s="$1" '$1==s {print $2; exit}' "$ESTADO_DIR/apps.tsv" 2>/dev/null
}

# Genera JSON para PATCH envs/bulk con render_env (no imprime secretos en logs).
generar_envs_json() {
  local slug="$1"
  local tmp_env; tmp_env="$(mktemp "${TMPDIR:-/tmp}/hefesto_envs.XXXXXX")"
  chmod 600 "$tmp_env"
  if ! render_env "$slug" > "$tmp_env"; then
    error "render_env falló para $slug"; rm -f "$tmp_env"; return 1
  fi
  cat "$tmp_env"
  rm -f "$tmp_env"
}

if [ "$MODO" = "dry" ]; then
  # Solo se hace 1 llamada a la API si hay token: GET /version
  if [ -f "${COOLIFY_TOKEN_FILE:-/nada}" ]; then
    api GET /version >/dev/null 2>&1 || true
  fi
  # Recorrer apps e imprimir plan
  mapfile -t apps_iter < <(seleccionar_apps | sort -u)
  for slug in "${apps_iter[@]}"; do
    [ -z "$slug" ] && continue
    fila="$slug"; [ -n "$fila" ] || continue
    repo="$(campo "$slug" 2)"; bd="$(campo "$slug" 8)"; grupo="$(campo "$slug" 9)"
    alta_privada="$(campo "$slug" 10)"; servicio="$(campo "$slug" 5)"; puerto="$(campo "$slug" 6)"
    vars_n="$(awk -F'\t' -v s="$slug" '$1==s {n=split($13,a,","); print n}' "$APPS_FILE")"
    host="$slug.$DOMINIO_BASE"
    if [ "$alta_privada" = "si" ] && [ "$PUBLICAR" -eq 0 ]; then
      dom="sin dominio (alta privada)"
    else
      dom="https://$host"
    fi
    if [ "$grupo" = "pesada" ]; then
      accion="dejar detenida"
    else
      accion="desplegar"
    fi
    printf '%s: %s, dominio %s, %s variables, %s\n' "$slug" "crear|actualizar app" "$dom" "$vars_n" "$accion"
  done
  exit 0
fi

# Modo --ejecutar
if ! coolify_validar; then exit 1; fi

# Servidor
if [ -n "${COOLIFY_SERVER_UUID:-}" ]; then
  server_uuid="$COOLIFY_SERVER_UUID"
else
  servers="$(api GET /servers)" || { error "no se pudo listar servers"; exit 1; }
  server_uuid="$(printf '%s' "$servers" | jq -r '.[0].uuid')"
  if [ -z "$server_uuid" ] || [ "$server_uuid" = "null" ]; then
    error "no hay servers configurados"; exit 1
  fi
fi

# Proyecto mvps
proyectos="$(api GET /projects)" || proyectos="[]"
proj_uuid="$(printf '%s' "$proyectos" | jq -r --arg n "mvps" '.[] | select(.name==$n) | .uuid' | head -1)"
if [ -z "$proj_uuid" ] || [ "$proj_uuid" = "null" ]; then
  body="$(mktemp "${TMPDIR:-/tmp}/hefesto_body.XXXXXX")"; printf '{"name":"mvps","description":"MVPs desplegados desde hefesto-mvps-coolify"}' > "$body"
  proj_resp="$(api POST /projects "$body")" || { error "no se pudo crear el proyecto"; rm -f "$body"; exit 1; }
  rm -f "$body"
  proj_uuid="$(printf '%s' "$proj_resp" | jq -r '.uuid')"
fi
log "proyecto mvps: $proj_uuid"

mapfile -t apps_iter < <(seleccionar_apps | sort -u)
for slug in "${apps_iter[@]}"; do
  [ -z "$slug" ] && continue
  if ! validar_app "$slug"; then continue; fi
  repo="$(campo "$slug" 2)"; base_dir="$(campo "$slug" 3)"; compose_file="$(campo "$slug" 4)"
  servicio="$(campo "$slug" 5)"; puerto="$(campo "$slug" 6)"
  servicios_extra="$(campo "$slug" 7)"
  bd="$(campo "$slug" 8)"; grupo="$(campo "$slug" 9)"
  alta_privada="$(campo "$slug" 10)"; necesita_smtp="$(campo "$slug" 11)"
  # bd se usa por validar_compose_app indirectamente (referencia apps.tsv); alta_privada y necesita_smtp
  # condicionan el dominio/SMTP más abajo.
  : "${bd:=}" "${alta_privada:=no}" "${necesita_smtp:=no}"

  if ! validar_compose_app "$slug" "$repo" "$base_dir" "$compose_file"; then
    log_aplicacion "RECHAZADO_COMPOSE $slug"
    registrar_estado "$slug" "" "RECHAZADO_COMPOSE"
    continue
  fi

  # UUID: si ya existe en estado, usarlo; si no, crear.
  app_uuid="$(ver_uuid_app "$slug")"
  if [ -z "$app_uuid" ]; then
    body="$(mktemp "${TMPDIR:-/tmp}/hefesto_body.XXXXXX")"
    jq -n --arg p "$proj_uuid" --arg s "$server_uuid" --arg n "$slug" \
           --arg b "coolify" --arg bd "$base_dir" --arg cf "$compose_file" \
      '{project_uuid:$p, server_uuid:$s, environment_name:"production",
        git_repository:("https://github.com/buguenocesar92/" + $n),
        git_branch:$b, build_pack:"dockercompose", base_directory:$bd,
        docker_compose_location:$cf, name:$n, instant_deploy:false}' > "$body"
    app_resp="$(api POST /applications/public "$body")" || { error "no se pudo crear app $slug"; rm -f "$body"; continue; }
    rm -f "$body"
    app_uuid="$(printf '%s' "$app_resp" | jq -r '.uuid')"
    if [ -z "$app_uuid" ] || [ "$app_uuid" = "null" ]; then
      error "app $slug sin uuid"
      continue
    fi
  fi

  # Esperar docker_compose_raw
  waits=0
  while [ "$waits" -lt 24 ]; do
    waits=$((waits + 1))
    app="$(api GET "/applications/$app_uuid")" || app=""
    raw="$(printf '%s' "$app" | jq -r '.docker_compose_raw // ""')"
    if [ -n "$raw" ]; then break; fi
    sleep 1
  done
  if [ -z "$raw" ]; then
    error "compose no listo para $slug tras espera"
    continue
  fi

  # Variables
  envs_json="$(generar_envs_json "$slug")" || continue
  envs_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_envs_body.XXXXXX")"; printf '%s' "$envs_json" > "$envs_body"
  api PATCH "/applications/$app_uuid/envs/bulk" "$envs_body" >/dev/null || { error "envs/bulk falló para $slug"; rm -f "$envs_body"; continue; }
  rm -f "$envs_body"

  # Dominio
  host="$slug.$DOMINIO_BASE"
  if [ "$alta_privada" = "no" ] || [ "$PUBLICAR" -eq 1 ]; then
    domains="$(jq -n --arg n "$servicio" --arg u "https://$host:$puerto" \
      '{docker_compose_domains:[{name:$n, domain:$u}]}')"
    if [ -n "$servicios_extra" ]; then
      extra_domains=""
      for s in $(echo "$servicios_extra" | tr ',' ' '); do
        [ -z "$s" ] && continue
        extra_domains="$extra_domains $(jq -n --arg n "$s" --arg u "https://$s.$DOMINIO_BASE" '{name:$n, domain:$u}')"
      done
      domains="$(jq -n --argjson d1 "$(printf '%s' "$domains" | jq '.docker_compose_domains')" \
                              --argjson d2 "$(printf '[%s]' "${extra_domains:-}")" \
        '{docker_compose_domains: ($d1 + $d2)}')"
    fi
    patch_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_patch.XXXXXX")"; printf '%s' "$domains" > "$patch_body"
    api PATCH "/applications/$app_uuid" "$patch_body" >/dev/null || { error "dominio falló para $slug"; rm -f "$patch_body"; continue; }
    rm -f "$patch_body"
  fi

  # Deploy o detener
  if [ "$grupo" = "pesada" ]; then
    api POST "/applications/$app_uuid/start" >/dev/null 2>&1 || true
    registrar_estado "$slug" "$app_uuid" "CREADA_DETENIDA"
    continue
  fi

  api POST "/deploy?uuid=$app_uuid&force=false" >/dev/null || { error "deploy falló para $slug"; continue; }
  if [ "$alta_privada" = "no" ] || [ "$PUBLICAR" -eq 1 ]; then
    registrar_estado "$slug" "$app_uuid" "DESPLEGADA" "https://$host"
  else
    registrar_estado "$slug" "$app_uuid" "DESPLEGADA_SIN_DOMINIO"
  fi
done

log "Resumen:"
resumen_estado
