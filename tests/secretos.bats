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
