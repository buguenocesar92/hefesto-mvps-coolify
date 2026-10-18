#!/usr/bin/env bats
# validar-compose.sh con docker compose REAL (nunca tests/stubs/docker): rechaza privileged, cap_add,
# docker.sock, binds fuera del proyecto, network_mode host, ports y container_name; ignora profiles.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  # preparar_entorno antepone tests/stubs (que trae un stub de docker) al PATH: se quita aquí.
  PATH="${PATH#"$RAIZ/tests/stubs:"}"; export PATH
  DOCKER_BIN="$(command -v docker || true)"; export DOCKER_BIN
  [ -n "$DOCKER_BIN" ] || skip "docker no disponible"
  "$DOCKER_BIN" compose version >/dev/null 2>&1 || skip "docker compose no disponible"
  export PROYECTO="$BATS_TEST_TMPDIR/p"; mkdir -p "$PROYECTO"
}

escribir() { printf '%s\n' "$1" > "$PROYECTO/compose.yaml"; }

@test "usa el docker real, no el stub de tests/stubs" {
  [[ "$DOCKER_BIN" != "$RAIZ/tests/stubs/"* ]]
  [[ "$(command -v docker)" != "$RAIZ/tests/stubs/"* ]]
}

@test "acepta nginx con bind interno" {
  escribir 'services:
  web:
    image: nginx
    volumes:
      - "./ops:/ops:ro"
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
}

@test "rechaza privileged" {
  escribir 'services:
  web:
    image: nginx
    privileged: true
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: privileged"* ]]
}

@test "rechaza cap_add (solo lo ve docker real: el stub no emite cap_add)" {
  escribir 'services:
  web:
    image: nginx
    cap_add: [SYS_ADMIN]
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: cap_add no vacío"* ]]
}

@test "rechaza ports" {
  escribir 'services:
  web:
    image: nginx
    ports:
      - "127.0.0.1:3080:3000"
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: ports"* ]]
}

@test "rechaza container_name" {
  escribir 'services:
  web:
    image: nginx
    container_name: xx
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: container_name"* ]]
}

@test "rechaza bind con docker.sock" {
  escribir 'services:
  web:
    image: nginx
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: docker.sock"* ]]
}

@test "rechaza bind fuera del proyecto" {
  escribir 'services:
  web:
    image: nginx
    volumes:
      - "/etc:/host-etc"
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: bind fuera del proyecto"* ]]
}

@test "ignora servicios con profiles" {
  escribir 'services:
  web:
    image: nginx
  tools:
    image: alpine
    profiles: [tools]
    privileged: true
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
}

@test "rechaza network_mode host" {
  escribir 'services:
  web:
    image: nginx
    network_mode: host
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: network_mode host"* ]]
}
