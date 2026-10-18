# hefesto-mvps-coolify

Herramienta que despliega las 54 apps MVP listadas en `apps.tsv` sobre una instancia
de **Coolify v4** (rama `coolify` de cada repo), separa secretos por app y deja el
estado de despliegue en un directorio local.

## Requisitos

- **VPN arriba** para llegar a la API de Coolify.
- Token de Coolify en `~/.config/hefesto/coolify-token`, modo `0600`.
- (Opcional, apps que usan Supabase REST) clave de servicio de Supabase en
  `~/.config/hefesto/supabase-service-key`, modo `0600`.
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

# 2) Desplegar por grupo (las livianas no tocan el SMTP, las pesadas se quedan
#    CREADA_DETENIDA para revisarlas antes del deploy).
./desplegar.sh --grupo liviana --dry-run
./desplegar.sh --grupo liviana --ejecutar
./desplegar.sh --grupo media   --ejecutar
./desplegar.sh --grupo pesada  --ejecutar

# 3) Verificación contra Coolify (TSV) y contra las URLs públicas.
./verificar.sh

# 4) Para cada app de alta privada, cuando esté lista:
./desplegar.sh --apps <slug> --ejecutar --publicar
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

- `<slug>.env` (0600): secretos generados por `lib/secretos.sh` (hex/hex64/b64-32,
  alnum24, bcrypt) por app. Es idempotente: la segunda llamada devuelve el mismo valor.
- `apps.tsv` (0600): `slug uuid estado url fecha` por app tras cada corrida.
- `compose.XXXXXX/`: temporales para validar el compose (se borran al cerrar).
- `supabase.sql` (0600): generado por `supabase-sql.sh`.
- `verificacion.tsv` (0600): salida de `verificar.sh`.

Conviene **respaldar el directorio en Vaultwarden o el sistema de backups del
servidor** (`$ESTADO_DIR` puede reconstruirse, pero las claves generadas se perderían
y habría que regenerarlas, lo que invalida los deploys anteriores).

## Estado de una app

Cada corrida de `desplegar.sh` registra una fila por app en `apps.tsv` con uno de
estos estados:

| Estado | Significado |
|---|---|
| `DESPLEGADA` | `docker_compose_domains` aplicado + `POST /deploy` 200 |
| `DESPLEGADA_SIN_DOMINIO` | `--publicar` aún no corrido (alta privada) |
| `CREADA_DETENIDA` | grupo `pesada`: app creada, sin deploy |
| `RECHAZADO_COMPOSE` | el compose de la rama `coolify` no pasa validar-compose.sh |

## Tests

```bash
bats tests/coolify.bats            # 5 ok — cliente de Coolify + token
bats tests/validar-compose.bats    # 8 ok — validar-compose.sh
bats tests/secretos.bats           # 6 ok — lib/secretos.sh + 54 plantillas
bats tests/desplegar.bats          # 7 ok — desplegar.sh (dry + ejecutar + idempotencia)
bats tests/supabase-sql.bats       # 2 ok — supabase-sql.sh
bats tests/verificar.bats          # 1 ok — verificar.sh
shellcheck -x *.sh lib/*.sh tests/stubs/*
```

## Repos afectados

- `hefesto-mvps-coolify/` (este repo) es la única herramienta.
- Los 54 repos en `~/Dev/<repo>` **no se tocan desde aquí**: la rama `coolify` se
  maneja en otro flujo.
