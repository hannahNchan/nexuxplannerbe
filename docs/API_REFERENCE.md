# NexusPlanner Backend API Reference

Ultima revision: 2026-09-26

## 1. Alcance

Esta referencia describe la superficie HTTP versionada en `supabase/functions` y su contrato con los RPCs PostgreSQL. Para el CLI consultar `docs/cli/README.md`; para reglas de negocio y permisos consultar `ARCHITECTURE.md`, `DATA_MODEL.md` y `SECURITY.md`.

Base local:

```text
http://127.0.0.1:54321
```

Rutas:

- Data API: `/rest/v1`
- Edge Functions: `/functions/v1`
- Auth: `/auth/v1`
- Storage: `/storage/v1`

## 2. Convenciones

Todas las funciones aceptan `POST` y preflight `OPTIONS`. Otros metodos responden `405`.

Headers de commands de usuario:

```http
Authorization: Bearer <user-access-token>
apikey: <publishable-key>
Content-Type: application/json
```

El body comun es:

```json
{
  "action": "command_name",
  "payload": {
    "p_parameter": "value"
  }
}
```

Los nombres en `payload` son los parametros SQL exactos y usan prefijo `p_`. Una respuesta exitosa usa:

```json
{ "data": {} }
```

Los errores usan normalmente:

```json
{ "error": "message" }
```

`workspace-commands` tambien devuelve `details` del error Supabase. Los consumidores no deben depender de que todas las funciones tengan exactamente el mismo objeto de error.

## 3. Data API

Las lecturas ordinarias se hacen con PostgREST:

```http
GET /rest/v1/tasks?select=*&project_id=eq.<uuid>
```

Headers:

```http
apikey: <publishable-key>
Authorization: Bearer <user-access-token>
```

RLS determina las filas visibles. Usar Data API para filtros, joins, orden y paginacion; usar commands para mutaciones que deban conservar invariantes o crear efectos secundarios.

El limite local configurado es 1,000 filas. Toda lista potencialmente grande debe paginarse con `Range` o limites explicitos.

## 4. `workspace-commands`

Endpoint:

```text
POST /functions/v1/workspace-commands
```

### Crear organizacion

```json
{
  "action": "create_organization",
  "payload": {
    "p_name": "Engineering",
    "p_logo_url": null
  }
}
```

El command crea organizacion, owner, actividad y job. Devuelve JSON con la identidad creada.

### Crear proyecto

```json
{
  "action": "create_project",
  "payload": {
    "p_title": "NexusPlanner",
    "p_description": "Planning workspace",
    "p_project_key": "NEXUS",
    "p_organization_id": "<uuid>",
    "p_tags": ["product", "engineering"],
    "p_visibility": "organization"
  }
}
```

`p_visibility` admite `organization` o `private`. El command crea owner, tags y columnas iniciales; no reemplazarlo por un insert directo.

### Invitaciones de organizacion

| Action | Payload |
| --- | --- |
| `create_organization_invitation` | `p_organization_id`, `p_email` |
| `create_organization_invitation_for_user` | `p_organization_id`, `p_invitee_id` |
| `accept_organization_invitation` | `p_invitation_id` |
| `decline_organization_invitation` | `p_invitation_id` |

La variante por email resuelve un usuario existente. El repositorio no implementa aun provision automatica de una cuenta externa por email.

### Miembros de organizacion

| Action | Payload |
| --- | --- |
| `update_organization_member_role` | `p_organization_id`, `p_member_id`, `p_role` |
| `remove_organization_member` | `p_organization_id`, `p_member_id` |

Roles: `owner`, `admin`, `member`. El command evita dejar la organizacion sin owner.

### Eliminar organizacion

```json
{
  "action": "delete_organization",
  "payload": { "p_organization_id": "<uuid>" }
}
```

Solo owner. Encola metadata de limpieza de Storage y elimina la organizacion con cascadas relacionales. El worker actual no reconoce el job `activity.organization_deleted`, por lo que los objetos de Storage no deben considerarse limpiados automaticamente.

### Miembros e invitaciones de proyecto

| Action | Payload |
| --- | --- |
| `add_project_member` | `p_project_id`, `p_user_id`, `p_role` |
| `remove_project_member` | `p_project_id`, `p_member_id` |
| `create_project_invitation` | `p_project_id`, `p_invitee_id` |
| `accept_project_invitation` | `p_invitation_id` |
| `decline_project_invitation` | `p_invitation_id` |

Roles de proyecto: `owner`, `member`. El usuario debe pertenecer a la organizacion antes de agregarse al proyecto.

## 5. Tablero por scope

### `board-view`

Endpoint:

```text
POST /functions/v1/board-view
```

Request:

```json
{
  "projectId": "<uuid>"
}
```

El endpoint requiere JWT y llama `get_project_board_view`. El RPC devuelve proyecto, preferencia solicitada, scope efectivo, scopes disponibles, sprint activo, capacidades, columna inicial, orden, columnas y tareas.

Reglas de lectura:

- `kanban`: tareas del proyecto con `in_backlog = false`, columna asignada y `sprint_id IS NULL`.
- `sprint`: las mismas condiciones, pero con `sprint_id` igual al sprint activo.
- Sin preferencia guardada, un proyecto con sprint activo conserva `sprint`; sin sprint activo usa `kanban`.
- Si se guardo `sprint` y no existe sprint activo, el scope efectivo es `kanban`.
- El frontend no debe volver a filtrar las tareas recibidas.

### `board-commands`

Endpoint:

```text
POST /functions/v1/board-commands
```

Guardar Kanban:

```json
{
  "action": "set_scope",
  "payload": {
    "p_project_id": "<uuid>",
    "p_scope": "kanban"
  }
}
```

`p_scope` admite `kanban` o `sprint`. Seleccionar `sprint` sin sprint activo es rechazado. La respuesta contiene el read model actualizado, no solo la fila de preferencia.

Mover una tarea al Kanban continuo:

```json
{
  "action": "move_task_to_kanban",
  "payload": {
    "p_project_id": "<uuid>",
    "p_task_id": "<uuid>",
    "p_column_id": "<uuid-or-null>",
    "p_position": 2
  }
}
```

Mover una tarea a un sprint activo o planificado:

```json
{
  "action": "move_task_to_sprint",
  "payload": {
    "p_project_id": "<uuid>",
    "p_task_id": "<uuid>",
    "p_sprint_id": "<uuid>",
    "p_column_id": "<uuid-or-null>",
    "p_position": 0
  }
}
```

Devolver una tarea al backlog:

```json
{
  "action": "move_task_to_backlog",
  "payload": {
    "p_project_id": "<uuid>",
    "p_task_id": "<uuid>",
    "p_position": null
  }
}
```

Si se omite `p_column_id`, el backend usa la primera columna del proyecto. Si se omite `p_position`, agrega la tarea al final del destino. El backend valida proyecto, columna, sprint y permisos, y normaliza `in_backlog`, `column_id` y `sprint_id` como una sola transicion.

## 6. `task-commands`

Endpoint:

```text
POST /functions/v1/task-commands
```

### Crear tarea

```json
{
  "action": "create_task",
  "payload": {
    "p_project_id": "<uuid>",
    "p_title": "Implement report filters",
    "p_subtitle": "Header controls",
    "p_description": "Acceptance criteria and implementation notes",
    "p_destination": "backlog",
    "p_column_id": null,
    "p_sprint_id": null,
    "p_position": 0,
    "p_issue_type_id": "<uuid-or-null>",
    "p_priority_id": "<uuid-or-null>",
    "p_story_points": "5",
    "p_assignee_id": "<uuid-or-null>",
    "p_epic_id": "<uuid-or-null>",
    "p_github_link": null
  }
}
```

`p_destination` admite `backlog`, `kanban` o `sprint`. `scrum` permanece como alias compatible: con `p_sprint_id` equivale a `sprint`, sin el equivale a `kanban`. Si se envia una columna, sprint, epica o responsable, todos deben pertenecer o ser validos para el proyecto.

### Asignar o desasignar

```json
{
  "action": "assign_task",
  "payload": {
    "p_project_id": "<uuid>",
    "p_task_id": "<uuid>",
    "p_assignee_id": "<member-uuid-or-null>"
  }
}
```

`null` desasigna. El command registra evento y puede generar notificacion.

### Mover entre columnas

```json
{
  "action": "move_task_column",
  "payload": {
    "p_project_id": "<uuid>",
    "p_task_id": "<uuid>",
    "p_column_id": "<uuid>",
    "p_position": 3
  }
}
```

Este command conserva el scope actual de una tarea ya ubicada en Kanban o sprint. Rechaza tareas que aun estan en backlog; para sacarlas se debe usar `board-commands` con un destino explicito.

La columna debe pertenecer al mismo proyecto. `p_position` puede omitirse para usar la logica por defecto del command.

### Programar fechas

```json
{
  "action": "schedule_task",
  "payload": {
    "p_project_id": "<uuid>",
    "p_task_id": "<uuid>",
    "p_planned_start_date": "2026-10-05",
    "p_planned_end_date": "2026-10-08"
  }
}
```

Fechas en formato `YYYY-MM-DD`. Si final se omite, se iguala al inicio. Si ambas son `null`, la tarea queda sin programar. El final no puede ser anterior al inicio.

## 7. `epic-commands`

Endpoint:

```text
POST /functions/v1/epic-commands
```

```json
{
  "action": "create_epic",
  "payload": {
    "p_project_id": "<uuid>",
    "p_name": "Reporting",
    "p_color": "#3B82F6",
    "p_owner_id": "<project-member-uuid-or-null>",
    "p_phase_id": "<phase-uuid-or-null>",
    "p_estimated_effort": "13",
    "p_start_date": "2026-10-01",
    "p_end_date": "2026-10-31"
  }
}
```

El command genera `epic_id_display`, valida owner/fase/fechas y registra actividad. La fecha de la epica no se deriva automaticamente de sus tareas.

## 8. `sprint-commands`

Endpoint:

```text
POST /functions/v1/sprint-commands
```

### Crear sprint

```json
{
  "action": "create_sprint",
  "payload": {
    "p_project_id": "<uuid>",
    "p_name": "Sprint 12",
    "p_goal": "Close reporting MVP",
    "p_start_date": "2026-10-01T09:00:00.000Z",
    "p_duration": "15d",
    "p_status": "future"
  }
}
```

Duraciones: `7d`, `15d`, `1m`. Estado inicial: `future` o `active`. Solo puede existir un sprint activo por proyecto.

### Completar sprint

```json
{
  "action": "complete_sprint",
  "payload": {
    "p_project_id": "<uuid>",
    "p_sprint_id": "<uuid>",
    "p_dispositions": [
      {
        "taskId": "<incomplete-task-uuid>",
        "destination": "backlog"
      },
      {
        "taskId": "<another-task-uuid>",
        "destination": "sprint",
        "sprintId": "<future-sprint-uuid>"
      },
      {
        "taskId": "<third-task-uuid>",
        "destination": "kanban"
      }
    ]
  }
}
```

Debe existir exactamente una disposicion por cada tarea incompleta. Los destinos son `backlog`, `kanban` o un `sprint` futuro del mismo proyecto. El command genera el reporte antes de moverlas, cierra el sprint y cambia a Kanban las preferencias de tablero que hayan quedado apuntando al sprint cerrado.

## 9. `notification-commands`

Endpoint:

```text
POST /functions/v1/notification-commands
```

```json
{
  "action": "mark_all_read",
  "payload": {}
}
```

Devuelve en `data` el numero de notificaciones actualizadas. La UI puede etiquetar la accion como "Borrar todo", pero la operacion conserva filas y establece `read_at`.

## 10. `agent-commands`

Endpoint:

```text
POST /functions/v1/agent-commands
```

### Validar plan

```json
{
  "action": "validate_plan",
  "payload": { "plan": {} }
}
```

Devuelve:

```json
{
  "data": {
    "ok": false,
    "errors": [],
    "warnings": [],
    "operations": {
      "organizations": 0,
      "projects": 0,
      "epics": 0,
      "sprints": 0,
      "tasks": 0,
      "scheduledTasks": 0
    }
  }
}
```

El handler no exige Authorization para esta rama, pero el gateway puede exigir JWT segun despliegue.

### Aplicar plan

```json
{
  "action": "apply_plan",
  "payload": {
    "dry_run": false,
    "plan": {
      "organization": { "name": "Engineering" },
      "projects": []
    }
  }
}
```

Requiere JWT. `dry_run: true` solo valida. El contrato completo y ejemplo viven en `docs/cli/AGENT_PLANS.md` y `packages/cli/examples/agent-plan.example.json`.

Aliases aceptados por el parser:

- Proyecto: `title` o `name`; `project_key` o `key`.
- Epica: `name` o `title`; fechas `start_date`/`end_date` o `start`/`end`.
- Tarea: `title` o `name`; puntos `story_points` o `points`.
- Fechas de tarea: `planned_start_date`, `start_date` o `start`; final equivalente.
- Referencias: `ref`, `key` o `id`.

El plan no es transaccional de punta a punta. Organizaciones/proyectos creados antes de un fallo permanecen.

## 11. `job-worker`

Endpoint:

```text
POST /functions/v1/job-worker
```

Headers:

```http
x-job-worker-secret: <JOB_WORKER_SECRET>
Content-Type: application/json
```

No usa JWT de usuario. Body:

```json
{
  "queueName": "nexusplanner-events",
  "limit": 10,
  "workerId": "scheduler-instance-1"
}
```

Todos los campos son opcionales. `limit` queda entre 1 y 50. El worker resetea jobs estancados por mas de 300 segundos, reclama con lock, ejecuta y marca `done`/`failed`.

Respuesta:

```json
{
  "workerId": "scheduler-instance-1",
  "queueName": "nexusplanner-events",
  "processed": 1,
  "results": [
    { "id": "<uuid>", "jobType": "activity.task_created", "status": "done" }
  ]
}
```

El worker actual solo valida tipos y tiene adaptadores incompletos. Consultar `ARCHITECTURE.md` antes de asumir entrega externa.

## 12. Lecturas frecuentes

Ejemplos conceptuales de PostgREST:

```http
GET /rest/v1/organizations?select=*&order=created_at.asc
GET /rest/v1/projects?select=*&organization_id=eq.<uuid>&order=created_at.asc
GET /rest/v1/epics?select=*,epic_phases(*)&project_id=eq.<uuid>
GET /rest/v1/tasks?select=*,columns(*),priorities(*),epics(*)&project_id=eq.<uuid>
GET /rest/v1/sprints?select=*&project_id=eq.<uuid>&order=start_date.asc
GET /rest/v1/sprint_reports?select=*&project_id=eq.<uuid>&order=generated_at.desc
GET /rest/v1/user_notifications?select=*&order=created_at.desc
```

Estas consultas estan sujetas a relaciones expuestas por PostgREST y RLS efectivo. No usar service role para hacerlas desde frontend.

## 13. Codigos de estado

| Codigo | Significado habitual |
| --- | --- |
| `200` | Command ejecutado o validacion completada |
| `400` | Action/payload invalido, regla SQL o permiso de dominio rechazado |
| `401` | Falta Authorization o secreto de worker invalido |
| `405` | Metodo no permitido |
| `500` | Variables backend ausentes o fallo interno del worker |

Varios errores de permisos lanzados por RPC aparecen como `400`, no `403`. Los clientes deben mostrar el mensaje de dominio y no inferir autorizacion solo por status HTTP.

## 14. Agregar una accion nueva

1. Crear primero el command SQL con autorizacion e invariantes.
2. Revocar `PUBLIC` y conceder `EXECUTE` al rol correcto.
3. Agregar action y mapping en la Edge Function correspondiente.
4. Propagar JWT de usuario; no usar service role.
5. Agregar CLI/frontend si aplica.
6. Probar usuario autorizado, no miembro y otro tenant.
7. Documentar payload, respuesta y efectos secundarios aqui.

Una accion HTTP no debe implementar por segunda vez reglas ya presentes en SQL. La Edge Function es adaptador; el command es la frontera transaccional.
