# NexusPlanner CLI

Cliente de línea de comandos para operar NexusPlanner desde agentes, scripts o terminal humana.

El CLI no escribe directo a la base de datos para operaciones críticas. Las mutaciones usan Edge Functions o comandos backend; las lecturas usan Supabase REST con JWT y RLS.

Documentación completa:

- `docs/cli/README.md`: arquitectura, configuración, comandos, frontera backend y despliegue.
- `docs/cli/AGENT_PLANS.md`: contrato JSON para `agent validate-plan` y `agent apply-plan`.

## Configuración

```bash
npm run cli -- config set url http://127.0.0.1:54321
npm run cli -- config set anon-key <publishable-or-anon-key>
npm run cli -- config set token <user-access-token>
npm run cli -- config set org <organization-id>
npm run cli -- config set project <project-id>
```

También puede leer:

```bash
NEXUS_API_URL=
NEXUS_PUBLISHABLE_KEY=
NEXUS_ACCESS_TOKEN=
NEXUS_ORGANIZATION_ID=
NEXUS_PROJECT_ID=
```

Cuando se ejecuta desde la raíz del repo, también usa `.env.local` y `.env` para `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY`, `VITE_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.

## Primeros comandos

```bash
npm run cli -- auth status
npm run cli -- org list
npm run cli -- org create "Lufthansa"
npm run cli -- project list
npm run cli -- epic create "Motor de planeación" --project <project-id> --start 2026-09-01 --end 2026-09-30
npm run cli -- task list
npm run cli -- task create "Diseñar calendario" --destination backlog
npm run cli -- sprint create "Sprint 1" --duration 7d --project <project-id>
npm run cli -- board get
npm run cli -- notifications list
npm run cli -- notifications clear
npm run cli -- activity list
npm run cli -- agent validate-plan ./packages/cli/examples/agent-plan.example.json
npm run cli -- agent apply-plan ./packages/cli/examples/agent-plan.example.json --dry-run
```

`agent validate-plan` revisa la estructura del plan sin token de usuario. `agent apply-plan` usa `agent-commands` y aplica el plan mediante commands server-side, resolviendo `ref`, `epic_ref` y `sprint_ref` contra los IDs reales que devuelve Supabase.
