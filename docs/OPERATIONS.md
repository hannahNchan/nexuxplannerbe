# NexusPlanner Backend Operations

Ultima revision: 2026-09-26

## 1. Objetivo

Este manual cubre instalacion local, Edge Functions, migraciones, worker, backups y despliegue sobre un host permanente como una Raspberry Pi. Distingue de forma estricta entre entornos desechables y la base que contiene informacion personal.

Principio central:

> El repositorio contiene definicion y codigo; la base, Auth, objetos y secretos pertenecen al entorno desplegado.

Clonar o actualizar Git no debe borrar ni reemplazar el volumen de datos. Aplicar migraciones cambia estructura, no debe importar datos del seed salvo catalogos globales.

## 2. Modos de ejecucion

### Desarrollo local desechable

Supabase CLI administra contenedores locales. Se puede usar `db reset` porque los datos son de prueba y se reconstruyen desde migraciones y seed.

### Desarrollo local contra la Raspberry

Frontend y CLI corren en la PC, pero apuntan a la API de la Raspberry. El backend no necesita levantarse tambien en la PC. Este modo usa datos reales y cualquier comando de usuario puede modificarlos.

### Validacion backend aislada

Se levanta una instancia local desde este repo para probar migraciones y funciones sin tocar la Raspberry. Es el modo recomendado antes de desplegar cambios.

### Host permanente/Raspberry

El host ejecuta el stack persistente y las Edge Functions. El checkout Git aporta migraciones y codigo; el volumen persistente conserva la informacion. No existe todavia un `docker-compose.yml` de produccion versionado en este repositorio: la operacion actual se apoya en Supabase CLI o en la instalacion self-hosted ya existente del host.

## 3. Requisitos

- Linux para el flujo documentado de instalacion compartible.
- Docker Engine activo y soporte de Docker Compose.
- Node.js 18 o superior.
- npm.
- Git.
- Espacio suficiente para imagenes, volumen de Postgres, Storage y backups.
- Para host remoto: SSH y una cuenta sin exposicion publica de credenciales.

Comprobar:

```bash
docker version
docker compose version
node --version
npm --version
git --version
```

## 4. Instalacion local desde cero

```bash
git clone https://github.com/hannahNchan/nexuxplannerbe.git nexusplannerbe
cd nexusplannerbe
npm install
cp .env.example .env
npm run start
npm run status
```

`npm run start` crea/inicia el stack local. La primera ejecucion descarga imagenes y puede tardar.

Copiar desde `npm run status` la URL y claves generadas hacia `.env`. Los valores deben ser texto plano, no enlaces Markdown:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<publishable-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-or-secret-key>
NEXUS_API_URL=http://127.0.0.1:54321
NEXUS_PUBLISHABLE_KEY=<publishable-key>
JOB_WORKER_SECRET=<random-local-secret>
```

Aplicar desde cero esquema y catalogos:

```bash
npm run reset
```

Este comando es destructivo para la base local seleccionada. Debe usarse solo en una instancia desechable creada para este repo.

## 5. Puertos locales

La configuracion versionada usa:

| Capacidad | URL/puerto |
| --- | --- |
| API gateway | `http://127.0.0.1:54321` |
| PostgreSQL | `127.0.0.1:54322` |
| Studio | `http://127.0.0.1:54323` |
| Mailpit | `http://127.0.0.1:54324` |
| Analytics | `127.0.0.1:54327` |
| Shadow DB | `127.0.0.1:54320` |
| Edge inspector | `127.0.0.1:8083` |

El gateway expone REST, GraphQL, Auth, Realtime, Storage y Edge Functions bajo la misma base URL.

## 6. Edge Functions en desarrollo

Con Supabase ya iniciado, abrir otra terminal:

```bash
npm run functions:serve
```

El script equivale a:

```bash
npx supabase functions serve --env-file .env
```

Si aparece que `.env` no existe:

```bash
cp .env.example .env
```

Luego completar las claves usando `npm run status`. No poner espacios alrededor de `=` ni escapar guiones bajos.

Las funciones se sirven en:

```text
http://127.0.0.1:54321/functions/v1/<function-name>
```

Funciones disponibles:

- `workspace-commands`
- `task-commands`
- `epic-commands`
- `sprint-commands`
- `notification-commands`
- `agent-commands`
- `job-worker`

## 7. Usuarios de prueba

El seed no crea usuarios. Para un entorno local limpio:

1. Abrir Studio en `http://127.0.0.1:54323`.
2. Ir a Authentication, Users.
3. Crear un usuario de prueba con email y password.
4. Iniciar sesion desde el frontend o CLI.

El login falla con `Invalid login credentials` si el usuario no existe aunque la configuracion de email sea correcta. El error `Unsupported provider: provider is not enabled` indica que el cliente intento un proveedor OAuth no habilitado; el entorno actual esta configurado para email/password.

## 8. Conectar el frontend

En `.env.local` del frontend:

```env
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY=<publishable-key>
VITE_AUTH_REDIRECT_URL=http://localhost:5173
```

Reiniciar Vite despues de cambiar variables. Vite las carga al arrancar; modificar el archivo con el proceso vivo no garantiza que las peticiones cambien de host.

Para apuntar a la Raspberry, reemplazar `127.0.0.1` por su hostname o IP actual y usar la publishable key de esa instalacion. No copiar service role al frontend.

## 9. Flujo de migraciones

### Crear

```bash
npx supabase migration new descriptive_change_name
```

Editar el archivo generado en `supabase/migrations`. Una migracion debe ser legible, determinista y segura al ejecutarse una sola vez en orden.

### Validar localmente

```bash
npm run start
npm run reset
npm run functions:serve
```

Probar:

- instalacion vacia;
- datos representativos sin informacion personal;
- usuario autorizado;
- usuario de otro tenant;
- rollback funcional o plan de correccion;
- integridad de FKs, triggers, RLS y Storage.

### Revisar SQL pendiente

Antes de aplicar a un host con datos:

```bash
npx supabase migration list
npx supabase db push --dry-run --db-url "$NEXUS_DB_URL"
```

La disponibilidad exacta de flags depende de la version fijada por `package-lock.json`; confirmar con:

```bash
npx supabase db push --help
```

### Aplicar en una base existente

Solo despues de backup y prueba de restauracion:

```bash
npx supabase db push --db-url "$NEXUS_DB_URL"
```

`NEXUS_DB_URL` es una variable administrativa privada con la conexion PostgreSQL. No guardarla en Git ni mostrarla en historial compartido.

No usar `db reset` en la Raspberry con informacion real.

## 10. Baseline y migraciones incrementales

`00000000000000_baseline_schema.sql` representa el punto inicial importable sin datos. No es un dump de la instancia personal.

Reglas:

- No reemplazar el baseline con un dump que incluya usuarios o datos.
- No reescribir migraciones ya aplicadas para "arreglar" produccion.
- Cada cambio posterior obtiene un timestamp nuevo.
- `seed.sql` conserva solo catalogos universales.
- Si una instalacion ya existia antes del baseline, registrar cuidadosamente el historial de migraciones sin volver a ejecutar DDL incompatible.

## 11. Despliegue seguro a la Raspberry

### Estructura recomendada

```text
/srv/nexusplanner/
  backend/          # checkout de este repositorio
  backups/          # fuera de Git, permisos restringidos
  runtime/          # archivos de entorno/configuracion privada
  storage/          # si el self-hosting monta archivos aqui
```

Los nombres exactos pueden variar. Lo importante es separar checkout, secretos, volumen y backups.

### Flujo por release

1. Desarrollar en PC en una rama.
2. Probar contra Supabase local desechable.
3. Revisar diff de migraciones y funciones.
4. Hacer commit y push a GitHub.
5. Crear backup consistente de la Raspberry.
6. En la Raspberry, traer el commit aprobado con `git fetch` y `git pull --ff-only`.
7. Ejecutar `npm ci` si cambiaron dependencias.
8. Inspeccionar migraciones pendientes.
9. Aplicar solo las migraciones aprobadas.
10. Reiniciar/recargar Edge Functions segun el supervisor real.
11. Ejecutar smoke tests.
12. Observar logs antes de declarar el despliegue terminado.

Ejemplo de actualizacion de codigo:

```bash
cd /srv/nexusplanner/backend
git status --short
git fetch origin
git pull --ff-only origin main
npm ci
```

No hacer `git reset --hard` sobre un checkout con cambios no inventariados. Si aparecen cambios hechos directamente en la Raspberry, revisarlos y llevarlos primero a una rama/commit.

### Donde se desarrolla

Los cambios backend deben hacerse normalmente en la PC, subirse al repo y desplegarse a la Raspberry. Editar en la Raspberry crea divergencia y dificulta reproducibilidad. Si una correccion urgente se hace alli:

1. Crear una rama.
2. Commit del cambio, sin secretos.
3. Push al remoto.
4. Llevar la rama a la PC, revisar y fusionar.
5. Volver a dejar la Raspberry en `main` limpio.

## 12. Backups

Un backup util no es solo un archivo creado: debe poder restaurarse.

### Antes de cada migracion delicada

Respaldar por separado:

- esquemas y datos de PostgreSQL;
- roles necesarios;
- Auth si no queda incluido por el metodo de dump;
- metadatos y objetos de Storage;
- secretos/configuracion, en almacenamiento cifrado separado;
- commit exacto desplegado.

Ejemplo logico desde un host autorizado:

```bash
mkdir -p /srv/nexusplanner/backups/$(date +%Y%m%d-%H%M%S)
pg_dump "$NEXUS_DB_URL" --format=custom --file=/srv/nexusplanner/backups/<timestamp>/database.dump
```

No colocar dumps dentro del repositorio. Ajustar propietario y permisos:

```bash
chmod 700 /srv/nexusplanner/backups
chmod 600 /srv/nexusplanner/backups/<timestamp>/database.dump
```

### Verificacion

- Confirmar exit code y tamano no trivial.
- Generar checksum.
- Listar contenido con `pg_restore --list`.
- Restaurar periodicamente en una instancia aislada.
- Verificar conteos, login de prueba, RLS, reportes y Storage.

### Retencion

Conservar al menos:

- ultimo backup previo a despliegue;
- backups diarios recientes;
- backups semanales/mensuales segun capacidad;
- una copia fuera de la Raspberry.

Una tarjeta SD y su backup en la misma tarjeta comparten el mismo punto de falla.

## 13. Restauracion

La restauracion debe ocurrir primero en un entorno aislado:

1. Provisionar Postgres compatible.
2. Restaurar roles/esquema/datos con la herramienta correspondiente.
3. Restaurar Storage y su metadata de forma consistente.
4. Configurar secretos sin copiarlos a Git.
5. Levantar APIs/funciones.
6. Ejecutar smoke tests como usuario real de prueba.
7. Solo entonces planear el cambio de trafico.

No ejecutar `pg_restore --clean` contra la base personal sin una ventana y plan de rollback explicitos.

## 14. Worker y jobs

El worker se invoca por HTTP y necesita el secreto configurado. Ejemplo local:

```bash
curl -X POST \
  http://127.0.0.1:54321/functions/v1/job-worker \
  -H "Content-Type: application/json" \
  -H "x-job-worker-secret: $JOB_WORKER_SECRET" \
  -d '{"queueName":"default","limit":10}'
```

No hay scheduler versionado. Para ejecucion permanente se necesita systemd timer, cron o scheduler equivalente que:

- use el secreto desde un archivo protegido;
- tenga timeout;
- registre status sin imprimir secretos;
- evite ejecuciones superpuestas excesivas;
- invoque mantenimiento de jobs estancados.

No asumir que `done` significa que una integracion externa se ejecuto: revisar los tipos no-op documentados en `ARCHITECTURE.md`.

## 15. Health checks y smoke tests

Despues de iniciar o desplegar:

```bash
npm run status
docker ps
curl -fsS http://127.0.0.1:54321/rest/v1/ >/dev/null
```

Validar funcionalmente:

1. Login email/password.
2. Lectura de perfil.
3. Listado de organizaciones/proyectos del usuario.
4. Lectura de columnas, epicas, tareas y sprints.
5. Crear y modificar una tarea de prueba en un proyecto de prueba.
6. Recepcion de Realtime/notificacion si aplica.
7. Subida y borrado de una imagen de prueba.
8. Una llamada CLI con el mismo usuario.
9. Worker con cola vacia.

Nunca usar una organizacion personal para pruebas destructivas de despliegue.

## 16. Observabilidad

Fuentes actuales:

- logs de contenedores Docker;
- logs del runtime de Edge Functions;
- `command_jobs.last_error` y estados;
- `automation_runs`;
- `activity_events`;
- Mailpit en local;
- Studio para inspeccion controlada.

Comandos utiles:

```bash
npx supabase status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker logs --tail 200 <container-name>
```

No compartir logs sin revisar tokens, emails, payloads y URLs privadas.

## 17. Diagnostico frecuente

### Docker API no disponible

Sintoma: Supabase CLI no puede conectar al daemon. Solucion: iniciar Docker y verificar `docker version`. En Windows esto suele indicar Docker Desktop detenido; en Linux, revisar el servicio `docker`.

### `functions:serve` no encuentra `.env`

Crear `.env` desde `.env.example`, completar valores de `supabase status` y ejecutar desde la raiz del repo.

### Login invalido

Verificar que el usuario exista en esa instancia concreta. Un usuario creado en cloud o Raspberry no existe automaticamente en el stack local.

### Proveedor no habilitado

El cliente intento OAuth/telefono cuando la instancia solo tiene email/password. Usar el flujo configurado o habilitar el proveedor deliberadamente.

### El frontend sigue llamando otra URL

Detener y reiniciar Vite; inspeccionar `VITE_SUPABASE_URL`; limpiar service worker/cache si existe; comprobar en Network la URL final.

### Timeout al hacer `db push`

Comprobar URL, DNS/ruta, firewall, puerto, password y TLS. No sustituir la URL por otra base sin verificar el destino. Hacer backup antes de reintentar una operacion que pudo aplicarse parcialmente.

### Roadmap o vista vacia

Revisar primero el error de red/RLS en consola. Una consulta secundaria fallida, por ejemplo dependencias, puede abortar la carga aunque epicas existan. Confirmar membresia y policies en la instancia usada.

## 18. Detener y desinstalar localmente

Conservar datos locales respaldados por Supabase CLI:

```bash
npm run stop
```

Eliminar tambien estado local del stack:

```bash
npx supabase stop --no-backup
```

Eliminar dependencias sin borrar codigo:

```bash
rm -rf node_modules
rm -rf supabase/.temp
```

`package-lock.json` debe conservarse normalmente para instalaciones reproducibles. Solo regenerarlo cuando se actualizan dependencias de forma deliberada.

## 19. Checklist de release

### Antes

- [ ] Worktree limpio o cambios entendidos.
- [ ] Migraciones nuevas revisadas.
- [ ] `db reset` exitoso en local desechable.
- [ ] Edge Functions probadas localmente.
- [ ] Casos RLS multi-tenant probados.
- [ ] Backup de la Raspberry completado y verificable.
- [ ] Commit desplegable identificado.
- [ ] Plan de rollback escrito.

### Durante

- [ ] `git pull --ff-only` sin cambios inesperados.
- [ ] Dependencias instaladas con lockfile.
- [ ] Destino de DB confirmado antes de aplicar SQL.
- [ ] Migraciones aplicadas una sola vez.
- [ ] Funciones recargadas.
- [ ] Logs observados.

### Despues

- [ ] Login exitoso.
- [ ] Datos personales intactos.
- [ ] Organizaciones/proyectos correctos.
- [ ] Tareas, epicas, sprints y reportes accesibles.
- [ ] Storage accesible.
- [ ] Jobs sin crecimiento anormal de errores.
- [ ] Version/commit desplegado registrado.

## 20. Acciones prohibidas sobre la instancia personal

- `npx supabase db reset`
- `npx supabase stop --no-backup` sin entender el almacenamiento usado
- borrar volumenes Docker manualmente
- importar un baseline encima de tablas existentes
- ejecutar dumps con `--clean` sin plan de restauracion
- editar migraciones ya aplicadas para forzar estado
- poner service role en frontend
- copiar `.env`, dumps o Storage al repositorio
- probar cascadas destructivas con organizaciones reales

Ante duda sobre el destino de una orden, detenerse y ejecutar primero comandos de solo lectura: `pwd`, `git status`, `npx supabase status`, inspeccion de variables sin imprimir secretos y consultas de metadatos.
