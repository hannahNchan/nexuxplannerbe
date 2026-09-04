# NexusPlanner Backend

Backend reproducible para NexusPlanner usando Supabase local/self-hosted. Este repo contiene schema, RLS, RPC commands, Edge Functions, storage policies, seeds default y el CLI opcional para agentes.

No contiene datos personales, organizaciones, proyectos, tareas, usuarios ni dumps de produccion.

## Requisitos

- Docker Desktop, Docker Engine o un host Linux con Docker.
- Node.js 18+ si quieres usar los scripts npm o el CLI.
- Supabase CLI. Puedes usar `npx supabase ...` sin instalarlo globalmente.

## Instalacion rapida

```bash
npm install
npm run start
npm run reset
npm run status
```

`npm run start` levanta el stack local de Supabase con Docker. `npm run reset` aplica migraciones y despues ejecuta `supabase/seed.sql`.

Si no quieres usar npm:

```bash
npx supabase start
npx supabase db reset
npx supabase status
```

## Conectar el frontend

Despues de `supabase status`, copia la API URL y la publishable/anon key al `.env.local` del frontend:

```env
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY=<anon-or-publishable-key-from-status>
VITE_AUTH_REDIRECT_URL=http://localhost:5173
```

Luego en el repo frontend:

```bash
npm install
npm run dev
```

## Que se crea

- Schema publico completo de NexusPlanner desde `supabase/migrations/00000000000000_baseline_schema.sql`.
- Migraciones posteriores para comandos de organizacion, CLI/agente y colores de badges.
- Edge Functions:
  - `agent-commands`
  - `epic-commands`
  - `job-worker`
  - `notification-commands`
  - `sprint-commands`
  - `task-commands`
  - `workspace-commands`
- Buckets vacios:
  - `project-assets`
  - `avatars`
  - `task-images`
- Catalogos default:
  - tipos de issue
  - prioridades
  - fases de epica
  - sistema Fibonacci de story points

## Que NO se crea

- Usuarios de Auth.
- Organizaciones reales.
- Proyectos reales.
- Epicas, tareas, sprints o reportes reales.
- Objetos de storage.
- Secrets productivos.

## Edge Functions locales

Para servir functions localmente:

```bash
cp .env.example .env
npm run functions:serve
```

Para invocar `job-worker` necesitas definir `JOB_WORKER_SECRET` y enviar el header `x-job-worker-secret`.

## CLI opcional

El CLI vive en `packages/cli` y puede usarse contra este backend local:

```bash
npm run cli -- help
npm run cli -- auth status
```

Para operaciones autenticadas, inicia sesion desde el frontend o usa un token valido:

```bash
npm run cli -- config set url http://127.0.0.1:54321
npm run cli -- config set anon-key <anon-or-publishable-key>
npm run cli -- config set token <user-access-token>
```

El CLI tambien lee `~/.nexusplanner/config.json`. Si vienes de otro ambiente, revisa `npm run cli -- config get` antes de mutar datos para confirmar que `org` y `project` apuntan al backend correcto.

La documentacion del CLI esta en `docs/cli/README.md` y el contrato de planes de agentes en `docs/cli/AGENT_PLANS.md`.

## Por que no hay docker-compose.yml propio todavia

Supabase CLI ya genera y controla el compose interno para Postgres, Auth, REST, Realtime, Storage, Studio y Edge Runtime. Mantener un compose manual ahora duplicaria trabajo y seria mas facil de romper con cambios de Supabase.

Cuando el backend este estable en Raspberry o servidor propio, el siguiente paso sera crear una variante self-hosted con `docker-compose.yml`, healthchecks, backups y secrets de produccion.
