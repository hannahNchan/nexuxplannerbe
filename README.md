# NexusPlanner Backend

Reproducible NexusPlanner backend powered by the Supabase local stack. This repository contains the database schema, RLS policies, RPC command layer, Edge Functions, storage bucket policies, default seed catalogs, and the optional NexusPlanner CLI for agents.

This repo is intentionally shareable: it does not include production data, real users, organizations, projects, tasks, storage objects, or production secrets.

## Requirements

- Linux host with Docker Engine and Docker Compose support.
- Node.js 18+.
- npm.
- Supabase CLI through `npx supabase ...`; no global install is required.

Docker must be running before starting Supabase.

## Install

```bash
git clone <repo-url> nexusplannerbe
cd nexusplannerbe
npm install
cp .env.example .env
```

Start Supabase and apply the local schema:

```bash
npm run start
npm run reset
npm run status
```

`npm run start` starts the local Supabase Docker stack. `npm run reset` applies every migration and then runs `supabase/seed.sql`.

If you prefer not to use npm scripts:

```bash
npx supabase start
npx supabase db reset
npx supabase status
```

## Environment

After `npm run status`, copy the local API URL and keys into `.env`:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<publishable-or-anon-key-from-supabase-status>
SUPABASE_SERVICE_ROLE_KEY=<secret-or-service-role-key-from-supabase-status>

NEXUS_API_URL=http://127.0.0.1:54321
NEXUS_PUBLISHABLE_KEY=<publishable-or-anon-key-from-supabase-status>
NEXUS_ACCESS_TOKEN=
NEXUS_ORGANIZATION_ID=
NEXUS_PROJECT_ID=

JOB_WORKER_SECRET=change-me-local-only
```

Do not use Markdown links inside `.env` values. Environment values must be plain strings.

## Serve Edge Functions

Run this in a separate terminal after Supabase is already running:

```bash
npm run functions:serve
```

Local Edge Functions are served through:

```text
http://127.0.0.1:54321/functions/v1
```

The `job-worker` function requires `JOB_WORKER_SECRET` and callers must send the matching `x-job-worker-secret` header.

## Connect The Frontend

In the frontend repository, set `.env.local` with the values from `npm run status`:

```env
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY=<publishable-or-anon-key-from-supabase-status>
VITE_AUTH_REDIRECT_URL=http://localhost:5173
```

Then start the frontend:

```bash
npm install
npm run dev
```

Open the app at:

```text
http://localhost:5173
```

Supabase Studio is available at:

```text
http://127.0.0.1:54323
```

For a fresh local setup, create test users from Supabase Studio under `Authentication -> Users`.

## What This Creates

- Public NexusPlanner schema from `supabase/migrations/00000000000000_baseline_schema.sql`.
- Follow-up migrations for organization deletion commands, CLI/agent commands, and status badge colors.
- Storage buckets:
  - `project-assets`
  - `avatars`
  - `task-images`
- Edge Functions:
  - `agent-commands`
  - `epic-commands`
  - `job-worker`
  - `notification-commands`
  - `sprint-commands`
  - `task-commands`
  - `workspace-commands`
- Default catalogs:
  - issue types
  - priorities
  - epic phases
  - Fibonacci story point system
  - Fibonacci story point values

## What This Does Not Create

- Auth users.
- Real organizations.
- Real projects.
- Epics, tasks, sprints, reports, or activity data.
- Storage objects.
- Production secrets.

## CLI

The optional CLI lives in `packages/cli`:

```bash
npm run cli -- help
npm run cli -- auth status
```

Configure it against the local backend:

```bash
npm run cli -- config set url http://127.0.0.1:54321
npm run cli -- config set anon-key <publishable-or-anon-key>
npm run cli -- config set token <user-access-token>
```

The CLI also reads `~/.nexusplanner/config.json`. Before mutating data, check the active configuration:

```bash
npm run cli -- config get
```

CLI documentation:

- `docs/cli/README.md`
- `docs/cli/AGENT_PLANS.md`

## Stop Services

Stop the Supabase local stack:

```bash
npm run stop
```

Or directly:

```bash
npx supabase stop
```

To stop and remove the local database data instead of keeping a backup:

```bash
npx supabase stop --no-backup
```

## Uninstall Local Dependencies

Use this when you want to keep the repository but remove installed dependencies and local Supabase runtime state:

```bash
npm run stop
rm -rf node_modules
rm -f package-lock.json
rm -rf supabase/.temp
```

This keeps the source files, migrations, functions, seed data, docs, and `.env` files.

To install again later:

```bash
npm install
npm run start
npm run reset
npm run functions:serve
```

## Full Local Cleanup

If you want a stronger cleanup of Docker resources created by the Supabase local stack:

```bash
npx supabase stop --no-backup
docker ps -a
docker volume ls
```

Only remove Docker volumes manually if you are sure they belong to this local test environment.

## Why There Is No Custom docker-compose.yml Yet

The Supabase CLI already manages the local Docker Compose stack for Postgres, Auth, REST, Realtime, Storage, Studio, and Edge Runtime. Keeping a custom Compose file now would duplicate Supabase CLI behavior and make upgrades easier to break.

When this backend is promoted to a permanent Raspberry Pi or server deployment, the next step is to add a production-oriented self-hosted profile with a dedicated `docker-compose.yml`, healthchecks, backup strategy, reverse proxy, TLS, and real secret management.
