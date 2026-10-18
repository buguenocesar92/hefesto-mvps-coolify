#!/usr/bin/env bats
# instalar-supabase.sh: crea o reusa el servicio Supabase, configura la red interna,
# fija el SMTP de GoTrue con Resend, arranca el servicio y deja los secretos en archivos 0600.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export ESTADO_DIR="$HEFESTO_MVPS_ESTADO"
  mkdir -p "$ESTADO_DIR"
  export RESEND_ENV_FILE="$BATS_TEST_TMPDIR/resend.env"
  export SUPABASE_KEY_FILE="$BATS_TEST_TMPDIR/supabase-service-key"
  export SUPABASE_ANON_KEY_FILE="$BATS_TEST_TMPDIR/supabase-anon-key"
  export SUPABASE_POSTGRES_PASS="$BATS_TEST_TMPDIR/supabase-postgres.pass"
  export ESPERA_SONDEO=0 MAX_INTENTOS_INICIO=2
  printf 'RESEND_API_KEY=re_PRUEBA\n' > "$RESEND_ENV_FILE"; chmod 600 "$RESEND_ENV_FILE"
  responder GET /version '"4.4.6"'
  responder GET /servers '[{"uuid":"srv1"}]'
  responder GET /projects '[]'
  responder POST /projects '{"uuid":"proj-mvps"}'
  # POST /services: respuesta al crear el servicio Supabase.
  responder POST /services '{"uuid":"supa-uuid-1","domains":""}'
  # GET /services/<uuid>: status=running para que el bucle termine.
  responder GET /services/supa-uuid-1 '{"uuid":"supa-uuid-1","status":"running:healthy"}'
  # PATCH /services/<uuid> (red, envs/bulk): éxito vacío.
  responder PATCH /services/supa-uuid-1 '{}'
  responder PATCH /services/supa-uuid-1/envs/bulk '{}'
  # POST /services/<uuid>/start: éxito vacío.
  responder POST /services/supa-uuid-1/start '{}'
  # GET /services/<uuid>/envs: envs con valores (requieren read:sensitive).
  responder GET /services/supa-uuid-1/envs '[
    {"key":"SERVICE_SUPABASESERVICE_KEY","value":"svc-key-test-XYZ"},
    {"key":"SERVICE_SUPABASEANON_KEY","value":"anon-key-test-ABC"},
    {"key":"SERVICE_PASSWORD_POSTGRES","value":"postgres-pass-test-123"}
  ]'
}

@test "--dry-run imprime el plan y no hace POST /services ni PATCH" {
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --dry-run
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan"* || "$output" == *"supabase"* || "$output" == *"Supabase"* ]] || true
  ! grep -q 'curl POST /services' "$STUB_LOG"
  ! grep -q 'curl PATCH /services' "$STUB_LOG"
  [ ! -f "$ESTADO_DIR/supabase.uuid" ]
}

@test "--ejecutar hace POST /services con type:supabase, PATCH connect_to_docker_network:true y start" {
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  echo "STUB_LOG:"; cat "$STUB_LOG"; echo "---"
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^curl POST /services( |$)' "$STUB_LOG")" -eq 1 ]
  jq -e '.type == "supabase"' "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  jq -e '.name == "mvp-supabase"' "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  jq -e '.project_uuid == "proj-mvps"' "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  jq -e '.server_uuid == "srv1"' "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  jq -e '.environment_name == "production"' "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  jq -e '.instant_deploy == false' "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  jq -e '(.urls | length == 1) and (.urls[0].name == "supabase-kong") and (.urls[0].url | startswith("http://supabase."))' \
    "$STUB_DIR/cuerpo_POST__services_1" >/dev/null
  [ "$(grep -c '^curl PATCH /services/supa-uuid-1$' "$STUB_LOG")" -ge 1 ]
  [ "$(grep -c '^curl POST /services/supa-uuid-1/start$' "$STUB_LOG")" -eq 1 ]
  [ -f "$ESTADO_DIR/supabase.uuid" ]
  [ "$(cat "$ESTADO_DIR/supabase.uuid")" = "supa-uuid-1" ]
}

@test "segunda corrida no repite el POST /services (reusa \$ESTADO_DIR/supabase.uuid)" {
  printf 'supa-uuid-1\n' > "$ESTADO_DIR/supabase.uuid"
  : > "$STUB_LOG"
  responder GET /services/supa-uuid-1 '{"uuid":"supa-uuid-1","status":"running:healthy"}'
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  echo "STUB_LOG:"; cat "$STUB_LOG"; echo "---"
  [ "$status" -eq 0 ]
  ! grep -q 'curl POST /services' "$STUB_LOG"
  [ "$(cat "$ESTADO_DIR/supabase.uuid")" = "supa-uuid-1" ]
}

@test "archivos de claves quedan 0600 con valor del stub y no aparecen en \$output ni en el STUB_LOG" {
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$SUPABASE_KEY_FILE")" = "600" ]
  [ "$(stat -c %a "$SUPABASE_ANON_KEY_FILE")" = "600" ]
  [ "$(stat -c %a "$SUPABASE_POSTGRES_PASS")" = "600" ]
  [ "$(cat "$SUPABASE_KEY_FILE")" = "svc-key-test-XYZ" ]
  [ "$(cat "$SUPABASE_ANON_KEY_FILE")" = "anon-key-test-ABC" ]
  [ "$(cat "$SUPABASE_POSTGRES_PASS")" = "postgres-pass-test-123" ]
  [[ "$output" != *"svc-key-test-XYZ"* ]]
  [[ "$output" != *"anon-key-test-ABC"* ]]
  [[ "$output" != *"postgres-pass-test-123"* ]]
  [[ "$stderr" != *"svc-key-test-XYZ"* ]]
  [[ "$stderr" != *"anon-key-test-ABC"* ]]
  [[ "$stderr" != *"postgres-pass-test-123"* ]]
  ! grep -qF 'svc-key-test-XYZ' "$STUB_LOG"
  ! grep -qF 'anon-key-test-ABC' "$STUB_LOG"
  ! grep -qF 'postgres-pass-test-123' "$STUB_LOG"
}

@test "envs con value:null error de read:sensitive y no crea archivos" {
  rm -f "$SUPABASE_KEY_FILE" "$SUPABASE_ANON_KEY_FILE" "$SUPABASE_POSTGRES_PASS"
  responder GET /services/supa-uuid-1/envs '[
    {"key":"SERVICE_SUPABASESERVICE_KEY","value":null},
    {"key":"SERVICE_SUPABASEANON_KEY","value":"anon-x"},
    {"key":"SERVICE_PASSWORD_POSTGRES","value":"pass-x"}
  ]'
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"read:sensitive"* ]] || [[ "$output" == *"read:sensitive"* ]]
  [ ! -e "$SUPABASE_KEY_FILE" ]
  [ ! -e "$SUPABASE_ANON_KEY_FILE" ]
  [ ! -e "$SUPABASE_POSTGRES_PASS" ]
}

@test "bulk del SMTP lleva SMTP_PASS del resend.env y re_PRUEBA no aparece en \$output" {
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  body_smtp="$STUB_DIR/cuerpo_PATCH__services_supa-uuid-1_envs_bulk_1"
  [ -f "$body_smtp" ]
  jq -e '.data | map(select(.key=="SMTP_HOST")) | .[0].value == "smtp.resend.com"' "$body_smtp" >/dev/null
  jq -e '.data | map(select(.key=="SMTP_PORT")) | .[0].value == "465"' "$body_smtp" >/dev/null
  jq -e '.data | map(select(.key=="SMTP_USER")) | .[0].value == "resend"' "$body_smtp" >/dev/null
  jq -e '.data | map(select(.key=="SMTP_PASS")) | .[0].value == "re_PRUEBA"' "$body_smtp" >/dev/null
  jq -e '.data | map(select(.key=="SMTP_SENDER_NAME")) | .[0].value == "Hefesto"' "$body_smtp" >/dev/null
  jq -e '.data | map(select(.key=="SMTP_ADMIN_EMAIL")) | .[0].value | startswith("no-reply@")' "$body_smtp" >/dev/null
  [[ "$output" != *"re_PRUEBA"* ]]
  [[ "$stderr" != *"re_PRUEBA"* ]]
}

@test "fallback toma el valor que empieza con re_ cuando no hay RESEND_API_KEY" {
  printf 'OTRA_CLAVE=re_ALT\nOTRO_MAS=nope\n' > "$RESEND_ENV_FILE"; chmod 600 "$RESEND_ENV_FILE"
  run --separate-stderr "$RAIZ/instalar-supabase.sh" --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  body_smtp="$STUB_DIR/cuerpo_PATCH__services_supa-uuid-1_envs_bulk_1"
  jq -e '.data | map(select(.key=="SMTP_PASS")) | .[0].value == "re_ALT"' "$body_smtp" >/dev/null
  [[ "$output" != *"re_ALT"* ]]
  [[ "$stderr" != *"re_ALT"* ]]
}