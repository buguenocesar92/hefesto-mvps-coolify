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
      hex64|hex32|hex96|b64-32|alnum24|laravel|bcrypt:*|pbkdf2:*) : ;;
      *) echo "formato no soportado en plantillas: $fmt" >&2; return 1 ;;
    esac
  done
}

@test "render_env sobre todas las plantillas reales: fallan solo por pendientes, coinciden con los .tpl y con reporte.md, y solo ordenia/respaldos" {
  [ -f "$RAIZ/reporte.md" ] || { echo "falta reporte.md; correr tools/generar-plantillas.sh" >&2; return 1; }
  unset ENVS_DIR
  export HEFESTO_ADMIN_EMAIL="prueba@ejemplo.test"
  anon="$BATS_TEST_TMPDIR/anon.key"; printf 'anon-test-key' > "$anon"; chmod 600 "$anon"; export SUPABASE_ANON_KEY_FILE="$anon"
  sk="$BATS_TEST_TMPDIR/sk.key"; printf 'service-test-key' > "$sk"; chmod 600 "$sk"; export SUPABASE_KEY_FILE="$sk"
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
  tpl_pend="$(grep -l '{{PENDIENTE}}' "$RAIZ"/envs/*.tpl | xargs -r -n1 basename | sed 's/\.tpl$//' | sort -u | xargs)"
  rep="$(grep -E '^## [a-z][a-z0-9-]+ · ' "$RAIZ/reporte.md" | awk '{print $2}' | sort -u | xargs)"
  echo "renderizables=$ok no_renderizables=$obt"
  [ "$obt" = "$tpl_pend" ] || { echo "fallan=[$obt] pero tienen PENDIENTE=[$tpl_pend]" >&2; return 1; }
  [ "$obt" = "$rep" ] || { echo "fallan=[$obt] pero reporte.md=[$rep]" >&2; return 1; }
  for s in "${obtenidas[@]}"; do
    case "$s" in ordenia|respaldos) ;; *) echo "$s no debería quedar pendiente" >&2; return 1 ;; esac
  done
  [ "$ok" -eq $(( $(find "$RAIZ/envs" -maxdepth 1 -name '*.tpl' | wc -l) - ${#obtenidas[@]} )) ]
}

@test "{{HOST:<slug>}} se expande a <slug>.\$DOMINIO_BASE, también dentro de otro valor" {
  printf 'PANEL_HOST={{HOST:panel-enlaces}}\nCORS={{URL}},https://{{HOST:panel-enlaces}}\n' > "$ENVS_DIR/demo.tpl"
  out="$(render_env demo)"
  echo "$out"
  echo "$out" | jq -e '.data[] | select(.key=="PANEL_HOST") | .value == "panel-enlaces.hefesto-studio.cl"' >/dev/null
  echo "$out" | jq -e '.data[] | select(.key=="CORS") | .value == "https://demo.hefesto-studio.cl,https://panel-enlaces.hefesto-studio.cl"' >/dev/null
}

@test "{{COPIA:VAR}} copia el valor ya resuelto de VAR (literal o generado)" {
  cat > "$ENVS_DIR/demo.tpl" <<'EOF'
A_USER=hefesto
A_PASS={{GEN:hex64}}
B_USER={{COPIA:A_USER}}
B_PASS={{COPIA:A_PASS}}
EOF
  out="$(render_env demo)"
  echo "$out" | jq -e '(.data | map({(.key): .value}) | add) as $m
    | $m.B_USER == "hefesto" and $m.B_PASS == $m.A_PASS and ($m.A_PASS | test("^[0-9a-f]{64}$"))' >/dev/null
}

@test "{{COPIA:VAR}} falla si VAR no aparece antes en la plantilla" {
  printf 'B={{COPIA:NO_EXISTE}}\n' > "$ENVS_DIR/demo.tpl"
  run --separate-stderr render_env demo
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"COPIA:NO_EXISTE"* ]]
}

@test "{{DB_PASSWORD}} es hex64 y es el mismo DB_PASSWORD guardado para la app" {
  printf 'DB_PASSWORD={{DB_PASSWORD}}\nPOSTGRES_PASSWORD={{DB_PASSWORD}}\n' > "$ENVS_DIR/demo.tpl"
  out="$(render_env demo)"
  guardado="$(grep '^DB_PASSWORD=' "$HEFESTO_MVPS_ESTADO/demo.env" | cut -d= -f2-)"
  echo "$out" | jq -e --arg g "$guardado" '(.data | map({(.key): .value}) | add) as $m
    | $m.DB_PASSWORD == $g and $m.POSTGRES_PASSWORD == $g and ($g | test("^[0-9a-f]{64}$"))' >/dev/null
}

@test "laravel genera base64: más 32 bytes en base64" {
  v="$(secreto demo APP_KEY laravel)"
  [[ "$v" =~ ^base64:[A-Za-z0-9+/]{43}=$ ]]
  [ "$(printf '%s' "${v#base64:}" | base64 -d | wc -c)" -eq 32 ]
}

@test "pbkdf2:<VAR_PLANO> da base64(salt32+pbkdf2_sha256(clave,salt,100000)) y guarda la clave plana" {
  v="$(secreto vig SALTED_PASS pbkdf2:SALTED_PASS_PLANO)"
  plano="$(grep '^SALTED_PASS_PLANO=' "$HEFESTO_MVPS_ESTADO/vig.env" | cut -d= -f2-)"
  [ -n "$plano" ]
  printf '%s\n%s\n' "$v" "$plano" | python3 -I -c 'import sys,base64,hashlib
v,p=sys.stdin.read().split("\n")[:2]
b=base64.b64decode(v)
assert len(b)==64
assert hashlib.pbkdf2_hmac("sha256",p.encode(),b[:32],100000)==b[32:]'
}

@test "bcrypt usa coste 12 y guarda la clave plana con el nombre pedido" {
  h="$(secreto demo NR_ADMIN_HASH bcrypt:NR_ADMIN_PASSWORD)"
  [[ "$h" == '$2y$12$'* ]]
  grep -qE '^NR_ADMIN_PASSWORD=[A-Za-z0-9]{24}$' "$HEFESTO_MVPS_ESTADO/demo.env"
}
