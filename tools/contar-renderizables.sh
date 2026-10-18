#!/usr/bin/env bash
# contar-renderizables.sh: corre render_env sobre todas las envs/*.tpl con un estado temporal y
# claves de prueba; imprime renderizables=N y no_renderizables=a,b. No toca el estado real ni
# imprime valores.
set -euo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/contar.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HEFESTO_MVPS_ESTADO="$tmp/estado" HEFESTO_ADMIN_EMAIL="prueba@ejemplo.test"
printf 'anon-test-key' > "$tmp/anon"; printf 'service-test-key' > "$tmp/sk"; chmod 600 "$tmp/anon" "$tmp/sk"
export SUPABASE_ANON_KEY_FILE="$tmp/anon" SUPABASE_KEY_FILE="$tmp/sk"
unset ENVS_DIR
# shellcheck source=lib/comun.sh
source "$RAIZ/lib/comun.sh"
# shellcheck source=lib/secretos.sh
source "$RAIZ/lib/secretos.sh"
ok=0; malas=()
for tpl in "$RAIZ"/envs/*.tpl; do
  slug="$(basename "$tpl" .tpl)"
  # shellcheck disable=SC2031  # tmp se reusa, no se modifica tras el trap.
  if render_env "$slug" >/dev/null 2>"$tmp/err"; then ok=$((ok + 1)); else malas+=("$slug"); fi
done
printf 'renderizables=%s\n' "$ok"
printf 'no_renderizables=%s\n' "$(IFS=,; printf '%s' "${malas[*]}")"
