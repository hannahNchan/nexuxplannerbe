create or replace function public.delete_organization_command(
  p_organization_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_organization public.organizations%rowtype;
  v_project_ids uuid[];
begin
  if v_actor_id is null then
    raise exception 'Debes iniciar sesión para eliminar una organización.';
  end if;

  select public.current_organization_role(p_organization_id)
    into v_role;

  if coalesce(v_role, '') <> 'owner' then
    raise exception 'Solo el owner puede eliminar la organización.';
  end if;

  select *
    into v_organization
  from public.organizations
  where id = p_organization_id
  for update;

  if v_organization.id is null then
    raise exception 'Organización no encontrada.';
  end if;

  select coalesce(array_agg(id), array[]::uuid[])
    into v_project_ids
  from public.projects
  where organization_id = p_organization_id;

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.organization_deleted',
    jsonb_build_object(
      'job_key', 'organization-deleted:' || p_organization_id::text,
      'organizationId', p_organization_id,
      'organizationName', v_organization.name,
      'actorId', v_actor_id,
      'projectIds', v_project_ids,
      'storageCleanup', jsonb_build_object(
        'bucket', 'project-assets',
        'prefixes', jsonb_build_array(
          'organization-logos/' || p_organization_id::text || '/'
        )
      )
    )
  );

  delete from public.organizations
  where id = p_organization_id;

  return p_organization_id;
end;
$$;

revoke execute on function public.delete_organization_command(uuid) from PUBLIC, anon;
grant execute on function public.delete_organization_command(uuid) to authenticated;
