#!/usr/bin/env bats
# supabase-sql.sh: genera el SQL de supabase (CREATE DATABASE + sql/01-*.sql del kit
# + migraciones rest) en $ESTADO_DIR/supabase.sql, sin imprimir claves.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export APPS_TSV="$BATS_TEST_TMPDIR/apps.tsv"
  export ESTADO_DIR="$HEFESTO_MVPS_ESTADO"
  export REPOS_DIR="$BATS_TEST_TMPDIR/repos"
  mkdir -p "$ESTADO_DIR" "$REPOS_DIR"
  cat > "$APPS_TSV" <<'EOF'
slug	repo	base_dir	compose_file	servicio_web	puerto_web	servicios_extra_con_dominio	bd	grupo	alta_privada	necesita_smtp	cambios_para_coolify	variables_obligatorias	secretos_generables
pgapp	hefesto-pgapp	/	compose.yaml	web	3000		supabase-pg	liviana	no	no		DB_PASSWORD	DB_PASSWORD=hex64
restapp	hefesto-restapp	/	compose.yaml	web	3000		supabase-rest	liviana	no	no		SUPABASE_URL,SUPABASE_SECRET_KEY	SUPABASE_SECRET_KEY=sin_generar: viene del kit
EOF
  # Repos git reales con rama coolify
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
}

@test "--todas genera SQL con CREATE DATABASE mvp_<slug>, \\connect y migración rest" {
  run --separate-stderr "$RAIZ/supabase-sql.sh" --todas
  echo "status=$status stderr=$stderr output=$output"
  [ "$status" -eq 0 ]
  archivo="$(echo "$output" | tail -2 | head -1)"
  [ -f "$archivo" ]
  grep -q '^CREATE DATABASE mvp_pgapp;' "$archivo"
  grep -qF '\connect mvp_pgapp' "$archivo"
  grep -q '^CREATE ROLE' "$archivo"
  grep -qF '\connect postgres' "$archivo"
  grep -q 'public.demo' "$archivo"
  [ "$(stat -c %a "$archivo")" = "600" ]
}

@test "no imprime secretos en stdout ni en stderr" {
  # Sembrar un secret conocido
  printf 'DB_PASSWORD=secreto-privado-XYZ\n' > "$ESTADO_DIR/pgapp.env"
  run --separate-stderr "$RAIZ/supabase-sql.sh" --apps pgapp
  [ "$status" -eq 0 ]
  [[ "$output" != *"secreto-privado-XYZ"* ]]
  [[ "$stderr" != *"secreto-privado-XYZ"* ]]
}

@test "usa en \\set app_user el rol literal que crea el kit" {
  cat > "$REPOS_DIR/hefesto-pgapp/sql/01-rol.sql" <<'SQL'
CREATE ROLE fider_app LOGIN PASSWORD :'app_pass';
SQL
  ( cd "$REPOS_DIR/hefesto-pgapp" && git add . && git commit -q -m rol-literal )
  run --separate-stderr "$RAIZ/supabase-sql.sh" --apps pgapp
  echo "status=$status stderr=$stderr"
  [ "$status" -eq 0 ]
  grep -qxF "\\set app_user 'fider_app'" "$ESTADO_DIR/supabase.sql"
}

@test "con CREATE ROLE :'app_user' usa la convención mvp_<slug>_app y app_pass es el DB_PASSWORD hex64" {
  run --separate-stderr "$RAIZ/supabase-sql.sh" --apps pgapp
  [ "$status" -eq 0 ]
  grep -qxF "\\set app_user 'mvp_pgapp_app'" "$ESTADO_DIR/supabase.sql"
  clave="$(grep '^DB_PASSWORD=' "$ESTADO_DIR/pgapp.env" | cut -d= -f2-)"
  [[ "$clave" =~ ^[0-9a-f]{64}$ ]]
  grep -qxF "\\set app_pass '$clave'" "$ESTADO_DIR/supabase.sql"
}
