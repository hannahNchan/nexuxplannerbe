# NexusPlanner Backend Agent Entry Point

Última revisión: 2026-09-26

Este repositorio es la distribución backend reproducible de NexusPlanner. Contiene el schema PostgreSQL, RLS, funciones SQL/RPC, triggers, Edge Functions, buckets de Storage, catálogos seed y el CLI opcional. No contiene datos personales ni es un volcado de producción.

## Lectura Obligatoria

Antes de cambiar comportamiento:

1. Lee `AGENTS.md`.
2. Lee `docs/ARCHITECTURE.md` para entender fronteras y flujos.
3. Lee `docs/API_REFERENCE.md` si el cambio toca contratos HTTP, payloads o respuestas.
4. Lee `docs/DATA_MODEL.md` si el cambio toca tablas, relaciones o lifecycle.
5. Lee `docs/SECURITY.md` si toca Auth, RLS, grants, RPCs, Storage, secretos o Edge Functions.
6. Lee `docs/OPERATIONS.md` si toca setup, migraciones, deploy, worker, backup o Raspberry Pi.
7. Lee la migración y función completas antes de editarlas.

## Fuente De Verdad

- `supabase/migrations/00000000000000_baseline_schema.sql`: baseline de schema sin datos.
- Migraciones posteriores: cambios incrementales que siempre ganan sobre el baseline.
- `supabase/functions/`: wrappers HTTP y worker.
- `supabase/config.toml`: configuración del stack local.
- `supabase/seed.sql`: únicamente catálogos globales.
- `packages/cli/src/index.mjs`: comportamiento real del CLI.

## Invariantes

- Nunca agregues datos reales, dumps, tokens, passwords o service-role keys al repo.
- No edites el baseline para una feature nueva. Crea una migración con `npx supabase migration new <name>`.
- No pongas organizaciones, usuarios, proyectos, sprints, épicas o tareas en `seed.sql`.
- Toda operación crítica debe pasar por un command SQL/RPC y validar `auth.uid()` más permisos de organización/proyecto.
- Una Edge Function con JWT de usuario debe propagar ese token; no debe convertir una operación de usuario en service role.
- Solo el worker puede usar `SUPABASE_SERVICE_ROLE_KEY`.
- Funciones `SECURITY DEFINER` deben fijar `search_path`, validar identidad y tener grants explícitos.
- Un proyecto solo puede tener un sprint activo.
- Las dependencias no pueden cruzar proyectos ni crear ciclos.
- Completar sprint genera el snapshot histórico antes de mover tareas incompletas.
- Eventos, notificaciones y jobs se crean server-side.
- Un cambio de schema se verifica desde una base limpia con `npx supabase db reset` cuando Docker esté disponible.

## Riesgos Verificados Que No Deben Ignorarse

- El baseline no habilita RLS en `epics` ni en los catálogos, aunque el dump concede privilegios de tabla a roles Data API. Consulta `docs/SECURITY.md` antes de ampliar exposición.
- `task-images` permite administrar objetos a cualquier usuario autenticado, sin scope de proyecto o propietario.
- No hay schedules `pg_cron` versionados, aunque existen funciones de mantenimiento y deadlines.
- `job-worker` reconoce jobs cuyos adaptadores externos todavía son no-op.
- `activity.organization_deleted` no figura entre los tipos conocidos del worker actual.
- `agent apply-plan` no es una transacción global; puede aplicar parcialmente un plan.

No corrijas estas deudas como efecto colateral de otra tarea. Trátalas como cambios de seguridad/operación separados, con migración y verificación.

## Verificación

Para documentación solamente, usa `git diff --check` y valida que todas las rutas citadas existan. Para código o SQL:

```bash
npm install
npx supabase db reset
npx supabase functions serve --env-file .env
npm run cli -- help
```

No ejecutes `db reset` contra una instancia con datos personales. El comando está pensado para el stack local efímero administrado por este checkout.
