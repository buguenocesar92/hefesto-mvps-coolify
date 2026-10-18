#!/usr/bin/env bats
# validar-compose.sh: rechaza privilegios, docker.sock, binds fuera del proyecto,
# network_mode host/container, pid/ipc host, ports y container_name.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  # Importante: NO usar tests/stubs en el PATH aquí; validar-compose.sh debe
  # hablar con `docker compose` real. Si no está disponible, skip.
  if ! command -v docker >/dev/null 2>&1; then skip "docker no disponible"; fi
  if ! docker compose version >/dev/null 2>&1; then skip "docker compose no disponible"; fi
  export PROYECTO="$BATS_TEST_TMPDIR/p"; mkdir -p "$PROYECTO"
}

escribir() { printf '%s\n' "$2" > "$PROYECTO/compose.yaml"; }
# respuesta admitida por `docker compose config --format json` para un servicio único:
#   {"services":{"web":{"image":"nginx","volumes":[...]}}}

@test "acepta nginx con bind interno" {
  escribir compose 'services:
  web:
    image: nginx
    volumes:
      - "./ops:/ops:ro"
'
  run "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
}

@test "rechaza privileged" {
  escribir compose 'services:
  web:
    image: nginx
    privileged: true
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: privileged"* ]]
}

@test "rechaza ports" {
  escribir compose 'services:
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
  escribir compose 'services:
  web:
    image: nginx
    container_name: xx
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: container_name"* ]]
}

@test "rechaza bind con docker.sock" {
  escribir compose 'services:
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
  escribir compose 'services:
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
  escribir compose 'services:
  tools:
    image: alpine
    profiles: [tools]
    privileged: true
'
  run "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 0 ]
}

@test "rechaza network_mode host" {
  escribir compose 'services:
  web:
    image: nginx
    network_mode: host
'
  run --separate-stderr "$RAIZ/validar-compose.sh" "$PROYECTO" compose.yaml
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"web: network_mode host"* ]]
}
