# Agent Instructions

This repository is the backend-only distribution for NexusPlanner.

Before changing backend behavior, inspect:

- `README.md`
- `supabase/config.toml`
- `supabase/migrations`
- `supabase/functions`
- `supabase/seed.sql`

Rules:

- Keep this repo free of personal data, production dumps, real user rows, passwords, access tokens and service role keys.
- Use `supabase migration new <name>` for new schema changes.
- Do not add organizations, projects, tasks, sprints or users to `seed.sql`; seed only global/default catalogs and empty infrastructure setup.
- Prefer SQL commands/RPCs and Edge Functions as the backend boundary. Do not duplicate business rules in a client script.
- Verify with `npx supabase db reset` when Docker is available.

