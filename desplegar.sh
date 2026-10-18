#!/usr/bin/env bash
# desplegar.sh (--apps a,b | --grupo liviana|media|pesada | --todas) [--dry-run|--ejecutar] [--publicar]
# Crea o actualiza aplicaciones de Coolify desde apps.tsv. Modo por defecto: --dry-run.
set -euo pipefail
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

[ -n "$MODO" ] || MODO="dry"
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
  local proyecto_dir
  if [ "$base_dir" = "/" ] || [ -z "$base_dir" ]; then
    proyecto_dir="$tmpdir"
    if ! git -C "$repo_path" archive coolify 2>"$tmpdir/.giterr" | tar -xf - -C "$tmpdir" 2>"$tmpdir/.tarerr"; then
      error "git archive falló para $repo: giterr=$(cat "$tmpdir/.giterr" 2>/dev/null) tarerr=$(cat "$tmpdir/.tarerr" 2>/dev/null)"
      rm -rf "$tmpdir"; return 1
    fi
  else
    local base_norm="${base_dir#/}"
    proyecto_dir="$tmpdir/$base_norm"
    if ! git -C "$repo_path" archive coolify -- "$base_norm" 2>"$tmpdir/.giterr" | tar -xf - -C "$tmpdir" 2>"$tmpdir/.tarerr"; then
      error "git archive falló para $repo: giterr=$(cat "$tmpdir/.giterr" 2>/dev/null) tarerr=$(cat "$tmpdir/.tarerr" 2>/dev/null)"
      rm -rf "$tmpdir"; return 1
    fi
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

# pendientes_de <slug>: imprime, una por línea, las variables de la plantilla que valen {{PENDIENTE}}.
pendientes_de() {
  local plantilla="${ENVS_DIR:-$RAIZ/envs}/$1.tpl"
  [ -f "$plantilla" ] || return 0
  grep -E '^[A-Z][A-Z0-9_]*=.*\{\{PENDIENTE\}\}' "$plantilla" | cut -d= -f1 || true
}

# Genera JSON para PATCH envs/bulk con render_env (no imprime secretos en logs).
generar_envs_json() {
  local slug="$1"
  local tmp_env; tmp_env="$(mktemp "${TMPDIR:-/tmp}/hefesto_envs.XXXXXX")"
  chmod 600 "$tmp_env"
  if ! render_env "$slug" > "$tmp_env" 2> "$tmp_env.err"; then
    error "render_env falló para $slug"
    rm -f "$tmp_env" "$tmp_env.err"
    return 1
  fi
  cat "$tmp_env"
  rm -f "$tmp_env" "$tmp_env.err"
}

if [ "$MODO" = "dry" ]; then
  # Solo se hace 1 llamada a la API si hay token: GET /version
  if [ -f "${COOLIFY_TOKEN_FILE:-/nada}" ]; then
    api GET /version >/dev/null 2>&1 || true
  fi
  # Recorrer apps, validar slug y compose, e imprimir plan
  mapfile -t apps_iter < <(seleccionar_apps | sort -u)
  for slug in "${apps_iter[@]}"; do
    [ -z "$slug" ] && continue
    if ! validar_app "$slug"; then
      printf '%s: slug inválido\n' "$slug"
      continue
    fi
    repo="$(campo "$slug" 2)"; base_dir="$(campo "$slug" 3)"; compose_file="$(campo "$slug" 4)"
    bd="$(campo "$slug" 8)"; grupo="$(campo "$slug" 9)"
    alta_privada="$(campo "$slug" 10)"; servicio="$(campo "$slug" 5)"; puerto="$(campo "$slug" 6)"
    vars_n="$(awk -F'\t' -v s="$slug" '$1==s {n=split($13,a,","); print n}' "$APPS_FILE")"
    host="$slug.$DOMINIO_BASE"
    if ! validar_compose_app "$slug" "$repo" "$base_dir" "$compose_file"; then
      printf '%s: RECHAZADO_COMPOSE\n' "$slug"
      continue
    fi
    mapfile -t pend < <(pendientes_de "$slug")
    if [ "${#pend[@]}" -gt 0 ]; then
      printf '%s: NECESITA_DATOS (%s)\n' "$slug" "${pend[*]}"
      continue
    fi
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
server_uuid="$(coolify_server_uuid)" || exit 1

# Proyecto mvps
proj_uuid="$(coolify_proyecto_mvps)" || exit 1
log "proyecto mvps: $proj_uuid"

fallos=0
pendientes_total=0
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
    registrar_estado "$slug" "$(ver_uuid_app "$slug")" "RECHAZADO_COMPOSE"
    fallos=$((fallos + 1))
    continue
  fi

  mapfile -t pend < <(pendientes_de "$slug")
  if [ "${#pend[@]}" -gt 0 ]; then
    log "NECESITA_DATOS $slug: ${pend[*]}"
    registrar_estado "$slug" "$(ver_uuid_app "$slug")" "NECESITA_DATOS"
    pendientes_total=$((pendientes_total + 1))
    continue
  fi

  # UUID: si ya existe en estado, usarlo; si no, crear.
  app_uuid="$(ver_uuid_app "$slug")"
  if [ -z "$app_uuid" ]; then
    body="$(mktemp "${TMPDIR:-/tmp}/hefesto_body.XXXXXX")"
    jq -n --arg p "$proj_uuid" --arg s "$server_uuid" --arg n "$slug" --arg r "$repo" \
           --arg b "coolify" --arg bd "$base_dir" --arg cf "$compose_file" \
      '{project_uuid:$p, server_uuid:$s, environment_name:"production",
        git_repository:("https://github.com/buguenocesar92/" + $r),
        git_branch:$b, build_pack:"dockercompose", base_directory:$bd,
        docker_compose_location:$cf, name:$n, instant_deploy:false,
        connect_to_docker_network:true}' > "$body"
    app_resp="$(api POST /applications/public "$body")" || { error "no se pudo crear app $slug"; rm -f "$body"; registrar_estado "$slug" "" "ERROR_CREAR"; fallos=$((fallos + 1)); continue; }
    rm -f "$body"
    app_uuid="$(printf '%s' "$app_resp" | jq -r '.uuid')"
    if [ -z "$app_uuid" ] || [ "$app_uuid" = "null" ]; then
      error "app $slug sin uuid"
      registrar_estado "$slug" "" "ERROR_UUID"
      fallos=$((fallos + 1))
      continue
    fi
  fi

  # Esperar docker_compose_raw (hasta 120 s con sondeo cada 5 s).
  ESPERA_SONDEO="${ESPERA_SONDEO:-5}"
  waits=0
  while [ "$waits" -lt 24 ]; do
    waits=$((waits + 1))
    app="$(api GET "/applications/$app_uuid")" || app=""
    raw="$(printf '%s' "$app" | jq -r '.docker_compose_raw // ""')"
    if [ -n "$raw" ]; then break; fi
    sleep "$ESPERA_SONDEO"
  done
  if [ -z "$raw" ]; then
    error "compose no listo para $slug tras espera"
    registrar_estado "$slug" "$app_uuid" "ERROR_COMPOSE_RAW"
    fallos=$((fallos + 1))
    continue
  fi

  # Variables
  envs_json="$(generar_envs_json "$slug")" || {
    registrar_estado "$slug" "$app_uuid" "ERROR_ENVS"; fallos=$((fallos + 1)); continue; }
  envs_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_envs_body.XXXXXX")"; printf '%s' "$envs_json" > "$envs_body"
  api PATCH "/applications/$app_uuid/envs/bulk" "$envs_body" >/dev/null || { error "envs/bulk falló para $slug"; rm -f "$envs_body"; registrar_estado "$slug" "$app_uuid" "ERROR_ENVS_BULK"; fallos=$((fallos + 1)); continue; }
  rm -f "$envs_body"

  # --publicar: lee `# publicar: VAR=VALOR` de la plantilla y sobreescribe en el JSON.
  if [ "$PUBLICAR" -eq 1 ]; then
    plantilla_pub="${ENVS_DIR:-$RAIZ/envs}/$slug.tpl"
    if [ -f "$plantilla_pub" ]; then
      pubs="$(grep -E '^# publicar: [A-Z][A-Z0-9_]*=(.+)$' "$plantilla_pub" | sed 's/^# publicar: //' || true)"
      if [ -n "$pubs" ]; then
        reenv_body="$(mktemp "${TMPDIR:-/tmp}/hefesto_pub.XXXXXX")"
        printf '%s' "$envs_json" > "$reenv_body"
        while IFS= read -r linea_pub; do
          [ -z "$linea_pub" ] && continue
          var_pub="${linea_pub%%=*}"
          val_pub="${linea_pub#*=}"
          if ! jq --arg k "$var_pub" --arg v "$val_pub" \
            '.data |= map(if .key == $k then .value = $v else . end)' \
            "$reenv_body" > "$reenv_body.tmp"; then
            error "--publicar: jq falló para $var_pub"
            rm -f "$reenv_body" "$reenv_body.tmp"
            continue
          fi
          mv "$reenv_body.tmp" "$reenv_body"
        done <<< "$pubs"
        api PATCH "/applications/$app_uuid/envs/bulk" "$reenv_body" >/dev/null || { error "public envs/bulk falló para $slug"; rm -f "$reenv_body"; registrar_estado "$slug" "$app_uuid" "ERROR_PUBLIC_ENVS"; fallos=$((fallos + 1)); continue; }
        rm -f "$reenv_body"
      fi
    fi
  fi

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
    api PATCH "/applications/$app_uuid" "$patch_body" >/dev/null || { error "dominio falló para $slug"; rm -f "$patch_body"; registrar_estado "$slug" "$app_uuid" "ERROR_DOMINIO"; fallos=$((fallos + 1)); continue; }
    rm -f "$patch_body"
  fi

  # Deploy o detener. Con --publicar, las pesadas también se despliegan (César las
  # revisó y quiere que arranquen con el setup inicial en true).
  if [ "$grupo" = "pesada" ] && [ "$PUBLICAR" -ne 1 ]; then
    registrar_estado "$slug" "$app_uuid" "CREADA_DETENIDA"
    continue
  fi

  api POST "/deploy?uuid=$app_uuid&force=false" >/dev/null || { error "deploy falló para $slug"; registrar_estado "$slug" "$app_uuid" "ERROR_DEPLOY"; fallos=$((fallos + 1)); continue; }
  if [ "$alta_privada" = "no" ] || [ "$PUBLICAR" -eq 1 ]; then
    registrar_estado "$slug" "$app_uuid" "DESPLEGADA" "https://$host"
  else
    registrar_estado "$slug" "$app_uuid" "DESPLEGADA_SIN_DOMINIO"
  fi
done

log "Resumen:"
resumen_estado
if [ "$pendientes_total" -gt 0 ]; then
  exit 1
fi
exit $(( fallos > 0 ))
