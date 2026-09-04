create or replace function public.create_epic_command(
  p_project_id uuid,
  p_name text,
  p_color text default null,
  p_owner_id uuid default null,
  p_phase_id uuid default null,
  p_estimated_effort text default null,
  p_start_date date default null,
  p_end_date date default null
)
returns public.epics
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_epic public.epics%rowtype;
  v_next_sequence integer;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear épicas.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para crear épicas en este proyecto.';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'El nombre de la épica es obligatorio.';
  end if;

  if p_start_date is not null and p_end_date is not null and p_end_date < p_start_date then
    raise exception 'La fecha de fin de la épica no puede ser anterior a la fecha de inicio.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id
  for update;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  if p_owner_id is not null and not public.can_assign_project_user(p_project_id, p_owner_id) then
    raise exception 'El responsable de la épica debe pertenecer al proyecto.';
  end if;

  if p_phase_id is not null and not exists (
    select 1
    from public.epic_phases phase
    where phase.id = p_phase_id
  ) then
    raise exception 'La fase de la épica no existe.';
  end if;

  v_next_sequence := coalesce(v_project.epic_sequence, 0) + 1;

  update public.projects
  set
    epic_sequence = v_next_sequence,
    updated_at = now()
  where id = p_project_id;

  insert into public.epics (
    user_id,
    project_id,
    name,
    color,
    owner_id,
    phase_id,
    estimated_effort,
    epic_id_display,
    start_date,
    end_date
  )
  values (
    v_user_id,
    p_project_id,
    trim(p_name),
    coalesce(nullif(trim(coalesce(p_color, '')), ''), '#3B82F6'),
    p_owner_id,
    p_phase_id,
    nullif(trim(coalesce(p_estimated_effort, '')), ''),
    upper(v_project.project_key) || '-' || v_next_sequence::text,
    p_start_date,
    p_end_date
  )
  returning * into v_epic;

  perform public.record_activity_event(
    'epic.created',
    v_project.organization_id,
    p_project_id,
    null,
    null,
    v_user_id,
    jsonb_build_object(
      'epic_id', v_epic.id,
      'epic_id_display', v_epic.epic_id_display,
      'name', v_epic.name,
      'owner_id', v_epic.owner_id,
      'phase_id', v_epic.phase_id,
      'estimated_effort', v_epic.estimated_effort,
      'start_date', v_epic.start_date,
      'end_date', v_epic.end_date
    ),
    'epic.created:' || v_epic.id::text
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.epic_created',
    jsonb_build_object(
      'job_key', 'activity.epic_created:' || v_epic.id::text,
      'project_id', p_project_id,
      'epic_id', v_epic.id,
      'actor_id', v_user_id
    )
  );

  return v_epic;
end;
$$;

revoke all on function public.create_epic_command(uuid, text, text, uuid, uuid, text, date, date) from public;
revoke execute on function public.create_epic_command(uuid, text, text, uuid, uuid, text, date, date) from PUBLIC, anon;
grant execute on function public.create_epic_command(uuid, text, text, uuid, uuid, text, date, date) to authenticated;

create or replace function public.create_sprint_command(
  p_project_id uuid,
  p_name text,
  p_goal text default null,
  p_start_date timestamptz default now(),
  p_duration text default '7d',
  p_status text default 'future'
)
returns public.sprints
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_sprint public.sprints%rowtype;
  v_duration text := coalesce(nullif(trim(p_duration), ''), '7d');
  v_status text := coalesce(nullif(trim(p_status), ''), 'future');
  v_start_date timestamptz := coalesce(p_start_date, now());
  v_end_date timestamptz;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear sprints.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para crear sprints en este proyecto.';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'El nombre del sprint es obligatorio.';
  end if;

  if v_duration not in ('7d', '15d', '1m') then
    raise exception 'La duración del sprint debe ser 7d, 15d o 1m.';
  end if;

  if v_status not in ('future', 'active') then
    raise exception 'Un sprint nuevo solo puede crearse como future o active.';
  end if;

  if v_duration = '7d' then
    v_end_date := date_trunc('day', v_start_date) + interval '7 days' + interval '23 hours 59 minutes 59 seconds 999 milliseconds';
  elsif v_duration = '15d' then
    v_end_date := date_trunc('day', v_start_date) + interval '15 days' + interval '23 hours 59 minutes 59 seconds 999 milliseconds';
  else
    v_end_date := date_trunc('day', v_start_date) + interval '1 month' + interval '23 hours 59 minutes 59 seconds 999 milliseconds';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  if v_status = 'active' and exists (
    select 1
    from public.sprints sprint
    where sprint.project_id = p_project_id
      and sprint.status = 'active'
  ) then
    raise exception 'Ya existe un sprint activo en este proyecto.';
  end if;

  insert into public.sprints (
    project_id,
    name,
    goal,
    status,
    start_date,
    end_date
  )
  values (
    p_project_id,
    trim(p_name),
    nullif(trim(coalesce(p_goal, '')), ''),
    v_status,
    v_start_date,
    v_end_date
  )
  returning * into v_sprint;

  perform public.record_activity_event(
    'sprint.created',
    v_project.organization_id,
    p_project_id,
    v_sprint.id,
    null,
    v_user_id,
    jsonb_build_object(
      'name', v_sprint.name,
      'goal', v_sprint.goal,
      'status', v_sprint.status,
      'duration', v_duration,
      'start_date', v_sprint.start_date,
      'end_date', v_sprint.end_date
    ),
    'sprint.created:' || v_sprint.id::text
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.sprint_created',
    jsonb_build_object(
      'job_key', 'activity.sprint_created:' || v_sprint.id::text,
      'project_id', p_project_id,
      'sprint_id', v_sprint.id,
      'actor_id', v_user_id
    )
  );

  return v_sprint;
end;
$$;

revoke all on function public.create_sprint_command(uuid, text, text, timestamptz, text, text) from public;
revoke execute on function public.create_sprint_command(uuid, text, text, timestamptz, text, text) from PUBLIC, anon;
grant execute on function public.create_sprint_command(uuid, text, text, timestamptz, text, text) to authenticated;

create or replace function public.mark_all_notifications_read_command()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_updated_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para borrar notificaciones.';
  end if;

  update public.user_notifications
  set read_at = now()
  where user_id = v_user_id
    and read_at is null;

  get diagnostics v_updated_count = row_count;

  return v_updated_count;
end;
$$;

revoke all on function public.mark_all_notifications_read_command() from public;
revoke execute on function public.mark_all_notifications_read_command() from PUBLIC, anon;
grant execute on function public.mark_all_notifications_read_command() to authenticated;

create or replace function public.schedule_task_command(
  p_project_id uuid,
  p_task_id uuid,
  p_planned_start_date date default null,
  p_planned_end_date date default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para planificar tareas.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para planificar tareas en este proyecto.';
  end if;

  if p_task_id is null then
    raise exception 'La tarea es obligatoria.';
  end if;

  if p_planned_start_date is not null and p_planned_end_date is not null and p_planned_end_date < p_planned_start_date then
    raise exception 'La fecha final de la tarea no puede ser anterior a la fecha inicial.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  update public.tasks
  set
    planned_start_date = p_planned_start_date,
    planned_end_date = coalesce(p_planned_end_date, p_planned_start_date),
    updated_at = now()
  where id = p_task_id
    and project_id = p_project_id
  returning * into v_task;

  if v_task.id is null then
    raise exception 'La tarea no pertenece al proyecto activo.';
  end if;

  perform public.record_activity_event(
    'task.scheduled',
    v_project.organization_id,
    p_project_id,
    v_task.sprint_id,
    v_task.id,
    v_user_id,
    jsonb_build_object(
      'planned_start_date', v_task.planned_start_date,
      'planned_end_date', v_task.planned_end_date
    ),
    'task.scheduled:' || v_task.id::text || ':' || extract(epoch from now())::text
  );

  return v_task;
end;
$$;

revoke all on function public.schedule_task_command(uuid, uuid, date, date) from public;
revoke execute on function public.schedule_task_command(uuid, uuid, date, date) from PUBLIC, anon;
grant execute on function public.schedule_task_command(uuid, uuid, date, date) to authenticated;
