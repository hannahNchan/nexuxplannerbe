insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'project-assets',
    'project-assets',
    true,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  ),
  (
    'avatars',
    'avatars',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  ),
  (
    'task-images',
    'task-images',
    true,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  )
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users can view project asset files" on storage.objects;
create policy "Users can view project asset files"
  on storage.objects
  for select
  to authenticated, anon
  using (bucket_id = 'project-assets');

drop policy if exists "Project owners can manage project asset files" on storage.objects;
create policy "Project owners can manage project asset files"
  on storage.objects
  to authenticated
  using (
    bucket_id = 'project-assets'
    and exists (
      select 1
      from public.projects project
      where project.id::text = (storage.foldername(storage.objects.name))[2]
        and public.can_manage_project(project.id)
    )
  )
  with check (
    bucket_id = 'project-assets'
    and exists (
      select 1
      from public.projects project
      where project.id::text = (storage.foldername(storage.objects.name))[2]
        and public.can_manage_project(project.id)
    )
  );

drop policy if exists "Organization admins can manage organization logos" on storage.objects;
create policy "Organization admins can manage organization logos"
  on storage.objects
  to authenticated
  using (
    bucket_id = 'project-assets'
    and (storage.foldername(name))[1] = 'organization-logos'
    and public.can_manage_organization(((storage.foldername(name))[2])::uuid)
  )
  with check (
    bucket_id = 'project-assets'
    and (storage.foldername(name))[1] = 'organization-logos'
    and public.can_manage_organization(((storage.foldername(name))[2])::uuid)
  );

drop policy if exists "Users can view avatar files" on storage.objects;
create policy "Users can view avatar files"
  on storage.objects
  for select
  to authenticated, anon
  using (bucket_id = 'avatars');

drop policy if exists "Users can manage own avatar files" on storage.objects;
create policy "Users can manage own avatar files"
  on storage.objects
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users can view task image files" on storage.objects;
create policy "Users can view task image files"
  on storage.objects
  for select
  to authenticated, anon
  using (bucket_id = 'task-images');

drop policy if exists "Authenticated users can manage task image files" on storage.objects;
create policy "Authenticated users can manage task image files"
  on storage.objects
  to authenticated
  using (bucket_id = 'task-images')
  with check (bucket_id = 'task-images');
