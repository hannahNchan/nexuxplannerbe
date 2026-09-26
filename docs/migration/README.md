# Migration Notes

For the complete operational workflow, including backups, Raspberry Pi deployment, validation and restore precautions, read `docs/OPERATIONS.md`. For table ownership, cascades and invariants, read `docs/DATA_MODEL.md`.

This backend repo starts from a schema-only baseline exported from the working NexusPlanner backend.

The baseline intentionally contains no table data. Personal exports such as `cloud_data_auth_public_storage.sql` must not be copied here because they can contain users, organizations, projects, storage object metadata and private URLs.

Executable migrations are organized as:

1. `00000000000000_baseline_schema.sql` - complete public schema baseline.
2. Post-baseline migrations - backend changes created after the baseline export.
3. `storage_buckets_and_policies` - empty buckets and storage policies for local installs.
4. `seed.sql` - global catalogs only.

Current migration ledger:

| Migration | Purpose |
| --- | --- |
| `00000000000000_baseline_schema.sql` | Public schema, functions, triggers, grants and RLS baseline |
| `20260825001916_organization_settings_delete_command.sql` | Owner-only organization deletion command |
| `20260825003434_fix_delete_organization_storage_cleanup.sql` | Prevents unsafe direct deletion from Storage system tables |
| `20260831195943_cli_missing_backend_commands.sql` | Commands required by CLI and agent plans |
| `20260904181108_add_column_status_badge_colors.sql` | Twelve-color status badge palette on project columns |
| `20260904194224_storage_buckets_and_policies.sql` | Empty buckets, limits and Storage access policies |
| `20260926210129_add_project_board_scope_preferences.sql` | Per-user board scope preference, board read model and scope command |
| `20260926211638_add_board_task_placement_commands.sql` | Atomic task placement commands for backlog, Kanban and sprint, plus sprint-close normalization and placement audit |

This list is descriptive. Migration filenames and SQL content remain authoritative.

For future changes, create migrations with:

```bash
npx supabase migration new <descriptive_name>
```

Then verify from a clean database:

```bash
npx supabase db reset
```

`db reset` is only for a disposable local database. Never run it against the persistent Raspberry Pi installation or any environment containing personal data.

Before applying an incremental migration to an existing installation:

1. Create and verify a private backup outside this repository.
2. Test the migration from a clean local database.
3. Test the upgrade against a restored copy when the change is destructive or rewrites data.
4. Inspect the target and pending migrations before executing `db push`.
5. Apply the migration once, run smoke tests, and record the deployed commit.
