#!/usr/bin/env bats
# aplicar-sql.sh: por cada app genera SQL por app (idempotente), crea una scheduled task
# en el servicio de Coolify con enabled:false, la ejecuta, sondea las executions y
# registra el estado por slug. El comando viaja en el cuerpo del POST, no en la URL.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export ESTADO_DIR="$HEFESTO_MVPS_ESTADO"
  mkdir -p "$ESTADO_DIR/sql"
  export REPOS_DIR="$BATS_TEST_TMPDIR/repos"
  export APPS_TSV="$BATS_TEST_TMPDIR/apps.tsv"
  mkdir -p "$REPOS_DIR"
  export ESPERA_SONDEO=0 MAX_INTENTOS=3
  cat > "$APPS_TSV" <<'EOF'
slug	repo	base_dir	compose_file	servicio_web	puerto_web	servicios_extra_con_dominio	bd	grupo	alta_privada	necesita_smtp	cambios_para_coolify	variables_obligatorias	secretos_generables
pgapp	hefesto-pgapp	/	compose.yaml	web	3000		supabase-pg	liviana	no	no		DB_PASSWORD	DB_PASSWORD=hex64
restapp	hefesto-restapp	/	compose.yaml	web	3000		supabase-rest	liviana	no	no		SUPABASE_URL,SUPABASE_SECRET_KEY	SUPABASE_SECRET_KEY=sin_generar: viene del kit
EOF
  # Repos git con rama coolify.
  for repo in hefesto-pgapp hefesto-restapp; do
    mkdir -p "$REPOS_DIR/$repo"
    ( cd "$REPOS_DIR/$repo" && git init -q -b main && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m init && git checkout -q -b coolify )
  done
  mkdir -p "$REPOS_DIR/hefesto-pgapp/sql"
  cat > "$REPOS_DIR/hefesto-pgapp/sql/01-rol.sql" <<'SQL'
CREATE ROLE :'app_user' LOGIN PASSWORD :'app_pass';
SQL
  ( cd "$REPOS_DIR/hefesto-pgapp" && git add . && git commit -q -m sql )
  mkdir -p "$REPOS_DIR/hefesto-restapp/supabase/migrations"
  cat > "$REPOS_DIR/hefesto-restapp/supabase/migrations/20260101000000_init.sql" <<'SQL'
create table if not exists public.demo (id int);
SQL
  ( cd "$REPOS_DIR/hefesto-restapp" && git add . && git commit -q -m sql )
  # Respuestas Coolify.
  responder GET /version '"4.4.6"'
  responder POST /services/supabase-uuid-1/scheduled-tasks '{"uuid":"task-uuid-1"}'
  responder POST /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/execute '{}'
  responder GET /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/executions \
    '[{"status":"success","message":"FIN_OK"}]'
  responder DELETE /services/supabase-uuid-1/scheduled-tasks/task-uuid-1 '{}'
  # Estado del uuid de Supabase.
  printf 'supabase-uuid-1\n' > "$ESTADO_DIR/supabase.uuid"
}

@test "--dry-run no llama a la API y muestra el plan" {
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --dry-run
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  # Sin llamadas a la API: el log del stub queda sin líneas curl (ni siquiera /version).
  [ ! -s "$STUB_LOG" ]
  ! grep -q '^curl ' "$STUB_LOG"
}

@test "--ejecutar crea la task con container:supabase-db y enabled:false, la ejecuta y lee executions" {
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  echo "STUB_LOG:"; cat "$STUB_LOG"; echo "---"
  [ "$status" -eq 0 ]
  jq -e '.container == "supabase-db"' "$STUB_DIR/cuerpo_POST__services_supabase-uuid-1_scheduled-tasks_1" >/dev/null
  jq -e '.enabled == false' "$STUB_DIR/cuerpo_POST__services_supabase-uuid-1_scheduled-tasks_1" >/dev/null
  jq -e '.command | type == "string" and (contains("psql -U postgres") or contains("base64 -d"))' \
    "$STUB_DIR/cuerpo_POST__services_supabase-uuid-1_scheduled-tasks_1" >/dev/null
  # El nombre de la task incluye el slug para distinguir apps en Coolify.
  jq -e '.name == "aplicar-sql-pgapp"' "$STUB_DIR/cuerpo_POST__services_supabase-uuid-1_scheduled-tasks_1" >/dev/null
  grep -q '^curl POST /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/execute$' "$STUB_LOG"
  grep -q '^curl GET /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/executions$' "$STUB_LOG"
}

@test "execution con FIN_OK da SQL_OK; con ERROR da SQL_ERROR y sale 1" {
  # Caso FIN_OK: el endpoint devuelve una LISTA de ejecuciones.
  responder GET /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/executions \
    '[{"status":"success","message":"FIN_OK"}]'
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SQL_OK"* ]]
  # Caso ERROR (nueva corrida).
  : > "$STUB_LOG"
  printf 'supabase-uuid-1\n' > "$ESTADO_DIR/supabase.uuid"
  responder POST /services/supabase-uuid-1/scheduled-tasks '{"uuid":"task-uuid-1"}'
  responder POST /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/execute '{}'
  responder GET /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/executions \
    '[{"status":"failed","message":"ERROR: relation does not exist"}]'
  responder DELETE /services/supabase-uuid-1/scheduled-tasks/task-uuid-1 '{}'
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SQL_ERROR"* ]]
  [[ "$output" == *"ERROR: relation does not exist"* ]]
}

@test "executions como objeto (compatibilidad) no rompe el bucle" {
  # Si la API alguna vez devolviera un objeto, no debe fallar el bucle entero.
  responder GET /services/supabase-uuid-1/scheduled-tasks/task-uuid-1/executions \
    '{"status":"success","message":"FIN_OK"}'
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SQL_OK"* ]]
}

@test "el comando viaja en el cuerpo JSON, no en la URL, y no aparece en \$output ni en el log del stub" {
  # Sembrar una clave conocida en el SQL: usar DB_PASSWORD generado por secreto.
  printf 'DB_PASSWORD=secreto-privado-XYZ\n' > "$ESTADO_DIR/pgapp.env"
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  # El cuerpo del POST scheduled-tasks contiene el comando (con base64 del SQL).
  jq -e '.command | contains("psql -U postgres -v ON_ERROR_STOP=1")' \
    "$STUB_DIR/cuerpo_POST__services_supabase-uuid-1_scheduled-tasks_1" >/dev/null
  # Recuperar el valor REAL de la clave y comprobar que no aparece en ningún lado
  # (el SQL viaja en base64; un grep del valor en claro sobre el body no probaría nada).
  # shellcheck source=lib/secretos.sh
  source "$RAIZ/lib/secretos.sh"
  pass="$(secreto pgapp DB_PASSWORD hex64)"
  [[ "$output" != *"$pass"* ]]
  [[ "$stderr" != *"$pass"* ]]
  ! grep -qF "$pass" "$STUB_LOG"
  ! grep -qF "$pass" "$STUB_DIR/cuerpo_POST__services_supabase-uuid-1_scheduled-tasks_1"
  # La URL registrada no contiene ni base64 ni psql (el comando viaja en el body).
  ! grep -q 'base64' "$STUB_LOG"
  ! grep -q 'psql' "$STUB_LOG"
}

@test "tras el éxito se llama al DELETE de la task" {
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  grep -q '^curl DELETE /services/supabase-uuid-1/scheduled-tasks/task-uuid-1$' "$STUB_LOG"
}

@test "SQL generado por app es idempotente: contiene \\gexec o IF NOT EXISTS para la base y el rol" {
  run --separate-stderr "$RAIZ/supabase-sql.sh" --apps pgapp --por-app
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  sql_file="$(echo "$output" | head -1)"
  [ -f "$sql_file" ]
  [ "$(stat -c %a "$sql_file")" = "600" ]
  # Base: envoltorio \gexec.
  grep -q "SELECT 'CREATE DATABASE mvp_pgapp' WHERE NOT EXISTS" "$sql_file"
  grep -q '\\gexec' "$sql_file"
  # Rol: condicional psql (\gset + \if + \endif), no DO $$.
  grep -qF 'crear_rol \gset' "$sql_file"
  grep -qF '\if :crear_rol' "$sql_file"
  grep -qF '\endif' "$sql_file"
  # Ningún bloque DO $$ con marcadores :'app_user'/ :'app_pass' dentro.
  awk '
    BEGIN { n = 0; dentro = 0 }
    /DO \$\$/ { dentro = 1; next }
    /END \$\$/ { dentro = 0; next }
    dentro == 1 && (/:\047app_user\047/ || /:\047app_pass\047/) { n++ }
    END { exit (n == 0 ? 0 : 1) }
  ' "$sql_file"
}

@test "registra el estado final en \$ESTADO_DIR/sql.tsv (slug, estado, fecha)" {
  responder DELETE /services/supabase-uuid-1/scheduled-tasks/task-uuid-1 '{}'
  run --separate-stderr "$RAIZ/aplicar-sql.sh" --apps pgapp --ejecutar
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  [ -f "$ESTADO_DIR/sql.tsv" ]
  grep -q 'pgapp' "$ESTADO_DIR/sql.tsv"
  grep -q 'SQL_OK' "$ESTADO_DIR/sql.tsv"
  [ "$(stat -c %a "$ESTADO_DIR/sql.tsv")" = "600" ]
}