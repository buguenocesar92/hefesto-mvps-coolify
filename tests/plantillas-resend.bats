#!/usr/bin/env bats
# Tarea 4: SMTP con Resend en las plantillas.
# - render_env resuelve {{RESEND_API_KEY}} desde $RESEND_ENV_FILE y no lo imprime fuera del JSON.
# - Si falta el archivo, error claro.
# - Las 54 plantillas siguen renderizando salvo ordenia y respaldos.
# - marketing.tpl NO contiene {{RESEND_API_KEY}} (MAILER_DSN=null://null).
# - boletines.tpl NO contiene {{RESEND_API_KEY}}.
# - El generador produce las nuevas reglas: SMTP_HOST=smtp.resend.com, SMTP_PORT=465, etc.
bats_require_minimum_version 1.5.0
load ayudante

setup() {
  preparar_entorno
  export RESEND_ENV_FILE="$BATS_TEST_TMPDIR/resend.env"
  printf 'RESEND_API_KEY=re_PRUEBA\n' > "$RESEND_ENV_FILE"; chmod 600 "$RESEND_ENV_FILE"
  export HEFESTO_ADMIN_EMAIL="prueba@ejemplo.test"
  export SUPABASE_ANON_KEY_FILE="$BATS_TEST_TMPDIR/anon.key"
  export SUPABASE_KEY_FILE="$BATS_TEST_TMPDIR/sk.key"
  printf 'anon-test-key' > "$SUPABASE_ANON_KEY_FILE"; chmod 600 "$SUPABASE_ANON_KEY_FILE"
  printf 'service-test-key' > "$SUPABASE_KEY_FILE"; chmod 600 "$SUPABASE_KEY_FILE"
  source "$RAIZ/lib/comun.sh"
  source "$RAIZ/lib/secretos.sh"
}

@test "render_env resuelve {{RESEND_API_KEY}} desde resend.env y el valor no aparece fuera del JSON" {
  ENVS_DIR="$BATS_TEST_TMPDIR/envs"
  mkdir -p "$ENVS_DIR"
  printf 'SMTP_HOST=smtp.resend.com\nSMTP_PORT=465\nSMTP_USER=resend\nSMTP_PASSWORD={{RESEND_API_KEY}}\n' > "$ENVS_DIR/demo.tpl"
  out="$(render_env demo)"
  echo "$out" | jq -e '.data[] | select(.key=="SMTP_PASSWORD") | .value == "re_PRUEBA"' >/dev/null
  # El valor del secreto no debe aparecer fuera del JSON.
  [[ "$(echo "$out" | grep -c 're_PRUEBA')" -eq 1 ]]
}

@test "render_env con RESEND_ENV_FILE ausente: error claro, sale 1" {
  rm -f "$RESEND_ENV_FILE"
  ENVS_DIR="$BATS_TEST_TMPDIR/envs"
  mkdir -p "$ENVS_DIR"
  printf 'SMTP_PASSWORD={{RESEND_API_KEY}}\n' > "$ENVS_DIR/demo.tpl"
  run --separate-stderr render_env demo
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"RESEND"* ]] || [[ "$stderr" == *"resend"* ]]
}

@test "render_env de las 54 plantillas reales: solo ordenia y respaldos quedan pendientes" {
  export HEFESTO_ADMIN_EMAIL="prueba@ejemplo.test"
  unset ENVS_DIR
  ok=0; obtenidas=()
  for tpl in "$RAIZ"/envs/*.tpl; do
    slug="$(basename "$tpl" .tpl)"
    err="$BATS_TEST_TMPDIR/$slug.err"
    if render_env "$slug" >/dev/null 2>"$err"; then
      ok=$((ok + 1))
    else
      obtenidas+=("$slug")
      [ -s "$err" ] || { echo "$slug falló sin decir por qué" >&2; return 1; }
      if grep -qv '^pendiente: ' "$err"; then
        echo "$slug falló por algo que no es un pendiente:" >&2; cat "$err" >&2; return 1
      fi
    fi
  done
  obt="$(printf '%s\n' "${obtenidas[@]}" | sed '/^$/d' | sort -u | xargs)"
  [ "$obt" = "ordenia respaldos" ] || { echo "pendientes=[$obt]" >&2; return 1; }
  [ "$ok" -eq $(( $(find "$RAIZ/envs" -maxdepth 1 -name '*.tpl' | wc -l) - 2 )) ]
}

@test "marketing.tpl NO contiene {{RESEND_API_KEY}} (MAILER_DSN=null://null)" {
  ! grep -q '{{RESEND_API_KEY}}' "$RAIZ/envs/marketing.tpl"
  grep -q 'MAILER_DSN=null://null' "$RAIZ/envs/marketing.tpl"
}

@test "boletines.tpl NO contiene {{RESEND_API_KEY}}" {
  ! grep -q '{{RESEND_API_KEY}}' "$RAIZ/envs/boletines.tpl"
}

@test "las plantillas con SMTP ahora apuntan a smtp.resend.com:465 con usuario resend" {
  for f in formularios ideas eventos publicaciones; do
    grep -qx 'SMTP_HOST=smtp.resend.com' "$RAIZ/envs/$f.tpl"
    grep -qx 'SMTP_PORT=465' "$RAIZ/envs/$f.tpl"
    case "$f" in
      formularios|eventos) grep -qx 'SMTP_USER=resend' "$RAIZ/envs/$f.tpl" ;;
      ideas)               grep -qx 'SMTP_USERNAME=resend' "$RAIZ/envs/$f.tpl" ;;
      publicaciones)       grep -qx 'SMTP_USERNAME=resend' "$RAIZ/envs/$f.tpl" ;;
    esac
    grep -qE '^SMTP_(PASS|PASSWORD)=\{\{RESEND_API_KEY\}\}$' "$RAIZ/envs/$f.tpl"
    grep -qx 'SMTP_READY=true' "$RAIZ/envs/$f.tpl"
  done
}

@test "MAILER_DSN/MAILER_URL en plantillas con SMTP van con smtps://resend:{{RESEND_API_KEY}}@smtp.resend.com:465" {
  # Si hay plantillas con MAILER_DSN, deben usar el esquema nuevo.
  if grep -lE '^MAILER_(DSN|URL)=' "$RAIZ/envs/"*.tpl >/dev/null 2>&1; then
    for f in $(grep -lE '^MAILER_(DSN|URL)=' "$RAIZ/envs/"*.tpl); do
      case "$(basename "$f" .tpl)" in
        marketing) grep -qx 'MAILER_DSN=null://null' "$f" ;;
        *) grep -qE '^MAILER_(DSN|URL)=smtps://resend:\{\{RESEND_API_KEY\}\}@smtp.resend.com:465$' "$f" ;;
      esac
    done
  fi
}