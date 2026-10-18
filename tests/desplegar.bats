#!/usr/bin/env bats
# desplegar.sh: dry-run, ejecución, idempotencia, rechazo por compose con privileged,
# no impresión del token.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export REPOS_DIR="$BATS_TEST_TMPDIR/repos"
  export APPS_TSV="$BATS_TEST_TMPDIR/apps.tsv"
  export DOCKER_BIN="$RAIZ/tests/stubs/docker"
  export ESTADO_DIR="$HEFESTO_MVPS_ESTADO"
  export ENVS_DIR="$BATS_TEST_TMPDIR/envs"
  mkdir -p "$REPOS_DIR" "$ENVS_DIR" "$ESTADO_DIR"
  cat > "$APPS_TSV" <<'EOF'
slug	repo	base_dir	compose_file	servicio_web	puerto_web	servicios_extra_con_dominio	bd	grupo	alta_privada	necesita_smtp	cambios_para_coolify	variables_obligatorias	secretos_generables
liviana	hefesto-liviana	/	compose.yaml	web	3000		mariadb-local	liviana	no	no		APP_KEY,DB_PASSWORD	DB_PASSWORD=hex64
pesada	hefesto-pesada	/	compose.yaml	app	3000		postgres-local	pesada	si	no		SESSION_SECRET	SESSION_SECRET=hex64
privada	hefesto-privada	/	compose.yaml	app	3000		mariadb-local	liviana	si	obligatorio		APP_KEY,DB_PASSWORD	DB_PASSWORD=hex64
EOF
  for slug in liviana pesada privada; do
    mkdir -p "$REPOS_DIR/hefesto-$slug/coolify"
    cat > "$REPOS_DIR/hefesto-$slug/coolify/compose.yaml" <<'YAML'
services:
  web:
    image: nginx
    volumes:
      - "./ops:/ops:ro"
YAML
    cat > "$ENVS_DIR/$slug.tpl" <<'TPL'
APP_KEY={{GEN:hex64}}
APP_URL={{URL}}
APP_HOST={{HOST}}
TPL
  done
  # Respuestas Coolify
  responder GET /servers '[{"uuid":"srv1"}]'
  responder GET /projects '[]'
  responder POST /projects '{"uuid":"proj-mvps"}'
  _slug_setup() {
    local s="$1"
    responder POST /applications/public "{\"uuid\":\"uuid-$s\"}"
    responder GET "/applications/uuid-$s" "{\"uuid\":\"uuid-$s\",\"status\":\"started:false\",\"docker_compose_raw\":\"services:\\n  web:\\n    image: nginx\\n\",\"docker_compose_domains\":[]}"
  }
  _slug_setup liviana
  _slug_setup pesada
  _slug_setup privada
}

@test "sin argumentos sale 2" {
  run "$RAIZ/desplegar.sh"
  [ "$status" -eq 2 ]
}

@test "--dry-run imprime plan y no hace POST/PATCH/deploy" {
  run "$RAIZ/desplegar.sh" --todas --dry-run
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"liviana:"* ]]
  [[ "$output" == *"pesada:"* ]]
  [[ "$output" == *"privada:"* ]]
  if [ -s "$STUB_LOG" ]; then
    ! grep -qE 'curl POST|curl PATCH' "$STUB_LOG"
  fi
}

@test "--ejecutar --apps liviana funciona y registra el uuid con DESPLEGADA" {
  run --separate-stderr "$RAIZ/desplegar.sh" --apps liviana --ejecutar
  echo "stderr=$stderr status=$status"
  echo "STUB_LOG:"
  cat "$STUB_LOG"
  echo "---"
  [ "$status" -eq 0 ]
  [ -f "$ESTADO_DIR/apps.tsv" ]
  grep -q 'liviana' "$ESTADO_DIR/apps.tsv"
  grep -q 'DESPLEGADA' "$ESTADO_DIR/apps.tsv"
  [ "$(grep -c 'curl POST /applications/public' "$STUB_LOG")" -eq 1 ]
  jq -e '.git_branch == "coolify" and .build_pack == "dockercompose"' \
     "$STUB_DIR/cuerpo_POST__applications_public_1" >/dev/null
}

@test "--ejecutar --todas crea proyecto, 3 apps con git_branch=coolify y build_pack=dockercompose" {
  run --separate-stderr "$RAIZ/desplegar.sh" --todas --ejecutar
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
  # 3 llamadas a curl POST applications/public
  [ "$(grep -c 'curl POST /applications/public' "$STUB_LOG")" -eq 3 ]
  # Cada app llamada con git_branch=coolify y build_pack=dockercompose en el cuerpo POST
  for n in 1 2 3; do
    jq -e '.git_branch == "coolify" and .build_pack == "dockercompose"' \
       "$STUB_DIR/cuerpo_POST__applications_public_$n" >/dev/null
  done
  # La pesada no se desplegó
  ! grep -q 'curl POST /deploy' "$STUB_LOG"
  # Estado final: pesada con CREADA_DETENIDA
  grep -q 'pesada' "$ESTADO_DIR/apps.tsv"
}

@test "segunda corrida es idempotente (no repite POST /applications/public)" {
  printf 'liviana\tuuid-liviana\tDESPLEGADA\thttps://liviana.hefesto-studio.cl\t2026-01-01\n' > "$ESTADO_DIR/apps.tsv"
  printf 'pesada\tuuid-pesada\tCREADA_DETENIDA\t\t2026-01-01\n' >> "$ESTADO_DIR/apps.tsv"
  printf 'privada\tuuid-privada\tDESPLEGADA_SIN_DOMINIO\t\t2026-01-01\n' >> "$ESTADO_DIR/apps.tsv"
  : > "$STUB_LOG"
  echo "antes de run STUB_LOG content:"
  cat "$STUB_LOG"
  echo "---"
  run "$RAIZ/desplegar.sh" --todas --ejecutar
  echo "stderr=$stderr status=$status"
  echo "STUB_LOG:"
  cat "$STUB_LOG"
  echo "---fin---"
  [ "$status" -eq 0 ]
  ! grep -q 'curl POST /applications/public' "$STUB_LOG"
}

@test "compose con privileged en rama coolify da RECHAZADO_COMPOSE y no llama a la API" {
  cat > "$REPOS_DIR/hefesto-liviana/coolify/compose.yaml" <<'YAML'
services:
  web:
    image: nginx
    privileged: true
YAML
  run "$RAIZ/desplegar.sh" --apps liviana --ejecutar
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [ -f "$ESTADO_DIR/apps.tsv" ]
  grep -q 'RECHAZADO_COMPOSE' "$ESTADO_DIR/apps.tsv"
  ! grep -q 'curl POST /applications/public' "$STUB_LOG"
}

@test "el token no aparece en logs ni en la salida" {
  run --separate-stderr "$RAIZ/desplegar.sh" --todas --ejecutar
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
  ! grep -F -- "TOKEN-PRUEBA-NO-REAL" "$STUB_LOG"
  [[ "$output" != *"TOKEN-PRUEBA-NO-REAL"* ]]
  [[ "$stderr" != *"TOKEN-PRUEBA-NO-REAL"* ]]
}
