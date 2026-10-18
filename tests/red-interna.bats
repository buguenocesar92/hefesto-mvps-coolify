#!/usr/bin/env bats
# Tarea 3: red interna y hosts reales de Supabase.
# - desplegar.sh: el POST /applications/public lleva connect_to_docker_network:true.
# - render_env: si $ESTADO_DIR/supabase.uuid existe, {{DB_HOST}} = supabase-db-<uuid>
#   y {{SUPABASE_URL}} = http://supabase-kong-<uuid>:8000. Las variables de entorno
#   SUPABASE_DB_HOST y SUPABASE_INTERNAL_URL siguen ganando.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export REPOS_DIR="$BATS_TEST_TMPDIR/repos"
  export APPS_TSV="$BATS_TEST_TMPDIR/apps.tsv"
  export ESTADO_DIR="$HEFESTO_MVPS_ESTADO"
  export ENVS_DIR="$BATS_TEST_TMPDIR/envs"
  export ESPERA_SONDEO=0
  mkdir -p "$REPOS_DIR" "$ENVS_DIR" "$ESTADO_DIR"
  cat > "$APPS_TSV" <<'EOF'
slug	repo	base_dir	compose_file	servicio_web	puerto_web	servicios_extra_con_dominio	bd	grupo	alta_privada	necesita_smtp	cambios_para_coolify	variables_obligatorias	secretos_generables
liviana	hefesto-liviana	/	compose.yaml	web	3000		supabase-pg	liviana	no	no		DB_HOST,DB_PASSWORD	DB_PASSWORD=hex64
EOF
  mkdir -p "$REPOS_DIR/hefesto-liviana"
  cat > "$REPOS_DIR/hefesto-liviana/compose.yaml" <<'YAML'
services:
  web:
    image: nginx
YAML
  ( cd "$REPOS_DIR/hefesto-liviana" && git init -q -b main && git config user.email t@t && git config user.name t && git add . && git commit -q -m init && git checkout -q -b coolify )
  cat > "$ENVS_DIR/liviana.tpl" <<'TPL'
DB_HOST={{DB_HOST}}
DB_PASSWORD={{DB_PASSWORD}}
SUPABASE_URL={{SUPABASE_URL}}
APP_URL={{URL}}
TPL
  # Sin supabase.uuid por defecto; cada test siembra lo que necesita.
  responder GET /servers '[{"uuid":"srv1"}]'
  responder GET /projects '[]'
  responder POST /projects '{"uuid":"proj-mvps"}'
  printf '{"uuid":"uuid-liviana"}' > "$STUB_DIR/resp/POST__applications_public.uuid_liviana"
  responder GET /applications/uuid-liviana '{"uuid":"uuid-liviana","status":"started:false","docker_compose_raw":"services:\n  web:\n    image: nginx\n","docker_compose_domains":[]}'
  source "$RAIZ/lib/comun.sh"
  source "$RAIZ/lib/secretos.sh"
}

@test "desplegar.sh POST /applications/public lleva connect_to_docker_network:true" {
  run --separate-stderr "$RAIZ/desplegar.sh" --apps liviana --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  echo "STUB_LOG:"; cat "$STUB_LOG"; echo "---"
  [ "$status" -eq 0 ]
  jq -e '.connect_to_docker_network == true' "$STUB_DIR/cuerpo_POST__applications_public_1" >/dev/null
}

@test "render_env con supabase.uuid=abc: DB_HOST=supabase-db-abc y SUPABASE_URL=http://supabase-kong-abc:8000" {
  printf 'abc\n' > "$ESTADO_DIR/supabase.uuid"
  export HEFESTO_ADMIN_EMAIL=""
  out="$(render_env liviana)"
  echo "$out" | jq -e '.data[] | select(.key=="DB_HOST") | .value == "supabase-db-abc"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="SUPABASE_URL") | .value == "http://supabase-kong-abc:8000"' >/dev/null
}

@test "render_env sin supabase.uuid: DB_HOST=supabase-db y SUPABASE_URL=http://supabase-kong:8000 (compatibilidad)" {
  unset SUPABASE_DB_HOST SUPABASE_INTERNAL_URL
  out="$(render_env liviana)"
  echo "$out" | jq -e '.data[] | select(.key=="DB_HOST") | .value == "supabase-db"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="SUPABASE_URL") | .value == "http://supabase-kong:8000"' >/dev/null
}

@test "render_env con SUPABASE_DB_HOST y SUPABASE_INTERNAL_URL: esas ganan sobre supabase.uuid" {
  printf 'abc\n' > "$ESTADO_DIR/supabase.uuid"
  export SUPABASE_DB_HOST="mi-db-override"
  export SUPABASE_INTERNAL_URL="http://mi-kong-override:9000"
  out="$(render_env liviana)"
  echo "$out" | jq -e '.data[] | select(.key=="DB_HOST") | .value == "mi-db-override"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="SUPABASE_URL") | .value == "http://mi-kong-override:9000"' >/dev/null
}