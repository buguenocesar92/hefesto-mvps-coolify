# ayudante: rutas y entorno aislado para las suites de hefesto-mvps-coolify.
RAIZ="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"; export RAIZ
preparar_entorno() {
  export STUB_DIR="$BATS_TEST_TMPDIR/stub" STUB_LOG="$BATS_TEST_TMPDIR/llamadas.log"
  mkdir -p "$STUB_DIR/resp"; : > "$STUB_LOG"
  export PATH="$RAIZ/tests/stubs:$PATH"
  export HEFESTO_MVPS_ESTADO="$BATS_TEST_TMPDIR/estado" COOLIFY_PAUSA=0 COOLIFY_URL=http://10.77.0.1:8000
  export COOLIFY_TOKEN_FILE="$BATS_TEST_TMPDIR/token"
  printf 'TOKEN-PRUEBA-NO-REAL|abc\n' > "$COOLIFY_TOKEN_FILE"; chmod 600 "$COOLIFY_TOKEN_FILE"
}
responder() { printf '%s' "$3" > "$STUB_DIR/resp/$1_$(printf '%s' "$2" | tr '/?&=' '____')"; }
responder_codigo() { printf '%s' "$3" > "$STUB_DIR/resp/$1_$(printf '%s' "$2" | tr '/?&=' '____').code${4:+.$4}"; }
sin_secretos() { ! grep -rqF -- "TOKEN-PRUEBA-NO-REAL" "$STUB_LOG" ${1:+"$1"}; }
