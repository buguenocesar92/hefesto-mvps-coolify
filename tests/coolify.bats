#!/usr/bin/env bats
# coolify.sh: el token viaja por fd y nunca aparece; reintenta 429; valida token y URL.
bats_require_minimum_version 1.5.0
load ayudante
setup() { preparar_entorno; source "$RAIZ/lib/comun.sh"; source "$RAIZ/lib/coolify.sh"; }

@test "api GET devuelve el cuerpo y el token viaja por descriptor, nunca en argv ni en la salida" {
  responder GET /version '"4.4.6"'
  run api GET /version
  [ "$status" -eq 0 ]; [ "$output" = '"4.4.6"' ]
  grep -qx 'token-por-fd' "$STUB_LOG"
  sin_secretos
  [[ "$output" != *TOKEN-PRUEBA* ]]
}
@test "api reintenta ante 429 y termina bien" {
  responder GET /servers '[{"uuid":"s1"}]'
  responder_codigo GET /servers 429 1
  run api GET /servers
  [ "$status" -eq 0 ]; [ "$(grep -c 'curl GET /servers' "$STUB_LOG")" -eq 2 ]
}
@test "api con 4xx sale 1 y dice método, ruta y código (sin cuerpo ni token)" {
  responder_codigo POST /projects 422
  run --separate-stderr api POST /projects
  [ "$status" -eq 1 ]; [[ "$stderr" == *"POST /projects → HTTP 422"* ]]
}
@test "coolify_validar rechaza token con permisos abiertos y URL rara" {
  chmod 644 "$COOLIFY_TOKEN_FILE"; run coolify_validar; [ "$status" -eq 1 ]
  chmod 600 "$COOLIFY_TOKEN_FILE"; COOLIFY_URL='http://x;rm' run coolify_validar; [ "$status" -eq 1 ]
  run coolify_validar; [ "$status" -eq 0 ]
}
@test "api rechaza rutas con caracteres de inyección" {
  run api GET '/servers;id'; [ "$status" -eq 1 ]; [ ! -s "$STUB_LOG" ]
}
