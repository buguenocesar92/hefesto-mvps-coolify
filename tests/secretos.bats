#!/usr/bin/env bats
# secretos.sh: genera y persiste secretos, expande marcadores en plantillas y arma JSON.
bats_require_minimum_version 1.5.0
load ayudante
setup() {
  preparar_entorno
  export ENVS_DIR="$BATS_TEST_TMPDIR/envs"; mkdir -p "$ENVS_DIR"
  source "$RAIZ/lib/comun.sh"
  source "$RAIZ/lib/secretos.sh"
}

@test "secreto es idempotente y deja 0600 el archivo y 0700 el directorio" {
  v1="$(secreto reservas APP_KEY hex64)"
  v2="$(secreto reservas APP_KEY hex64)"
  [ "$v1" = "$v2" ]
  [ "$(stat -c %a "$HEFESTO_MVPS_ESTADO/reservas.env")" = "600" ]
  [ "$(stat -c %a "$HEFESTO_MVPS_ESTADO")" = "700" ]
}

@test "bcrypt genera hash \$2y\$ y persiste la clave plana" {
  hash="$(secreto soporte BASIC_AUTH_PASSWORD bcrypt:BASIC_AUTH_PASSWORD_PLAIN)"
  [[ "$hash" == '$2y$'* ]] || [[ "$hash" == '$2b$'* ]]
  grep -q '^BASIC_AUTH_PASSWORD_PLAIN=' "$HEFESTO_MVPS_ESTADO/soporte.env"
}

@test "render_env reemplaza marcadores y produce JSON válido con is_literal:true" {
  cat > "$ENVS_DIR/demo.tpl" <<'EOF'
APP_URL={{URL}}
APP_HOST={{HOST}}
APP_KEY={{GEN:hex64}}
DB_NAME={{DB_NAME}}
EOF
  out="$(render_env demo)"
  echo "$out" | jq -e '.data | length == 4' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="APP_URL") | .value == "https://demo.hefesto-studio.cl"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="APP_HOST") | .value == "demo.hefesto-studio.cl"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="DB_NAME") | .value == "mvp_demo"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="APP_KEY") | (.value | length == 64)' >/dev/null
  echo "$out" | jq -e '.data[] | .is_literal == true' >/dev/null
  echo "$out" | jq -e '.data[] | .is_preview == false' >/dev/null
}

@test "render_env falla con {{PENDIENTE}}" {
  cat > "$ENVS_DIR/demo.tpl" <<'EOF'
MI_VAR={{PENDIENTE}}
EOF
  run --separate-stderr render_env demo
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"MI_VAR"* ]]
}

@test "render_env falla con clave inválida" {
  cat > "$ENVS_DIR/demo.tpl" <<'EOF'
bad-key=hola
EOF
  run --separate-stderr render_env demo
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"clave inválida"* ]]
}

@test "toda plantilla real contiene cada variable obligatoria de su app" {
  PLANTILLAS="$RAIZ/envs"
  while IFS=$'\t' read -r slug _; do
    [ "$slug" = "slug" ] && continue
    [ -z "$slug" ] && continue
    obr="$(awk -F'\t' -v s="$slug" 'NR>1 && $1==s {print $13}' "$RAIZ/apps.tsv")"
    [ -z "$obr" ] && continue
    plant="$PLANTILLAS/$slug.tpl"
    [ -f "$plant" ] || { echo "Falta plantilla: $plant" >&2; return 1; }
    IFS=',' read -r -a vars <<< "$obr"
    for v in "${vars[@]}"; do
      v="${v// /}"
      [ -z "$v" ] && continue
      # apps.tsv contiene descripciones embebidas como "ADMIN_PASSWORD(solobootstrap)".
      # Normalizar igual que el generador: solo el nombre base válido.
      nb="$(printf '%s' "$v" | grep -oE '^[A-Z][A-Z0-9_]{0,63}' || true)"
      [ -z "$nb" ] && continue
      grep -q "^${nb}=" "$plant" || { echo "$slug le falta $nb en $plant" >&2; return 1; }
    done
  done < <(tail -n +2 "$RAIZ/apps.tsv" | cut -f1)
}

@test "todos los formatos {{GEN:fmt}} en envs/ son soportados por secreto()" {
  formatos="$(grep -ohE '\{\{GEN:[^}]+\}\}' "$RAIZ/envs/"*.tpl | sed 's/^{{GEN://; s/}}$//' | sort -u)"
  for fmt in $formatos; do
    case "$fmt" in
      hex64|hex32|hex96|b64-32|alnum24|bcrypt:*) : ;;
      *) echo "formato no soportado en plantillas: $fmt" >&2; return 1 ;;
    esac
  done
}

@test "render_env corre sobre todas las plantillas reales y las que fallan coinciden con reporte.md" {
  [ -f "$RAIZ/reporte.md" ] || { echo "falta reporte.md; correr tools/generar-plantillas.sh primero" >&2; return 1; }
  # Anular ENVS_DIR del setup: queremos las plantillas reales de $RAIZ/envs.
  unset ENVS_DIR
  export HEFESTO_ADMIN_EMAIL="prueba@ejemplo.test"
  export SUPABASE_DB_HOST="supabase-db"
  export SUPABASE_INTERNAL_URL="http://supabase-kong:8000"
  # archivo de anon key 0600
  anon="$BATS_TEST_TMPDIR/anon.key"; printf 'anon-test-key' > "$anon"; chmod 600 "$anon"
  export SUPABASE_ANON_KEY_FILE="$anon"
  # archivo de service key 0600
  sk="$BATS_TEST_TMPDIR/sk.key"; printf 'service-test-key' > "$sk"; chmod 600 "$sk"
  export SUPABASE_KEY_FILE="$sk"

  ok=0; fail=0; fallaron=""
  while IFS=$'\t' read -r slug _; do
    [ "$slug" = "slug" ] && continue
    [ -z "$slug" ] && continue
    [ -f "$RAIZ/envs/$slug.tpl" ] || continue
    if render_env "$slug" >/dev/null 2>"$BATS_TEST_TMPDIR/render.err"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
      fallaron="$fallaron $slug"
    fi
  done < <(tail -n +2 "$RAIZ/apps.tsv" | cut -f1)

  echo "ok=$ok fail=$fail fallaron=$fallaron"
  [ "$fail" -gt 0 ]
  # Las apps que fallan deben ser EXACTAMENTE las listadas en reporte.md (las que
  # tienen alguna variable en {{PENDIENTE}}).
  esperadas="$(grep -E '^## [a-z][a-z0-9-]+ · ' "$RAIZ/reporte.md" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  obtenidas="$(printf '%s' "$fallaron" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  esperadas_norm="$(printf '%s' "$esperadas" | xargs)"
  obtenidas_norm="$(printf '%s' "$obtenidas" | xargs)"
  [ "$esperadas_norm" = "$obtenidas_norm" ] || { echo "diferencia: esperadas=$esperadas_norm obtenidas=$obtenidas_norm" >&2; return 1; }
}
