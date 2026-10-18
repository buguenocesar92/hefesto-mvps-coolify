# hefesto-mvps-coolify

Herramienta que despliega las 54 apps MVP listadas en `apps.tsv` sobre una instancia
de **Coolify v4** (rama `coolify` de cada repo), separa secretos por app y deja el
estado de despliegue en un directorio local.

## Requisitos

- **VPN arriba** para llegar a la API de Coolify.
- Token de Coolify en `~/.config/hefesto/coolify-token`, modo `0600`.
- (Obligatorio, apps que usan Supabase REST) clave de servicio de Supabase en
  `~/.config/hefesto/supabase-service-key`, modo `0600`.
- (Apps con `{{SUPABASE_ANON_KEY}}`) clave anon en
  `~/.config/hefesto/supabase-anon-key`, modo `0600`.
- (Apps con `{{ADMIN_EMAIL}}`) `HEFESTO_ADMIN_EMAIL=tu@correo` en el entorno.
- `bats`, `jq`, `shellcheck`, `docker compose`, `curl`, `openssl`, `htpasswd` en el
  PATH (los tests de `lib/*.sh` los necesitan).
- El árbol de cada repo en `~/Dev/<repo>`, con la rama `coolify` ya subida.

## Orden de uso

```bash
# 1) Generar el SQL de supabase y aplicarlo dentro del contenedor supabase-db.
./supabase-sql.sh --todas
#   imprime la ruta de $ESTADO_DIR/supabase.sql y el conteo de bases/migraciones.
#   aplicarlo:
docker exec -i supabase-db psql -U postgres < "$HOME/.local/state/hefesto-mvps/supabase.sql"

# 2) (Opcional) Regenerar las plantillas si apps.tsv cambió.
tools/generar-plantillas.sh
#   Revisar reporte.md para saber qué variables quedaron en {{PENDIENTE}}.

# 3) Desplegar por grupo. Las pesadas se quedan CREADA_DETENIDA hasta el --publicar.
./desplegar.sh --grupo liviana --dry-run          # siempre primero, sin tocar la API
./desplegar.sh --grupo liviana --ejecutar
./desplegar.sh --grupo media   --ejecutar
./desplegar.sh --grupo pesada  --ejecutar        # crea la app, la deja detenida

# 4) Para cada app de alta privada, cuando esté lista:
./desplegar.sh --apps <slug> --ejecutar --publicar
#   --publicar parsea `# publicar: VAR=true` de la plantilla, sobreescribe el JSON,
#   PATCH envs/bulk, asigna dominio y redespliega (también las pesadas).

# 5) Verificación contra Coolify (TSV) y contra las URLs públicas.
./verificar.sh
```

## Qué valida `validar-compose.sh`

`validar-compose.sh <directorio> <archivo-compose>` corre
`docker compose config --format json` sobre el compose de la rama `coolify` y rechaza
todo lo que abre la puerta a Coolify ejecutando cosas a nivel host:

- `privileged: true` y `cap_add`/`devices` no vacíos.
- `network_mode: host` o `container:ID`.
- `pid: host`, `ipc: host`.
- `ports` (los asigna Coolify al publicar el dominio).
- `container_name` presente.
- Volúmenes `type=="bind"` cuyo `source` esté fuera del proyecto o apunte a
  `/var/run/docker.sock` (o cualquier path que lo contenga).
- `security_opt` con `apparmor:unconfined` o `seccomp:unconfined`.

Los servicios con `profiles` no vacío se ignoran (Coolify no arranca perfiles
opcionales).

## Dónde quedan los secretos

Todo se persiste en `~/.local/state/hefesto-mvps/` (override con
`HEFESTO_MVPS_ESTADO`):

- `<slug>.env` (0600): secretos generados por `lib/secretos.sh` (hex64, hex32, hex96,
  b64-32, alnum24, bcrypt:VAR) por app. Es idempotente: la segunda llamada devuelve el
  mismo valor.
- `apps.tsv` (0600): `slug uuid estado url fecha` por app tras cada corrida.
- `compose.XXXXXX/`, `sql.XXXXXX/`: temporales para validar compose y armar SQL (se
  borran al cerrar, modo 0700).
- `supabase.sql` (0600): generado por `supabase-sql.sh`.
- `verificacion.tsv` (0600): salida de `verificar.sh` con la clasificación
  `responde`/`cae`.

Conviene **respaldar el directorio en Vaultwarden o el sistema de backups del
servidor** (`$ESTADO_DIR` puede reconstruirse, pero las claves generadas se perderían
y habría que regenerarlas, lo que invalida los deploys anteriores).

## Qué hace `tools/generar-plantillas.sh`

Lee `apps.tsv` y produce `envs/<slug>.tpl` (54 archivos) con la tabla de deducción
del plan (URL/HOST, SMTP apagado, DB_*, *_VOLUME, *_PUBLIC_URL, etc.). Las
variables que la tabla no resuelve quedan como `{{PENDIENTE}}` y se anotan en
`reporte.md`. `render_env` las anuncia y `desplegar.sh` marca la app como
`NECESITA_DATOS` sin tocar la API.

## Estado de una app

Cada corrida de `desplegar.sh` registra una fila por app en `apps.tsv` con uno de
estos estados:

| Estado | Significado |
|---|---|
| `DESPLEGADA` | `docker_compose_domains` aplicado + `POST /deploy` 200 |
| `DESPLEGADA_SIN_DOMINIO` | `--publicar` aún no corrido (alta privada) |
| `CREADA_DETENIDA` | grupo `pesada`: app creada, sin deploy (o `--publicar` aún no corrido) |
| `RECHAZADO_COMPOSE` | el compose de la rama `coolify` no pasa validar-compose.sh |
| `NECESITA_DATOS` | la plantilla tiene alguna variable `{{PENDIENTE}}` (ver `reporte.md`) |
| `ERROR_<paso>` | falló un paso (CREAR / UUID / COMPOSE_RAW / ENVS / ENVS_BULK / DOMINIO / DEPLOY / PUBLIC_ENVS) |

## Tests

```bash
bats tests/coolify.bats            # 5 ok — cliente de Coolify + token
bats tests/validar-compose.bats    # 8 ok — validar-compose.sh (docker compose real)
bats tests/secretos.bats           # 8 ok — lib/secretos.sh + 54 plantillas
bats tests/desplegar.bats          # 8 ok — desplegar.sh (dry + ejecutar + publicar + idempotencia)
bats tests/supabase-sql.bats       # 2 ok — supabase-sql.sh
bats tests/verificar.bats          # 1 ok — verificar.sh
shellcheck -x *.sh lib/*.sh tests/stubs/* tools/*.sh
```

## Repos afectados

- `hefesto-mvps-coolify/` (este repo) es la única herramienta.
- Los 54 repos en `~/Dev/<repo>` **no se tocan desde aquí**: la rama `coolify` se
  maneja en otro flujo.
