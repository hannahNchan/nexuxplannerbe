# Migration Notes

This backend repo starts from a schema-only baseline exported from the working NexusPlanner backend.

The baseline intentionally contains no table data. Personal exports such as `cloud_data_auth_public_storage.sql` must not be copied here because they can contain users, organizations, projects, storage object metadata and private URLs.

Executable migrations are organized as:

1. `00000000000000_baseline_schema.sql` - complete public schema baseline.
2. Post-baseline migrations - backend changes created after the baseline export.
3. `storage_buckets_and_policies` - empty buckets and storage policies for local installs.
4. `seed.sql` - global catalogs only.

For future changes, create migrations with:

```bash
npx supabase migration new <descriptive_name>
```

Then verify from a clean database:

```bash
npx supabase db reset
```
