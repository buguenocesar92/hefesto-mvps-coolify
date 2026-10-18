#!/usr/bin/env bats
# verificar.sh: para cada app con dominio, hace curl al host; cuenta 200/301/302/401/403 como responde.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export APPS_TSV="$BATS_TEST_TMPDIR/apps.tsv"
  export ESTADO_DIR="$HEFESTO_MVPS_ESTADO"
  mkdir -p "$ESTADO_DIR"
  cat > "$APPS_TMV" 2>/dev/null || true
  : > "$ESTADO_DIR/apps.tsv"
  # App con dominio: responde 200
  printf 'liviana\tuuid-1\tDESPLEGADA\thttps://liviana.hefesto-studio.cl\t2026-01-01\n' >> "$ESTADO_DIR/apps.tsv"
  # App con dominio: responde 502 -> cae
  printf 'caida\tuuid-2\tDESPLEGADA\thttps://caida.hefesto-studio.cl\t2026-01-01\n' >> "$ESTADO_DIR/apps.tsv"
  responder_codigo() { printf '%s' "$3" > "$STUB_DIR/resp/$1_$(printf '%s' "$2" | tr '/?&=' '____').code${4:-}"; }
  responder_codigo() { printf '%s' "$3" > "$STUB_DIR/resp/$1_$(printf '%s' "$2" | tr '/?&=' '____').code"; }
  responder_codigo GET https://liviana.hefesto-studio.cl/ 200
  responder_codigo GET https://caida.hefesto-studio.cl/ 502
}

@test "clasifica 200 como responde y 502 como cae" {
  run "$RAIZ/verificar.sh"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"responde"* ]]
  [[ "$output" == *"cae"* ]]
  [ -f "$ESTADO_DIR/verificacion.tsv" ]
  grep -q '^liviana	https' "$ESTADO_DIR/verificacion.tsv"
}
