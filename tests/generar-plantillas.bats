#!/usr/bin/env bats
# generar-plantillas.sh: rol del kit (git real), {{DB_PASSWORD}}, bcrypt por variable, copias,
# columna 14 con paréntesis, reporte limpio, "# publicar:" sin duplicados, y plantillas reales.
bats_require_minimum_version 1.5.0
load ayudante

fila_tsv() { local IFS=$'\t'; printf '%s\n' "$*"; }
# repo_kit <repo> [contenido de sql/01-admin.sql]: repo git real con rama coolify.
repo_kit() {
  local r="$REPOS_DIR/$1"
  mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  printf 'services: {}\n' > "$r/compose.yaml"
  if [ -n "${2:-}" ]; then mkdir -p "$r/sql"; printf '%s\n' "$2" > "$r/sql/01-admin.sql"; fi
  git -C "$r" add . && git -C "$r" commit -q -m init
  git -C "$r" checkout -q -b coolify
}

setup() {
  preparar_entorno
  export REPOS_DIR="$BATS_TEST_TMPDIR/repos" APPS_TSV="$BATS_TEST_TMPDIR/apps.tsv"
  export ENVS_DIR="$BATS_TEST_TMPDIR/envs" REPORTE="$BATS_TEST_TMPDIR/reporte.md"
  mkdir -p "$REPOS_DIR"
  repo_kit hefesto-pgkit "CREATE ROLE \"shlink_app\" LOGIN PASSWORD :'app_pass';"
  repo_kit hefesto-pgconv "CREATE ROLE :'app_user' LOGIN PASSWORD :'app_pass';"
  repo_kit hefesto-pgsin
  {
    fila_tsv slug repo base_dir compose_file servicio_web puerto_web servicios_extra_con_dominio bd grupo alta_privada necesita_smtp cambios_para_coolify variables_obligatorias secretos_generables
    fila_tsv pgkit hefesto-pgkit / compose.yaml app 8080 '' supabase-pg liviana si no '' \
      'POSTGRES_HOST,POSTGRES_USERNAME,POSTGRES_PASSWORD,DB_PASSWORD,INITIAL_SETUP_COMPLETE,OPERATOR_ACCOUNT_CREATED,SMTP_READY' \
      'POSTGRES_PASSWORD=hex64,DB_PASSWORD=hex64 (igual al del rol en sql/01-admin.sql)'
    fila_tsv pgconv hefesto-pgconv / compose.yaml app 3000 '' supabase-pg liviana no no '' 'DB_USER,DB_PASSWORD' ''
    fila_tsv pgsin hefesto-pgsin / compose.yaml app 3000 '' supabase-pg liviana no no '' 'POSTGRES_USERNAME' ''
    fila_tsv nodo hefesto-nodo / compose.yaml app 1880 '' ninguna liviana no no '' \
      'NR_CREDENTIAL_SECRET,NR_ADMIN_HASH,NR_HTTP_HASH,BASIC_AUTH_HASH' \
      'NR_CREDENTIAL_SECRET=hex64,NR_ADMIN_HASH=bcrypt(coste 8-16)-de-clave-admin-aleatoria,NR_HTTP_HASH=bcrypt(coste 8-16)-de-clave-http-aleatoria,BASIC_AUTH_HASH=bcrypt-de-clave-basic-auth (coste 8-16, gateway-start.sh:4)'
    fila_tsv trazas hefesto-trazas / compose.yaml langfuse-web 3000 '' postgres-local pesada si opcional '' \
      'CLICKHOUSE_USER,MINIO_ROOT_USER,MINIO_ROOT_PASSWORD,LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID,LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY' \
      'MINIO_ROOT_PASSWORD=hex48,LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=copia-de-MINIO_ROOT_PASSWORD,LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=copia-de-MINIO_ROOT_USER'
    fila_tsv formatos hefesto-formatos / compose.yaml app 5000 '' sqlite liviana no no '' \
      'SIGNOZ_USER_ROOT_PASSWORD,APP_KEY,SALTED_PASS,RARO_TOKEN' \
      'SIGNOZ_USER_ROOT_PASSWORD=hex32 (alfanumérica, sin símbolos),APP_KEY=base64:+base64-32,SALTED_PASS=base64(salt32+pbkdf2_sha256(clave,salt,100000)) (scripts/configure.py:7-8),RARO_TOKEN=formato-raro'
  } > "$APPS_TSV"
  "$RAIZ/tools/generar-plantillas.sh" > "$BATS_TEST_TMPDIR/gen.out" 2>&1 || { cat "$BATS_TEST_TMPDIR/gen.out"; return 1; }
}

@test "supabase-pg: DB_PASSWORD y POSTGRES_PASSWORD usan {{DB_PASSWORD}}, nunca {{GEN:…}}" {
  grep -qx 'POSTGRES_PASSWORD={{DB_PASSWORD}}' "$ENVS_DIR/pgkit.tpl"
  grep -qx 'DB_PASSWORD={{DB_PASSWORD}}' "$ENVS_DIR/pgkit.tpl"
  grep -qx 'DB_PASSWORD={{DB_PASSWORD}}' "$ENVS_DIR/pgconv.tpl"
  ! grep -qE '^(DB|POSTGRES)_PASSWORD=\{\{GEN:' "$ENVS_DIR/pgkit.tpl"
}

@test "DB_USER/POSTGRES_USERNAME: rol literal del kit, convención anotada, o PENDIENTE anotado" {
  grep -qx 'POSTGRES_USERNAME=shlink_app' "$ENVS_DIR/pgkit.tpl"
  grep -qx 'DB_USER=mvp_pgconv_app' "$ENVS_DIR/pgconv.tpl"
  grep -q '^- rol por convención: pgconv → mvp_pgconv_app' "$REPORTE"
  grep -qx 'POSTGRES_USERNAME={{PENDIENTE}}' "$ENVS_DIR/pgsin.tpl"
  grep -q '^## pgsin · POSTGRES_USERNAME · ' "$REPORTE"
}

@test "bcrypt: cada *_HASH usa su propia clave plana <VAR sin _HASH>_PASSWORD" {
  grep -qx 'NR_ADMIN_HASH={{GEN:bcrypt:NR_ADMIN_PASSWORD}}' "$ENVS_DIR/nodo.tpl"
  grep -qx 'NR_HTTP_HASH={{GEN:bcrypt:NR_HTTP_PASSWORD}}' "$ENVS_DIR/nodo.tpl"
  grep -qx 'BASIC_AUTH_HASH={{GEN:bcrypt:BASIC_AUTH_PASSWORD}}' "$ENVS_DIR/nodo.tpl"
  [ "$(grep -c 'bcrypt:BASIC_AUTH_PASSWORD' "$ENVS_DIR/nodo.tpl")" -eq 1 ]
}

@test "copia-de-X da {{COPIA:X}}, los usuarios internos son literales y render_env los iguala" {
  grep -qx 'CLICKHOUSE_USER=hefesto' "$ENVS_DIR/trazas.tpl"
  grep -qx 'MINIO_ROOT_USER=hefesto' "$ENVS_DIR/trazas.tpl"
  grep -qx 'MINIO_ROOT_PASSWORD={{GEN:hex96}}' "$ENVS_DIR/trazas.tpl"
  grep -qx 'LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID={{COPIA:MINIO_ROOT_USER}}' "$ENVS_DIR/trazas.tpl"
  grep -qx 'LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY={{COPIA:MINIO_ROOT_PASSWORD}}' "$ENVS_DIR/trazas.tpl"
  ! grep -q '{{PENDIENTE}}' "$ENVS_DIR/trazas.tpl"
  source "$RAIZ/lib/comun.sh"; source "$RAIZ/lib/secretos.sh"
  out="$(render_env trazas)"
  echo "$out" | jq -e '(.data | map({(.key): .value}) | add) as $m
    | $m.LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY == $m.MINIO_ROOT_PASSWORD
      and ($m.MINIO_ROOT_PASSWORD | length) == 96
      and $m.LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID == "hefesto"' >/dev/null
}

@test "columna 14 respeta paréntesis; formato no normalizable queda PENDIENTE; el reporte solo lista pendientes reales" {
  grep -qx 'SIGNOZ_USER_ROOT_PASSWORD={{GEN:hex32}}' "$ENVS_DIR/formatos.tpl"
  grep -qx 'APP_KEY={{GEN:laravel}}' "$ENVS_DIR/formatos.tpl"
  grep -qx 'SALTED_PASS={{GEN:pbkdf2:SALTED_PASS_PLANO}}' "$ENVS_DIR/formatos.tpl"
  grep -qx 'RARO_TOKEN={{PENDIENTE}}' "$ENVS_DIR/formatos.tpl"
  grep -q '^## formatos · RARO_TOKEN · formato de secreto no soportado: formato-raro' "$REPORTE"
  [ "$(grep -c '^## formatos · ' "$REPORTE")" -eq 1 ]
  ! grep -qE 'queda PENDIENTE|sinsímbolos|100000\)\)|gateway-start' "$REPORTE"
}

@test "# publicar: sale una sola vez por variable y nunca para SMTP_READY" {
  [ "$(grep -cx '# publicar: INITIAL_SETUP_COMPLETE=true' "$ENVS_DIR/pgkit.tpl")" -eq 1 ]
  [ "$(grep -cx '# publicar: OPERATOR_ACCOUNT_CREATED=true' "$ENVS_DIR/pgkit.tpl")" -eq 1 ]
  ! grep -q '^# publicar: SMTP_READY' "$ENVS_DIR/pgkit.tpl"
  ! grep -q '^# publicar:' "$ENVS_DIR/nodo.tpl"
}

@test "apps con necesita_smtp=no no llevan SMTP_READY (no usan SMTP en absoluto)" {
  # pgconv y pgsin tienen necesita_smtp=no y no declaran SMTP_HOST en vars_obligatorias.
  ! grep -q '^SMTP_READY=' "$ENVS_DIR/pgconv.tpl"
  ! grep -q '^SMTP_READY=' "$ENVS_DIR/pgsin.tpl"
}

@test "la asignacion de SMTP_USERNAME se deriva de apps.tsv (SMTP_USERNAME o *_SMTP_USER_NAME), no de lista fija (7.9)" {
  # Apps que declaran SMTP_USERNAME en variables_obligatorias -> SMTP_USERNAME
  for slug in firmas ideas publicaciones; do
    grep -qx '^SMTP_USERNAME=resend$' "$RAIZ/envs/$slug.tpl" || {
      echo "$slug debería tener SMTP_USERNAME=resend" >&2; return 1; }
    ! grep -q '^SMTP_USER=' "$RAIZ/envs/$slug.tpl" || {
      echo "$slug no debería tener SMTP_USER=..." >&2; return 1; }
  done
  # Apps con SMTP_USER (no SMTP_USERNAME) -> SMTP_USER
  for slug in eventos formularios reuniones; do
    grep -qx '^SMTP_USER=resend$' "$RAIZ/envs/$slug.tpl" || {
      echo "$slug debería tener SMTP_USER=resend" >&2; return 1; }
    ! grep -q '^SMTP_USERNAME=' "$RAIZ/envs/$slug.tpl" || {
      echo "$slug no debería tener SMTP_USERNAME=..." >&2; return 1; }
  done
}

@test "solo las 9 apps con SMTP tienen SMTP_READY; las de opcional y no no (7.8)" {
  # Cargar apps.tsv real para contar las que necesitan SMTP.
  apps_obligatorio="$(awk -F'\t' 'NR>1 && $11=="obligatorio" {print $1}' "$RAIZ/apps.tsv" | sort -u | wc -l)"
  [ "$apps_obligatorio" -eq 9 ]
  # Conteo de plantillas con SMTP_READY (true o false) en el repo real, descontando
  # las dos excepciones explícitas (marketing y boletines, opcional + false a propósito).
  total="$(grep -l "^SMTP_READY=" "$RAIZ/envs/"*.tpl | wc -l)"
  marketing_boletines=2
  [ "$((total - marketing_boletines))" -eq "$apps_obligatorio" ]
  # Cada plantilla con SMTP_READY debe corresponder a una app con necesita_smtp=obligatorio
  # (excepto marketing y boletines).
  while IFS= read -r tpl; do
    slug="$(basename "$tpl" .tpl)"
    case "$slug" in marketing|boletines) continue ;; esac
    smtp="$(awk -F'\t' -v s="$slug" 'NR>1 && $1==s {print $11}' "$RAIZ/apps.tsv")"
    [ "$smtp" = "obligatorio" ] || { echo "$slug tiene SMTP_READY pero necesita_smtp=$smtp" >&2; return 1; }
  done < <(grep -l "^SMTP_READY=" "$RAIZ/envs/"*.tpl)
  # Inverso: cada app con necesita_smtp=obligatorio debe tener SMTP_READY en su plantilla.
  while IFS= read -r slug; do
    grep -q "^SMTP_READY=" "$RAIZ/envs/$slug.tpl" || {
      echo "$slug (obligatorio) no tiene SMTP_READY" >&2; return 1; }
  done < <(awk -F'\t' 'NR>1 && $11=="obligatorio" {print $1}' "$RAIZ/apps.tsv")
}

@test "plantillas reales: las 20 supabase-pg usan {{DB_PASSWORD}} y secretos lleva PUBLIC_URL con barra final" {
  n=0
  while IFS=$'\t' read -r slug bd; do
    [ "$bd" = supabase-pg ] || continue
    n=$((n + 1))
    if grep -E '^(DB|POSTGRES)_PASSWORD=' "$RAIZ/envs/$slug.tpl" | grep -vqE '^(DB|POSTGRES)_PASSWORD=\{\{DB_PASSWORD\}\}$'; then
      echo "$slug no usa {{DB_PASSWORD}}:" >&2; grep -E '^(DB|POSTGRES)_PASSWORD=' "$RAIZ/envs/$slug.tpl" >&2; return 1
    fi
  done < <(tail -n +2 "$RAIZ/apps.tsv" | cut -f1,8)
  [ "$n" -eq 20 ]
  grep -qx 'PUBLIC_URL={{URL}}/' "$RAIZ/envs/secretos.tpl"
}
