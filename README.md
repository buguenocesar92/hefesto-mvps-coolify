# hefesto-mvps-coolify

Herramienta que despliega las 54 apps MVP listadas en `apps.tsv` sobre una instancia
de **Coolify v4** (rama `coolify` de cada repo), separa secretos por app y deja el
estado de despliegue en un directorio local.

## Requisitos

- **VPN arriba** para llegar a la API de Coolify.
- Token de Coolify en `~/.config/hefesto/coolify-token`, modo `0600`. Debe traer los
  scopes `read`, `write`, `deploy` y **`read:sensitive`** (este último es obligatorio
  para que `instalar-supabase.sh` pueda leer el `service_role`, el `anon` y la
  contraseña de postgres del servicio Supabase de un clic). Un token con `write`
  también puede ejecutar comandos en los contenedores mediante **scheduled tasks**,
  así que hay que guardarlo como un secreto de root (no en Vaultwarden compartido ni
  en scripts del repo).
- (Obligatorio, apps que usan Supabase REST) clave de servicio de Supabase en
  `~/.config/hefesto/supabase-service-key`, modo `0600`.
- (Apps con `{{SUPABASE_ANON_KEY}}`) clave anon en
  `~/.config/hefesto/supabase-anon-key`, modo `0600`.
- (Apps con `{{RESEND_API_KEY}}`, SMTP) clave de Resend en
  `~/.config/hefesto/resend.env`, modo `0600`. Formato `RESEND_API_KEY=re_...`.
- (Apps con `{{ADMIN_EMAIL}}`) `HEFESTO_ADMIN_EMAIL=tu@correo` en el entorno.
- `bats`, `jq`, `shellcheck`, `docker compose`, `curl`, `openssl`, `htpasswd`, `python3` en el
  PATH (los tests de `lib/*.sh` los necesitan).
- El árbol de cada repo en `~/Dev/<repo>`, con la rama `coolify` ya subida.

## Orden de uso

```bash
# 1) Crear (o reusar) el servicio Supabase de un clic en Coolify, fijar la red
#    interna con las apps, configurar el SMTP de GoTrue con Resend, arrancar el
#    servicio y dejar los secretos del servicio (service_role, anon, postgres) en
#    archivos 0600. Con --dry-run imprime el plan sin tocar la API.
./instalar-supabase.sh --dry-run
./instalar-supabase.sh --ejecutar

# 2) Aplicar el SQL por app con una scheduled task por base. Con --dry-run imprime
#    el plan; con --ejecutar crea la task (container=supabase-db, enabled=false),
#    la ejecuta y registra SQL_OK/SQL_ERROR en $ESTADO_DIR/sql.tsv (0600).
./aplicar-sql.sh --todas --dry-run
./aplicar-sql.sh --todas --ejecutar

# 3) Desplegar las apps por grupo. Las pesadas se quedan CREADA_DETENIDA hasta el --publicar.
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
  b64-32, alnum24, laravel, bcrypt:VAR, pbkdf2:VAR) por app. Las claves planas de los hash
  quedan aquí: `<X>_PASSWORD` por cada `<X>_HASH` (bcrypt coste 12) y
  `SALTED_PASS_PLANO` para el login de vigilancia. `DB_PASSWORD` es hex64; si un `.env`
  anterior tiene un `DB_PASSWORD` de 32 caracteres, se conserva (idempotencia): bórralo a
  mano antes de `supabase-sql.sh` si el kit exige hex64. Es idempotente: la segunda
  llamada devuelve el mismo valor.
- `apps.tsv` (0600): `slug uuid estado url fecha` por app tras cada corrida.
- `supabase.uuid` (0600): uuid del servicio Supabase de un clic en Coolify; lo crea
  `instalar-supabase.sh --ejecutar` y lo reusa en corridas siguientes.
- `supabase-postgres.pass` (0600): `SERVICE_PASSWORD_POSTGRES` del servicio Supabase.
- `compose.XXXXXX/`, `sql.XXXXXX/`: temporales para validar compose y armar SQL (se
  borran al cerrar, modo 0700).
- `supabase.sql` (0600): concatenado, generado por `supabase-sql.sh` (compatibilidad).
- `sql/<slug>.sql` (0600): uno por app, generado por `supabase-sql.sh --por-app`. Es
  lo que `aplicar-sql.sh` ejecuta dentro del contenedor `supabase-db-<uuid>`.
- `sql.tsv` (0600): `slug estado fecha` por app tras `aplicar-sql.sh --ejecutar`.
- `verificacion.tsv` (0600): salida de `verificar.sh` con la clasificación
  `responde`/`cae`.

Conviene **respaldar el directorio en Vaultwarden o el sistema de backups del
servidor** (`$ESTADO_DIR` puede reconstruirse, pero las claves generadas se perderían
y habría que regenerarlas, lo que invalida los deploys anteriores).

## Qué hace `tools/generar-plantillas.sh`

Lee `apps.tsv` y produce `envs/<slug>.tpl` (54 archivos) con la tabla de deducción
del plan (URL/HOST, DB_*, *_VOLUME, *_PUBLIC_URL, SMTP con Resend, etc.). Las
plantillas que piden algún campo SMTP se completan con `smtp.resend.com:465`, usuario
`resend` y contraseña `{{RESEND_API_KEY}}` (que `render_env` lee de `$RESEND_ENV_FILE`).
Excepciones: `marketing` (Mautic) usa `MAILER_DSN=null://null` y `boletines`
(listmonk) usa `DELIVERY_ENABLED=false`. Las variables que la tabla no resuelve
quedan como `{{PENDIENTE}}` y se anotan en `reporte.md`. `render_env` las anuncia y
`desplegar.sh` marca la app como `NECESITA_DATOS` sin tocar la API.

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
bats tests/coolify.bats              # 5 ok  — cliente de Coolify + token
bats tests/validar-compose.bats      # 10 ok — validar-compose.sh (docker compose real; skip sin docker)
bats tests/secretos.bats             # 15 ok — lib/secretos.sh + render de las 54 plantillas
bats tests/desplegar.bats            # 11 ok — desplegar.sh (dry, ejecutar, publicar, NECESITA_DATOS)
bats tests/red-interna.bats          # 4 ok  — connect_to_docker_network + DB_HOST/SUPABASE_URL internos
bats tests/instalar-supabase.bats    # 6 ok  — instalar-supabase.sh (servicio, red, SMTP, secretos 0600)
bats tests/aplicar-sql.bats          # 7 ok  — aplicar-sql.sh (scheduled task, idempotencia, sql.tsv)
bats tests/supabase-sql.bats         # 4 ok  — supabase-sql.sh (rol del kit, idempotencia, DB_PASSWORD hex64)
bats tests/plantillas-resend.bats    # 7 ok  — SMTP con Resend en las plantillas
bats tests/verificar.bats            # 1 ok  — verificar.sh
bats tests/generar-plantillas.bats   # 7 ok  — tabla de deducción del generador
tools/contar-renderizables.sh        # renderizables=52, no_renderizables=ordenia,respaldos
shellcheck -x *.sh lib/*.sh tests/stubs/* tools/*.sh
```

## Repos afectados

- `hefesto-mvps-coolify/` (este repo) es la única herramienta.
- Los 54 repos en `~/Dev/<repo>` **no se tocan desde aquí**: la rama `coolify` se
  maneja en otro flujo.
