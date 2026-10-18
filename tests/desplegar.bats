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
  export ESPERA_SONDEO=0
  mkdir -p "$REPOS_DIR" "$ENVS_DIR" "$ESTADO_DIR"
  cat > "$APPS_TSV" <<'EOF'
slug	repo	base_dir	compose_file	servicio_web	puerto_web	servicios_extra_con_dominio	bd	grupo	alta_privada	necesita_smtp	cambios_para_coolify	variables_obligatorias	secretos_generables
liviana	hefesto-liviana	/	compose.yaml	web	3000		mariadb-local	liviana	no	no		APP_KEY,DB_PASSWORD	DB_PASSWORD=hex64
pesada	hefesto-pesada	/	compose.yaml	app	3000		postgres-local	pesada	si	no		SESSION_SECRET	SESSION_SECRET=hex64
privada	hefesto-privada	/	compose.yaml	app	3000		mariadb-local	liviana	si	obligatorio		APP_KEY,DB_PASSWORD	DB_PASSWORD=hex64
EOF
  for slug in liviana pesada privada; do
    mkdir -p "$REPOS_DIR/hefesto-$slug"
    cat > "$REPOS_DIR/hefesto-$slug/compose.yaml" <<'YAML'
services:
  web:
    image: nginx
    volumes:
      - "./ops:/ops:ro"
YAML
    # Repos git reales con rama coolify (desplegar.sh usa `git archive coolify`).
    ( cd "$REPOS_DIR/hefesto-$slug" && git init -q -b main && git config user.email t@t && git config user.name t && echo ops > ops && git add . && git commit -q -m init && git checkout -q -b coolify && git add . && git commit -q --allow-empty -m coolify )
    cat > "$ENVS_DIR/$slug.tpl" <<'TPL'
APP_KEY={{GEN:hex64}}
APP_URL={{URL}}
APP_HOST={{HOST}}
TPL
  done
  # Respuestas Coolify. Para POST /applications/public el stub deduce el uuid por
  # el campo `name` del cuerpo y usa el archivo .uuid_<name> si existe.
  responder GET /servers '[{"uuid":"srv1"}]'
  responder GET /projects '[]'
  responder POST /projects '{"uuid":"proj-mvps"}'
  _slug_setup() {
    local s="$1"
    printf '%s' "{\"uuid\":\"uuid-$s\"}" > "$STUB_DIR/resp/POST__applications_public.uuid_$s"
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
  # git_repository debe usar el repo de apps.tsv (columna 2), no el slug.
  jq -e '.git_repository == "https://github.com/buguenocesar92/hefesto-liviana"' \
     "$STUB_DIR/cuerpo_POST__applications_public_1" >/dev/null
}

@test "--ejecutar --todas crea proyecto, 3 apps con git_branch=coolify y build_pack=dockercompose" {
  run --separate-stderr "$RAIZ/desplegar.sh" --todas --ejecutar
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
  # POST /projects se llama una sola vez (el proyecto mvps se crea la primera vez).
  [ "$(grep -c 'curl POST /projects' "$STUB_LOG")" -eq 1 ]
  # 3 llamadas a curl POST applications/public
  [ "$(grep -c 'curl POST /applications/public' "$STUB_LOG")" -eq 3 ]
  # Cada app llamada con git_branch=coolify y build_pack=dockercompose en el cuerpo POST
  for n in 1 2 3; do
    jq -e '.git_branch == "coolify" and .build_pack == "dockercompose"' \
       "$STUB_DIR/cuerpo_POST__applications_public_$n" >/dev/null
  done
  # La liviana debe tener PATCH de dominio y POST /deploy (uuid-liviana).
  grep -q 'curl PATCH /applications/uuid-liviana' "$STUB_LOG"
  grep -q 'curl POST /deploy?uuid=uuid-liviana' "$STUB_LOG"
  # La privada (alta_privada=si) NO debe tener PATCH de dominio. Solo envs/bulk.
  for f in "$STUB_DIR"/cuerpo_PATCH__applications_uuid-privada_*; do
    [ -f "$f" ] || continue
    jq -e 'has("docker_compose_domains") | not' "$f" >/dev/null || {
      echo "privada recibió PATCH con docker_compose_domains"; return 1; }
  done
  # La pesada NO debe tener /start ni /deploy.
  [ "$(grep -c 'curl POST /applications/uuid-pesada/start' "$STUB_LOG")" -eq 0 ]
  [ "$(grep -c 'curl POST /deploy?uuid=uuid-pesada' "$STUB_LOG")" -eq 0 ]
  # Estado final por fila (no por slug).
  fila_pesada="$(awk -F'\t' '$1=="pesada"' "$ESTADO_DIR/apps.tsv")"
  [ -n "$fila_pesada" ]
  [[ "$fila_pesada" == *"CREADA_DETENIDA"* ]]
  fila_liviana="$(awk -F'\t' '$1=="liviana"' "$ESTADO_DIR/apps.tsv")"
  [[ "$fila_liviana" == *"DESPLEGADA"* ]]
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
  cat > "$REPOS_DIR/hefesto-liviana/compose.yaml" <<'YAML'
services:
  web:
    image: nginx
    privileged: true
YAML
  ( cd "$REPOS_DIR/hefesto-liviana" && git add . && git commit -q -m 'add privileged' )
  run "$RAIZ/desplegar.sh" --apps liviana --ejecutar
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  [ -f "$ESTADO_DIR/apps.tsv" ]
  grep -q 'RECHAZADO_COMPOSE' "$ESTADO_DIR/apps.tsv"
  [ "$(grep -c 'curl POST /applications/public' "$STUB_LOG" 2>/dev/null)" -eq 0 ]
}

@test "--publicar lee # publicar: y redespliega con la variable en true" {
  # La pesada tiene `# publicar: INITIAL_SETUP_COMPLETE=true`; con --publicar debe
  # haber segundo PATCH envs/bulk y POST /deploy, y terminar DESPLEGADA.
  printf 'INITIAL_SETUP_COMPLETE=false\n' >> "$ENVS_DIR/pesada.tpl"
  printf '# publicar: INITIAL_SETUP_COMPLETE=true\n' >> "$ENVS_DIR/pesada.tpl"
  run --separate-stderr "$RAIZ/desplegar.sh" --apps pesada --ejecutar --publicar
  echo "stderr=$stderr status=$status"
  echo "STUB_LOG: $STUB_LOG"
  cat "$STUB_LOG"
  echo "---fin---"
  [ "$status" -eq 0 ]
  # Debe haber al menos 2 PATCH envs/bulk (el inicial + el de publicar).
  [ "$(grep -c 'curl PATCH /applications/uuid-pesada/envs/bulk' "$STUB_LOG")" -ge 2 ]
  # Debe haber POST /deploy para la pesada aunque sea grupo=pesada.
  grep -q 'curl POST /deploy?uuid=uuid-pesada' "$STUB_LOG"
  # Estado final: DESPLEGADA con URL pública.
  fila_pesada="$(awk -F'\t' '$1=="pesada"' "$ESTADO_DIR/apps.tsv")"
  [[ "$fila_pesada" == *"DESPLEGADA"*"https://pesada.$DOMINIO_BASE"* ]]
}

@test "el token no aparece en logs ni en la salida" {
  run --separate-stderr "$RAIZ/desplegar.sh" --todas --ejecutar
  echo "stderr=$stderr status=$status"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'TOKEN-PRUEBA-NO-REAL' "$STUB_LOG")" -eq 0 ]
  [[ "$output" != *"TOKEN-PRUEBA-NO-REAL"* ]]
  [[ "$stderr" != *"TOKEN-PRUEBA-NO-REAL"* ]]
  # Los secretos generados por secreto para cada app tampoco deben aparecer.
  for slug in liviana pesada privada; do
    [ -f "$ESTADO_DIR/$slug.env" ] || continue
    while IFS='=' read -r k v; do
      [ -z "$k" ] && continue
      [[ "$v" == *"TOKEN-PRUEBA"* ]] && continue
      [[ "$output" != *"$v"* ]] || { echo "valor de $k de $slug apareció en \$output"; return 1; }
      [[ "$stderr" != *"$v"* ]] || { echo "valor de $k de $slug apareció en \$stderr"; return 1; }
    done < "$ESTADO_DIR/$slug.env"
  done
}
