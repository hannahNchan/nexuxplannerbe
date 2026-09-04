# NexusPlanner CLI

Este documento describe el cliente de linea de comandos de NexusPlanner como contrato tecnico para agentes, scripts y operadores. La implementacion vive en `packages/cli/src/index.mjs`; el comando npm que lo ejecuta esta declarado como `cli` en `package.json`.

El CLI no es un segundo backend. Las lecturas usan Supabase REST con JWT y RLS, y las mutaciones criticas pasan por Supabase Edge Functions que a su vez llaman RPCs SQL transaccionales. Esta frontera evita que agentes externos repliquen reglas de negocio en el cliente.

## Ubicacion

```text
packages/cli/
  README.md
  examples/
    agent-plan.example.json
  package.json
  src/
    index.mjs
```

`packages/cli/README.md` es una guia corta de uso. Este archivo es la referencia completa. `docs/cli/AGENT_PLANS.md` documenta el formato que consumen `agent validate-plan` y `agent apply-plan`.

## Ejecucion

Desde la raiz del repo:

```bash
npm run cli -- help
```

La forma general es:

```bash
npm run cli -- <dominio> <accion> [argumentos] [--flags]
```

El CLI esta escrito como script Node ESM sin dependencias internas adicionales. Usa `fetch`, por lo que requiere una version moderna de Node compatible con el runtime del proyecto.

## Configuracion

El CLI arma su runtime desde tres fuentes. La prioridad real, de mayor a menor, es:

1. Variables de entorno `NEXUS_*`.
2. Variables publicas del proyecto en `.env.local` o `.env`.
3. Archivo persistente del usuario en `~/.nexusplanner/config.json`.

La configuracion persistente se escribe con:

```bash
npm run cli -- config set url http://127.0.0.1:54321
npm run cli -- config set anon-key <publishable-or-anon-key>
npm run cli -- config set token <user-access-token>
npm run cli -- config set org <organization-id>
npm run cli -- config set project <project-id>
```

Se puede inspeccionar sin imprimir secretos completos:

```bash
npm run cli -- config get
npm run cli -- auth status
```

Variables soportadas:

```bash
NEXUS_API_URL=
NEXUS_PUBLISHABLE_KEY=
NEXUS_ACCESS_TOKEN=
NEXUS_ORGANIZATION_ID=
NEXUS_PROJECT_ID=
```

Variables leidas desde `.env.local` y `.env`:

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY=
VITE_SUPABASE_ANON_KEY=
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
```

El token de usuario no se obtiene todavia por login interactivo. Para escrituras o lecturas protegidas se debe configurar `NEXUS_ACCESS_TOKEN` o guardar el token con `config set token`.

## Salida

La salida normal es JSON formateado con dos espacios. Los comandos que devuelven texto simple, como `auth token`, imprimen texto plano.

Los errores salen por `stderr` y terminan el proceso con codigo distinto de cero. Si una Edge Function responde texto no JSON, el CLI lo convierte en un mensaje legible en vez de romper con un error de parseo.

Ejemplo de funcion no desplegada:

```text
404 Function not found
```

## Frontera Backend

El CLI debe conservar esta regla: no escribir directo a tablas para operaciones criticas. Las mutaciones entran por Edge Functions y los permisos/reglas viven en RPCs SQL.

Mapeo actual:

| CLI | Edge Function | Accion | RPC/efecto |
| --- | --- | --- | --- |
| `org create` | `workspace-commands` | `create_organization` | `create_organization_command` |
| `org delete` | `workspace-commands` | `delete_organization` | `delete_organization_command` |
| `project create` | `workspace-commands` | `create_project` | `create_project_command` |
| `epic create` | `epic-commands` | `create_epic` | `create_epic_command` |
| `task create` | `task-commands` | `create_task` | `create_task_command` |
| `task assign` | `task-commands` | `assign_task` | `assign_task_command` |
| `task unassign` | `task-commands` | `assign_task` | `assign_task_command` con assignee nulo |
| `task move` | `task-commands` | `move_task_column` | `move_task_column_command` |
| `task schedule` | `task-commands` | `schedule_task` | `schedule_task_command` |
| `board move-task` | `task-commands` | `move_task_column` | delega en `task move` |
| `sprint create` | `sprint-commands` | `create_sprint` | `create_sprint_command` |
| `sprint complete` | `sprint-commands` | `complete_sprint` | `complete_sprint_command` |
| `notifications clear` | `notification-commands` | `mark_all_read` | `mark_all_notifications_read_command` |
| `agent validate-plan` | `agent-commands` | `validate_plan` | valida JSON sin mutar |
| `agent apply-plan` | `agent-commands` | `apply_plan` | orquesta commands server-side |

Las lecturas actuales usan REST directo con JWT:

| CLI | REST |
| --- | --- |
| `org list` | `GET /rest/v1/organizations?select=*&order=created_at.desc` |
| `project list` | `GET /rest/v1/projects?select=*&order=created_at.desc` con filtro opcional por `organization_id` |
| `epic list` | `GET /rest/v1/epics?select=*&project_id=eq.<id>&order=created_at.asc` |
| `task list` | `GET /rest/v1/tasks?select=*&project_id=eq.<id>&order=created_at.desc` |
| `sprint list` | `GET /rest/v1/sprints?select=*&project_id=eq.<id>&order=start_date.desc` |
| `board get` | `GET /rest/v1/columns` y `GET /rest/v1/tasks` por proyecto |
| `notifications list` | `GET /rest/v1/user_notifications` no leidas |
| `notifications read` | `PATCH /rest/v1/user_notifications?id=eq.<id>` |
| `activity list` | `GET /rest/v1/activity_events` con filtros opcionales |

## Comandos

### Auth

```bash
npm run cli -- auth status
npm run cli -- auth token
```

`auth status` muestra URL, presencia de key, presencia de token y IDs activos de organizacion/proyecto. No valida el token contra Supabase; solo inspecciona configuracion local.

`auth token` imprime el token configurado o una cadena vacia.

### Config

```bash
npm run cli -- config get
npm run cli -- config set url <supabase-url>
npm run cli -- config set anon-key <publishable-or-anon-key>
npm run cli -- config set token <user-access-token>
npm run cli -- config set org <organization-id>
npm run cli -- config set project <project-id>
```

Alias internos:

```text
url      -> apiUrl
anon-key -> anonKey
token    -> accessToken
org      -> organizationId
project  -> projectId
```

### Organizaciones

```bash
npm run cli -- org list
npm run cli -- org create "Nombre de organizacion" --logo-url https://example.com/logo.png
npm run cli -- org delete <organization-id>
npm run cli -- org switch <organization-id>
```

`org switch` solo cambia el ID persistido en `~/.nexusplanner/config.json`; no llama al backend.

### Proyectos

```bash
npm run cli -- project list
npm run cli -- project list --org <organization-id>
npm run cli -- project create "Nombre del proyecto" --key KEY --org <organization-id> --description "Texto"
npm run cli -- project switch <project-id>
```

`project create` usa `--org` o el proyecto activo configurado con `config set org`. `--visibility` se acepta y por default manda `organization`.

`project switch` solo cambia el ID persistido localmente.

### Epicas

```bash
npm run cli -- epic list --project <project-id>
npm run cli -- epic create "Nombre de epica" --project <project-id> --color "#3B82F6" --owner <user-id> --phase <phase-id> --effort L --start 2026-09-01 --end 2026-09-30
```

`epic create` delega en `create_epic_command`, que genera el ID visible de epica en backend y registra actividad/outbox.

### Tareas

```bash
npm run cli -- task list --project <project-id>
npm run cli -- task create "Titulo" --project <project-id> --destination backlog
npm run cli -- task create "Titulo" --project <project-id> --destination scrum --sprint <sprint-id> --column <column-id>
npm run cli -- task assign <task-id> <user-id> --project <project-id>
npm run cli -- task unassign <task-id> --project <project-id>
npm run cli -- task move <task-id> --column <column-id> --position 0 --project <project-id>
npm run cli -- task schedule <task-id> --start 2026-09-02 --end 2026-09-05 --project <project-id>
```

Flags de `task create`:

```text
--subtitle
--description
--destination backlog|scrum
--column <column-id>
--sprint <sprint-id>
--position <number>
--type <issue-type-id>
--priority <priority-id>
--points <story-points>
--assignee <user-id>
--epic <epic-id>
--github <url>
```

`task schedule` persiste `planned_start_date` y `planned_end_date`. Si `--end` se omite, el CLI manda la misma fecha de inicio como fin. Estas fechas alimentan calendario y timeline del tablero.

### Sprints

```bash
npm run cli -- sprint list --project <project-id>
npm run cli -- sprint create "Sprint 1" --project <project-id> --duration 7d --start 2026-09-01T09:00:00.000Z --status future --goal "Objetivo"
npm run cli -- sprint complete <sprint-id> --project <project-id> --dispositions '[{"taskId":"...","destination":"backlog"}]'
```

Duraciones permitidas por backend:

```text
7d
15d
1m
```

`sprint complete` requiere un JSON array para tareas incompletas. Cada elemento debe mapear una tarea incompleta a backlog o a otro sprint, siguiendo la regla de cierre detallado por tarea.

### Board

```bash
npm run cli -- board get --project <project-id>
npm run cli -- board move-task <task-id> --column <column-id> --position 0 --project <project-id>
```

`board get` devuelve columnas y tareas del proyecto. Es una lectura para agentes; no reconstruye layout del frontend.

### Notificaciones

```bash
npm run cli -- notifications list
npm run cli -- notifications read <notification-id>
npm run cli -- notifications clear
```

`notifications clear` marca todas las notificaciones no leidas del usuario como leidas mediante backend command.

### Actividad

```bash
npm run cli -- activity list
npm run cli -- activity list --project <project-id>
npm run cli -- activity list --org <organization-id>
```

Sin filtros usa los IDs activos configurados. Si no hay IDs activos, hace una consulta amplia que queda limitada por RLS.

### Agent

```bash
npm run cli -- agent validate-plan ./packages/cli/examples/agent-plan.example.json
npm run cli -- agent apply-plan ./packages/cli/examples/agent-plan.example.json --dry-run
npm run cli -- agent apply-plan ./packages/cli/examples/agent-plan.example.json
```

`validate-plan` solo necesita URL y publishable key porque no muta. `apply-plan` requiere token de usuario porque crea o enlaza entidades usando permisos reales. El formato completo esta en `docs/cli/AGENT_PLANS.md`.

## Flujo Recomendado Para Agentes

Un agente que no conoce el workspace debe empezar con:

```bash
npm run cli -- auth status
npm run cli -- org list
npm run cli -- project list
```

Si ya existe una organizacion y proyecto objetivo:

```bash
npm run cli -- config set org <organization-id>
npm run cli -- config set project <project-id>
```

Para crear estructura completa:

```bash
npm run cli -- agent validate-plan ./plan.json
npm run cli -- agent apply-plan ./plan.json --dry-run
npm run cli -- agent apply-plan ./plan.json
```

Para operar tareas existentes:

```bash
npm run cli -- task list --project <project-id>
npm run cli -- board get --project <project-id>
npm run cli -- task move <task-id> --column <column-id> --project <project-id>
npm run cli -- task schedule <task-id> --start 2026-09-02 --end 2026-09-05 --project <project-id>
```

## Despliegue Requerido

El CLI depende de que las Edge Functions existan en el Supabase destino. Si una accion devuelve `404 Function not found`, el problema normal es que la funcion no fue desplegada en ese ambiente.

Para un ambiente self-hosted o remoto, primero confirma que tu terminal apunta al proyecto correcto antes de aplicar migraciones o desplegar funciones.

Despliega funciones al Supabase destino correspondiente:

```bash
npx supabase functions deploy agent-commands task-commands epic-commands sprint-commands notification-commands workspace-commands --use-api
```

Si el deploy apunta a otro proyecto por el link del repo, revisa el ambiente antes de asumir que desplego donde esperabas.

## Invariantes

El CLI no debe introducir escrituras directas a tablas para:

```text
create_task
assign_task
move_task_column
schedule_task
complete_sprint
create_project
create_organization
delete_organization
create_epic
create_sprint
mark_all_notifications_read
agent apply-plan
```

Las reglas de permisos viven en SQL y RLS. El CLI puede validar UX y forma de payload, pero no puede ser fuente de verdad para roles, visibilidad, secuencias, IDs visibles, actividad, notificaciones ni outbox.

No guardar service-role keys en `~/.nexusplanner/config.json`. Este CLI opera como usuario autenticado.

## Limitaciones

El CLI no implementa login OAuth, device flow ni refresh de tokens. El token debe configurarse externamente.

No hay soporte YAML para planes; `agent` lee JSON.

No hay paginacion configurable en lecturas de actividad/notificaciones. `activity list` y `notifications list` usan limites fijos.

No hay comandos para CRUD completo de automatizaciones, dependencias, reportes, storage o catalogos. Esos dominios existen en la app/backend, pero el CLI todavia no expone comandos dedicados.

## Mantenimiento

Cuando se agregue un comando:

1. Actualiza `commandMatrix` en `packages/cli/src/index.mjs`.
2. Agrega el handler y conserva salida JSON.
3. Si muta datos criticos, crea o reutiliza una Edge Function command wrapper.
4. Actualiza este documento y `packages/cli/README.md`.
5. Si cambia el contrato para agentes, actualiza `docs/cli/AGENT_PLANS.md`.
6. Corre `npm run check` y `npm run build`.
