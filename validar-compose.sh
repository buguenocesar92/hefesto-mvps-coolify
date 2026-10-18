#!/usr/bin/env bash
# validar-compose.sh <directorio> <archivo-compose>: sale 0 si el compose es apto para Coolify;
# 1 + una línea por problema en stderr (`<servicio>: <motivo>`).
# Política: nada de docker.sock, binds dentro del proyecto, sin privileged/cap_add/devices,
# sin network_mode host/container, sin pid/ipc host, sin ports (los asigna Coolify),
# sin container_name. Perfiles con `profiles:` se ignoran.
set -euo pipefail
# shellcheck shell=bash

DOCKER="${DOCKER_BIN:-docker}"

dir="$1" archivo="$2"
[ -d "$dir" ]    || { echo "directorio inválido: $dir" >&2; exit 2; }
[ -f "$dir/$archivo" ] || { echo "archivo compose no existe: $dir/$archivo" >&2; exit 2; }

dir_real="$(realpath "$dir")"
json="$("$DOCKER" compose --project-directory "$dir" -f "$dir/$archivo" config --no-interpolate --format json 2>/dev/null)" \
  || { echo "docker compose config falló" >&2; exit 2; }

problemas=0
emitir() { echo "$1: $2" >&2; problemas=1; }

# 1) Comprobaciones simples por servicio (jq emite un TSV por problema).
mapfile -t lineas_simples < <(echo "$json" | jq -r '
  .services | to_entries[]
  | select((.value.profiles // []) | length == 0)
  | .key as $s | .value as $v
  | (
      (if $v.privileged == true then [$s, "privileged"] else empty end),
      (if ($v.cap_add // [] | length) > 0 then [$s, "cap_add no vacío"] else empty end),
      (if ($v.devices // [] | length) > 0 then [$s, "devices no vacío"] else empty end),
      (if ($v.network_mode // "") == "host" or ($v.network_mode // "" | startswith("container:")) then [$s, "network_mode host"] else empty end),
      (if ($v.pid // "") == "host" then [$s, "pid host"] else empty end),
      (if ($v.ipc // "") == "host" then [$s, "ipc host"] else empty end),
      (if ($v.ports // [] | length) > 0 then [$s, "ports"] else empty end),
      (if ($v.container_name // "") != "" then [$s, "container_name"] else empty end),
      (($v.security_opt // []) | .[] | select(. == "apparmor:unconfined" or . == "seccomp:unconfined") | [$s, ("security_opt " + .)])
    ) | @tsv
')
for l in "${lineas_simples[@]}"; do
  [ -z "$l" ] && continue
  serv="${l%%	*}"; mot="${l#*	}"
  emitir "$serv" "$mot"
done

# 2) Binds: docker.sock o fuera del proyecto.
mapfile -t binds < <(echo "$json" | jq -r '
  .services | to_entries[]
  | select((.value.profiles // []) | length == 0)
  | .key as $s
  | (.value.volumes // []) | .[] | select(.type == "bind")
  | [$s, (.source // "")]
  | @tsv
')
for l in "${binds[@]}"; do
  [ -z "$l" ] && continue
  serv="${l%%	*}"; src="${l#*	}"
  [ -z "$src" ] && continue
  case "$src" in
    *docker.sock*) emitir "$serv" "docker.sock"; continue ;;
  esac
  if [[ "$src" != /* ]]; then
    src_resuelto="$dir_real/$src"
  else
    src_resuelto="$src"
  fi
  src_canonical="$(realpath -m --canonicalize-missing "$src_resuelto" 2>/dev/null || realpath -m "$src_resuelto")"
  case "$src_canonical/" in
    "$dir_real"/*) ;;
    *) emitir "$serv" "bind fuera del proyecto" ;;
  esac
done

exit "$problemas"
