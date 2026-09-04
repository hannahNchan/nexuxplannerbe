# Agent Plans

Este documento define el contrato JSON que consumen:

```bash
npm run cli -- agent validate-plan <file>
npm run cli -- agent apply-plan <file> [--dry-run]
```

El objetivo de `agent apply-plan` es que un agente externo pueda crear una estructura completa de trabajo en NexusPlanner sin conocer IDs internos de antemano. El agente declara una jerarquia `organization -> projects -> sprints/epics/tasks`; el backend crea cada entidad con commands server-side y resuelve referencias locales a IDs reales durante la ejecucion.

## Frontera De Ejecucion

El CLI manda el archivo JSON a la Edge Function `agent-commands`.

`validate_plan` valida forma, campos minimos, duraciones de sprint y orden de fechas. No muta datos y no exige token de usuario.

`apply_plan` requiere token de usuario. Ejecuta los mismos commands backend que la UI usa para crear organizaciones, proyectos, sprints, epicas, tareas y fechas de tareas. Si una regla de permisos falla, falla el command correspondiente y no debe arreglarse en el CLI.

## Forma General

```json
{
  "organization": {
    "id": "uuid existente opcional",
    "name": "Nombre cuando se crea una nueva organizacion",
    "logo_url": "https://example.com/logo.png"
  },
  "projects": [
    {
      "id": "uuid existente opcional",
      "ref": "project-ref-local",
      "title": "Nombre del proyecto",
      "project_key": "KEY",
      "description": "Descripcion opcional",
      "visibility": "organization",
      "tags": ["opcional"],
      "sprints": [],
      "epics": [],
      "tasks": []
    }
  ]
}
```

`organization.id` indica que se debe usar una organizacion existente. Si no hay `id`, se requiere `organization.name` y se crea una nueva organizacion.

`project.id` indica que se debe usar un proyecto existente. Si no hay `id`, se requiere `title` o `name`, y tambien `project_key` o `key` para crear el proyecto.

## Referencias Locales

Cada proyecto, sprint, epica o tarea puede declarar `ref`. Esa referencia solo existe dentro del plan y sirve para enlazar objetos creados en la misma ejecucion.

Ejemplo:

```json
{
  "epics": [
    { "ref": "ops", "name": "Operaciones" }
  ],
  "sprints": [
    { "ref": "sprint-1", "name": "Sprint 1", "duration": "7d" }
  ],
  "tasks": [
    {
      "title": "Crear tablero operativo",
      "epic_ref": "ops",
      "sprint_ref": "sprint-1"
    }
  ]
}
```

El backend crea primero sprints, luego epicas, luego tareas. Por eso una tarea puede apuntar a `sprint_ref` y `epic_ref` aunque todavia no existan IDs reales al inicio de la ejecucion.

Si ya conoces el ID real, usa `epic_id` o `sprint_id`. Si mandas ambos, el ID real tiene prioridad sobre la referencia local.

## Organizacion

Campos aceptados:

| Campo | Tipo | Requerido | Uso |
| --- | --- | --- | --- |
| `id` | string UUID | No | Usa organizacion existente |
| `name` | string | Si no hay `id` | Nombre para crear organizacion |
| `logo_url` | string | No | Logo inicial al crear organizacion |

Regla: debe existir `organization`. Debe traer `id` o `name`.

## Proyecto

Campos aceptados:

| Campo | Tipo | Requerido | Uso |
| --- | --- | --- | --- |
| `id` | string UUID | No | Usa proyecto existente |
| `ref` | string | No | Referencia local |
| `title` | string | Si no hay `id` | Nombre del proyecto |
| `name` | string | Alternativa a `title` | Nombre del proyecto |
| `project_key` | string | Si no hay `id` | Prefijo de IDs visibles |
| `key` | string | Alternativa a `project_key` | Prefijo de IDs visibles |
| `description` | string | No | Descripcion |
| `visibility` | string | No | Default `organization` |
| `tags` | string[] | No | Tags iniciales |
| `sprints` | array | No | Sprints del proyecto |
| `epics` | array | No | Epicas del proyecto |
| `tasks` | array | No | Tareas del proyecto |

Regla: `projects` debe existir y contener al menos un proyecto.

## Sprints

Campos aceptados:

| Campo | Tipo | Requerido | Uso |
| --- | --- | --- | --- |
| `id` | string UUID | No | Usa sprint existente |
| `ref` | string | No | Referencia local |
| `name` | string | Si no hay `id` | Nombre del sprint |
| `goal` | string | No | Objetivo |
| `start_date` | string timestamp | No | Inicio |
| `start` | string timestamp | Alternativa | Inicio |
| `duration` | string | No | Default `7d` |
| `status` | string | No | Default `future` |

Duraciones validas:

```text
7d
15d
1m
```

El backend calcula `end_date`; el plan no debe intentar imponer fechas finales arbitrarias de sprint.

Estados de creacion aceptados por command:

```text
future
active
```

Si se crea como `active` y ya existe otro sprint activo en el proyecto, el command SQL falla.

## Epicas

Campos aceptados:

| Campo | Tipo | Requerido | Uso |
| --- | --- | --- | --- |
| `id` | string UUID | No | Usa epica existente |
| `ref` | string | No | Referencia local |
| `name` | string | Si no hay `id` | Nombre |
| `title` | string | Alternativa a `name` | Nombre |
| `color` | string | No | Color de epica |
| `owner_id` | string UUID | No | Responsable |
| `phase_id` | string UUID | No | Fase |
| `estimated_effort` | string | No | Esfuerzo |
| `effort` | string | Alternativa | Esfuerzo |
| `start_date` | string date | No | Inicio roadmap |
| `start` | string date | Alternativa | Inicio roadmap |
| `end_date` | string date | No | Fin roadmap |
| `end` | string date | Alternativa | Fin roadmap |

Si `start_date` y `end_date` existen, `end_date` no puede ser anterior a `start_date`.

## Tareas

Campos aceptados:

| Campo | Tipo | Requerido | Uso |
| --- | --- | --- | --- |
| `id` | string UUID | No | Usa tarea existente para programarla |
| `ref` | string | No | Referencia local |
| `title` | string | Si no hay `id` | Titulo |
| `name` | string | Alternativa a `title` | Titulo |
| `subtitle` | string | No | Subtitulo |
| `description` | string | No | Descripcion |
| `destination` | string | No | `backlog` o `scrum` |
| `column_id` | string UUID | No | Columna del tablero |
| `sprint_id` | string UUID | No | Sprint real |
| `sprint_ref` | string | No | Sprint local |
| `position` | number | No | Orden |
| `issue_type_id` | string UUID | No | Tipo |
| `priority_id` | string UUID | No | Prioridad |
| `story_points` | string | No | Puntos |
| `points` | string | Alternativa | Puntos |
| `assignee_id` | string UUID | No | Usuario asignado |
| `epic_id` | string UUID | No | Epica real |
| `epic_ref` | string | No | Epica local |
| `github_link` | string | No | Link externo |
| `planned_start_date` | string date | No | Fecha inicial para calendario/timeline |
| `start_date` | string date | Alternativa | Fecha inicial |
| `start` | string date | Alternativa | Fecha inicial |
| `planned_end_date` | string date | No | Fecha final |
| `end_date` | string date | Alternativa | Fecha final |
| `end` | string date | Alternativa | Fecha final |

Si la tarea tiene `sprint_id` o `sprint_ref` y no trae `destination`, el backend del agente usa `scrum`. Si no tiene sprint, usa `backlog`.

Si hay fecha inicial y no hay fecha final, la fecha final se vuelve igual a la inicial. Si hay fecha final anterior a la inicial, la validacion falla.

Si hay fecha final sin fecha inicial, la validacion genera warning y el backend no programa esa tarea.

## Ejemplo Completo

```json
{
  "organization": {
    "name": "Lufthansa"
  },
  "projects": [
    {
      "ref": "aero",
      "title": "Aero Operations Console",
      "project_key": "AERO",
      "description": "Workspace de pruebas creado por agente.",
      "visibility": "organization",
      "sprints": [
        {
          "ref": "sprint-1",
          "name": "Sprint 1",
          "goal": "Validar la primera experiencia de planeacion.",
          "duration": "7d",
          "status": "future",
          "start_date": "2026-09-01T09:00:00.000Z"
        }
      ],
      "epics": [
        {
          "ref": "ops",
          "name": "Operaciones",
          "color": "#3B82F6",
          "estimated_effort": "L",
          "start_date": "2026-09-01",
          "end_date": "2026-09-30"
        }
      ],
      "tasks": [
        {
          "ref": "calendar-view",
          "title": "Disenar vista calendario",
          "subtitle": "Validar fechas y drag and drop",
          "description": "Tarea de ejemplo generada desde agent apply-plan.",
          "destination": "scrum",
          "epic_ref": "ops",
          "sprint_ref": "sprint-1",
          "story_points": "5",
          "planned_start_date": "2026-09-02",
          "planned_end_date": "2026-09-05"
        }
      ]
    }
  ]
}
```

El ejemplo versionado vive en `packages/cli/examples/agent-plan.example.json`.

## Flujo Seguro

Primero validar:

```bash
npm run cli -- agent validate-plan ./plan.json
```

Luego simular:

```bash
npm run cli -- agent apply-plan ./plan.json --dry-run
```

Luego aplicar:

```bash
npm run cli -- agent apply-plan ./plan.json
```

`--dry-run` en `apply-plan` devuelve la misma validacion sin mutar. Sirve para probar que el usuario tiene conectividad hacia la Edge Function, aunque no prueba permisos SQL porque no ejecuta los commands.

## Resultado Esperado

`apply-plan` devuelve:

```json
{
  "data": {
    "applied": true,
    "validation": {
      "ok": true,
      "errors": [],
      "warnings": [],
      "operations": {
        "organizations": 1,
        "projects": 1,
        "epics": 1,
        "sprints": 1,
        "tasks": 2,
        "scheduledTasks": 2
      }
    },
    "results": {
      "organizationId": "uuid",
      "projects": [
        {
          "id": "uuid",
          "ref": "aero",
          "epics": [],
          "sprints": [],
          "tasks": []
        }
      ]
    }
  }
}
```

Las listas `epics`, `sprints` y `tasks` contienen los registros o IDs devueltos por los commands, junto con el `ref` local resuelto.

## Errores Comunes

`404 Function not found` significa que `agent-commands` no esta desplegada en el Supabase destino.

`Missing NexusPlanner CLI config` significa que falta URL, publishable key o token segun la accion.

Errores como `No tienes permisos...` vienen de SQL commands. No se corrigen en el plan ni en el CLI salvo que el usuario realmente este apuntando a la organizacion/proyecto equivocado.

Errores de duracion de sprint se corrigen usando solo `7d`, `15d` o `1m`.

Errores de referencia local ocurren cuando una tarea usa `epic_ref` o `sprint_ref` que no existe dentro del mismo proyecto del plan.

## Invariantes Para Agentes

No inventes UUIDs. Si no existe un ID real, usa `ref` local.

No asumas que todos los usuarios de la organizacion pueden mutar proyectos. El token usado por `apply-plan` debe tener permisos reales.

No calcules `end_date` de sprint en el plan. El backend lo calcula desde `duration`.

No cambies story points como consecuencia de fechas. Los puntos son estimacion humana; calendario y timeline usan fechas.

No uses `apply-plan` como migrador masivo idempotente. El command crea entidades nuevas cuando no recibe IDs existentes. Reaplicar el mismo plan sin IDs puede crear duplicados.

No pongas secretos en el archivo del plan.

## Pendientes Del Contrato

El contrato no soporta YAML.

El contrato no soporta dependencias entre tareas o epicas.

El contrato no soporta automatizaciones, miembros, invitaciones, notas, reportes, archivos ni catalogos.

El contrato no expone modo transaccional global para todo el plan. Cada command SQL es transaccional por entidad/operacion, pero el orquestador puede haber creado entidades previas si falla una entidad posterior.
