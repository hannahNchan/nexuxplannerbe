create or replace function public.move_task_destination_command(
  p_project_id uuid,
  p_task_id uuid,
  p_destination text,
  p_sprint_id uuid default null,
  p_column_id uuid default null,
  p_position integer default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_destination text := lower(trim(coalesce(p_destination, '')));
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_previous_column_id uuid;
  v_previous_sprint_id uuid;
  v_previous_in_backlog boolean;
  v_previous_position integer;
  v_target_column_id uuid := p_column_id;
  v_target_sprint_id uuid := p_sprint_id;
  v_target_position integer;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para mover tareas.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para mover tareas en este proyecto.';
  end if;

  if p_task_id is null then
    raise exception 'La tarea es requerida.';
  end if;

  if v_destination not in ('backlog', 'kanban', 'sprint') then
    raise exception 'El destino debe ser backlog, kanban o sprint.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  select *
    into v_task
  from public.tasks
  where id = p_task_id
    and project_id = p_project_id
  for update;

  if v_task.id is null then
    raise exception 'La tarea no pertenece al proyecto activo.';
  end if;

  v_previous_column_id := v_task.column_id;
  v_previous_sprint_id := v_task.sprint_id;
  v_previous_in_backlog := v_task.in_backlog;
  v_previous_position := v_task.position;

  if v_destination = 'backlog' then
    v_target_column_id := null;
    v_target_sprint_id := null;

    if p_position is null then
      select coalesce(max(task.position), -1) + 1
        into v_target_position
      from public.tasks task
      where task.project_id = p_project_id
        and task.in_backlog = true
        and task.id <> p_task_id;
    else
      v_target_position := greatest(p_position, 0);
    end if;
  else
    if v_target_column_id is null then
      select column_record.id
        into v_target_column_id
      from public.columns column_record
      where column_record.project_id = p_project_id
      order by column_record.position, column_record.created_at
      limit 1;
    end if;

    if v_target_column_id is null or not exists (
      select 1
      from public.columns column_record
      where column_record.id = v_target_column_id
        and column_record.project_id = p_project_id
    ) then
      raise exception 'La columna no pertenece al proyecto activo.';
    end if;

    if v_destination = 'kanban' then
      v_target_sprint_id := null;
    elsif v_target_sprint_id is null or not exists (
      select 1
      from public.sprints sprint
      where sprint.id = v_target_sprint_id
        and sprint.project_id = p_project_id
        and sprint.status in ('active', 'future')
    ) then
      raise exception 'Solo puedes mover tareas a sprints activos o planificados del proyecto.';
    end if;

    if p_position is null then
      select coalesce(max(task.position), -1) + 1
        into v_target_position
      from public.tasks task
      where task.project_id = p_project_id
        and task.in_backlog = false
        and task.column_id = v_target_column_id
        and task.sprint_id is not distinct from v_target_sprint_id
        and task.id <> p_task_id;
    else
      v_target_position := greatest(p_position, 0);
    end if;
  end if;

  update public.tasks
  set
    in_backlog = v_destination = 'backlog',
    column_id = v_target_column_id,
    sprint_id = v_target_sprint_id,
    position = v_target_position,
    updated_at = now()
  where id = p_task_id
    and project_id = p_project_id
  returning * into v_task;

  if v_previous_in_backlog is distinct from v_task.in_backlog
    or v_previous_column_id is distinct from v_task.column_id
    or v_previous_sprint_id is distinct from v_task.sprint_id
    or v_previous_position is distinct from v_task.position
  then
    perform public.record_activity_event(
      'task.moved',
      v_project.organization_id,
      p_project_id,
      v_task.sprint_id,
      v_task.id,
      v_user_id,
      jsonb_build_object(
        'destination', v_destination,
        'previous_in_backlog', v_previous_in_backlog,
        'in_backlog', v_task.in_backlog,
        'previous_column_id', v_previous_column_id,
        'column_id', v_task.column_id,
        'previous_sprint_id', v_previous_sprint_id,
        'sprint_id', v_task.sprint_id,
        'previous_position', v_previous_position,
        'position', v_task.position,
        'task_id_display', v_task.task_id_display
      ),
      'task-moved:' || v_task.id || ':' || extract(epoch from v_task.updated_at)::text
    );

    perform public.enqueue_command_job(
      'nexusplanner-events',
      'activity.task_moved',
      jsonb_build_object(
        'job_key', 'activity.task_moved:' || v_task.id || ':' || extract(epoch from v_task.updated_at)::text,
        'project_id', p_project_id,
        'task_id', v_task.id,
        'destination', v_destination,
        'actor_id', v_user_id
      )
    );
  end if;

  return v_task;
end;
$$;

revoke all on function public.move_task_destination_command(uuid, uuid, text, uuid, uuid, integer)
  from public, anon, authenticated;

create or replace function public.move_task_to_backlog_command(
  p_project_id uuid,
  p_task_id uuid,
  p_position integer default null
)
returns public.tasks
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.move_task_destination_command(
    p_project_id,
    p_task_id,
    'backlog',
    null,
    null,
    p_position
  );
$$;

revoke all on function public.move_task_to_backlog_command(uuid, uuid, integer)
  from public, anon;
grant execute on function public.move_task_to_backlog_command(uuid, uuid, integer)
  to authenticated;

create or replace function public.move_task_to_kanban_command(
  p_project_id uuid,
  p_task_id uuid,
  p_column_id uuid default null,
  p_position integer default null
)
returns public.tasks
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.move_task_destination_command(
    p_project_id,
    p_task_id,
    'kanban',
    null,
    p_column_id,
    p_position
  );
$$;

revoke all on function public.move_task_to_kanban_command(uuid, uuid, uuid, integer)
  from public, anon;
grant execute on function public.move_task_to_kanban_command(uuid, uuid, uuid, integer)
  to authenticated;

create or replace function public.move_task_to_sprint_command(
  p_project_id uuid,
  p_task_id uuid,
  p_sprint_id uuid,
  p_column_id uuid default null,
  p_position integer default null
)
returns public.tasks
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.move_task_destination_command(
    p_project_id,
    p_task_id,
    'sprint',
    p_sprint_id,
    p_column_id,
    p_position
  );
$$;

revoke all on function public.move_task_to_sprint_command(uuid, uuid, uuid, uuid, integer)
  from public, anon;
grant execute on function public.move_task_to_sprint_command(uuid, uuid, uuid, uuid, integer)
  to authenticated;

create or replace function public.move_task_column_command(
  p_project_id uuid,
  p_task_id uuid,
  p_column_id uuid,
  p_position integer default null
)
returns public.tasks
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_task public.tasks%rowtype;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para mover tareas.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para mover tareas en este proyecto.';
  end if;

  select *
    into v_task
  from public.tasks
  where id = p_task_id
    and project_id = p_project_id
  for update;

  if v_task.id is null then
    raise exception 'La tarea no pertenece al proyecto activo.';
  end if;

  if v_task.in_backlog then
    raise exception 'Usa el comando de destino Kanban o Sprint para sacar una tarea del backlog.';
  end if;

  return public.move_task_destination_command(
    p_project_id,
    p_task_id,
    case when v_task.sprint_id is null then 'kanban' else 'sprint' end,
    v_task.sprint_id,
    p_column_id,
    p_position
  );
end;
$$;

revoke all on function public.move_task_column_command(uuid, uuid, uuid, integer)
  from public, anon;
grant execute on function public.move_task_column_command(uuid, uuid, uuid, integer)
  to authenticated;

create or replace function public.create_task_command(
  p_project_id uuid,
  p_title text,
  p_subtitle text default null,
  p_description text default null,
  p_destination text default 'backlog',
  p_column_id uuid default null,
  p_sprint_id uuid default null,
  p_position integer default 0,
  p_issue_type_id uuid default null,
  p_priority_id uuid default null,
  p_story_points text default null,
  p_assignee_id uuid default null,
  p_epic_id uuid default null,
  p_github_link text default null
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
  v_next_sequence integer;
  v_requested_destination text := lower(coalesce(nullif(trim(p_destination), ''), 'backlog'));
  v_destination text;
  v_in_backlog boolean;
  v_column_id uuid := p_column_id;
  v_sprint_id uuid := p_sprint_id;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear tareas.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para crear tareas en este proyecto.';
  end if;

  if trim(coalesce(p_title, '')) = '' then
    raise exception 'El título de la tarea es obligatorio.';
  end if;

  if v_requested_destination not in ('backlog', 'kanban', 'sprint', 'scrum') then
    raise exception 'El destino debe ser backlog, kanban o sprint.';
  end if;

  v_destination := case
    when v_requested_destination = 'scrum' and p_sprint_id is not null then 'sprint'
    when v_requested_destination = 'scrum' then 'kanban'
    else v_requested_destination
  end;

  select *
    into v_project
  from public.projects
  where id = p_project_id
  for update;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  if p_epic_id is not null and not exists (
    select 1
    from public.epics epic
    where epic.id = p_epic_id
      and epic.project_id = p_project_id
  ) then
    raise exception 'La épica no pertenece al proyecto activo.';
  end if;

  if p_assignee_id is not null and not exists (
    select 1
    from public.project_members member
    where member.project_id = p_project_id
      and member.user_id = p_assignee_id
  ) then
    raise exception 'Solo puedes asignar tareas a miembros del proyecto.';
  end if;

  if v_destination = 'backlog' then
    v_in_backlog := true;
    v_column_id := null;
    v_sprint_id := null;
  else
    v_in_backlog := false;

    if v_column_id is null then
      select column_record.id
        into v_column_id
      from public.columns column_record
      where column_record.project_id = p_project_id
      order by column_record.position, column_record.created_at
      limit 1;
    end if;

    if v_column_id is null or not exists (
      select 1
      from public.columns column_record
      where column_record.id = v_column_id
        and column_record.project_id = p_project_id
    ) then
      raise exception 'La columna no pertenece al proyecto activo.';
    end if;

    if v_destination = 'kanban' then
      v_sprint_id := null;
    elsif v_sprint_id is null then
      raise exception 'Las tareas con destino sprint necesitan un sprint.';
    elsif not exists (
      select 1
      from public.sprints sprint
      where sprint.id = v_sprint_id
        and sprint.project_id = p_project_id
        and sprint.status in ('active', 'future')
    ) then
      raise exception 'Solo puedes crear tareas en sprints activos o planificados del proyecto.';
    end if;
  end if;

  v_next_sequence := coalesce(v_project.task_sequence, 0) + 1;

  update public.projects
  set
    task_sequence = v_next_sequence,
    updated_at = now()
  where id = p_project_id;

  insert into public.tasks (
    project_id,
    title,
    task_id_display,
    subtitle,
    description,
    position,
    in_backlog,
    column_id,
    sprint_id,
    issue_type_id,
    priority_id,
    story_points,
    assignee_id,
    epic_id,
    github_link
  )
  values (
    p_project_id,
    trim(p_title),
    upper(v_project.project_key) || '-' || v_next_sequence::text,
    nullif(trim(coalesce(p_subtitle, '')), ''),
    nullif(p_description, ''),
    greatest(coalesce(p_position, 0), 0),
    v_in_backlog,
    v_column_id,
    v_sprint_id,
    p_issue_type_id,
    p_priority_id,
    nullif(trim(coalesce(p_story_points, '')), ''),
    p_assignee_id,
    p_epic_id,
    nullif(trim(coalesce(p_github_link, '')), '')
  )
  returning * into v_task;

  perform public.record_activity_event(
    'task.created',
    v_project.organization_id,
    p_project_id,
    v_sprint_id,
    v_task.id,
    v_user_id,
    jsonb_build_object(
      'destination', v_destination,
      'requested_destination', v_requested_destination,
      'task_id_display', v_task.task_id_display,
      'title', v_task.title,
      'subtitle', v_task.subtitle,
      'column_id', v_task.column_id,
      'sprint_id', v_task.sprint_id,
      'issue_type_id', v_task.issue_type_id,
      'priority_id', v_task.priority_id,
      'story_points', v_task.story_points,
      'assignee_id', v_task.assignee_id,
      'epic_id', v_task.epic_id,
      'is_unassigned', v_task.assignee_id is null,
      'in_backlog', v_task.in_backlog
    ),
    'task-created:' || v_task.id
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.task_created',
    jsonb_build_object(
      'job_key', 'activity.task_created:' || v_task.id,
      'project_id', p_project_id,
      'task_id', v_task.id,
      'actor_id', v_user_id
    )
  );

  return v_task;
end;
$$;

revoke execute on function public.create_task_command(
  uuid, text, text, text, text, uuid, uuid, integer, uuid, uuid, text, uuid, uuid, text
) from PUBLIC, anon;
grant execute on function public.create_task_command(
  uuid, text, text, text, text, uuid, uuid, integer, uuid, uuid, text, uuid, uuid, text
) to authenticated;

create or replace function public.complete_sprint_command(
  p_project_id uuid,
  p_sprint_id uuid,
  p_dispositions jsonb default '[]'::jsonb
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
  v_first_column_id uuid;
  v_completed_tasks integer := 0;
  v_incomplete_tasks integer := 0;
  v_disposition_count integer;
  v_total_disposition_count integer;
  v_invalid_disposition_count integer;
  v_task record;
  v_action text;
  v_target_sprint_id uuid;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para completar sprints.';
  end if;

  if p_project_id is null or not public.can_mutate_project(p_project_id) then
    raise exception 'No tienes permisos para completar sprints en este proyecto.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  select *
    into v_sprint
  from public.sprints
  where id = p_sprint_id
    and project_id = p_project_id
  for update;

  if v_sprint.id is null then
    raise exception 'El sprint no pertenece al proyecto activo.';
  end if;

  if v_sprint.status <> 'active' then
    raise exception 'Solo puedes completar un sprint activo.';
  end if;

  if jsonb_typeof(coalesce(p_dispositions, '[]'::jsonb)) <> 'array' then
    raise exception 'Las decisiones de tareas incompletas deben enviarse como arreglo.';
  end if;

  create temporary table if not exists tmp_incomplete_tasks (
    task_id uuid primary key
  ) on commit drop;

  truncate table tmp_incomplete_tasks;

  insert into tmp_incomplete_tasks (task_id)
  select task.id
  from public.tasks task
  left join public.columns column_record on column_record.id = task.column_id
  where task.project_id = p_project_id
    and task.sprint_id = p_sprint_id
    and not (
      column_record.id is not null
      and lower(trim(
        translate(
          column_record.name,
          'ÁÉÍÓÚÜÑáéíóúüñ',
          'AEIOUUNaeiouun'
        )
      )) in ('done', 'hecho', 'finalizado', 'completado', 'cerrado')
    );

  select count(*) into v_incomplete_tasks from tmp_incomplete_tasks;

  select count(*)
    into v_completed_tasks
  from public.tasks task
  where task.project_id = p_project_id
    and task.sprint_id = p_sprint_id
    and not exists (
      select 1
      from tmp_incomplete_tasks incomplete
      where incomplete.task_id = task.id
    );

  select
    count(*),
    count(distinct (disposition->>'taskId')::uuid)
    into v_total_disposition_count, v_disposition_count
  from jsonb_array_elements(coalesce(p_dispositions, '[]'::jsonb)) disposition
  where (disposition->>'taskId')::uuid in (select task_id from tmp_incomplete_tasks);

  if v_total_disposition_count <> v_incomplete_tasks
    or v_disposition_count <> v_incomplete_tasks
  then
    raise exception 'Cada tarea incompleta necesita exactamente una decisión antes de completar el sprint.';
  end if;

  select count(*)
    into v_invalid_disposition_count
  from jsonb_array_elements(coalesce(p_dispositions, '[]'::jsonb)) disposition
  where not exists (
    select 1
    from tmp_incomplete_tasks incomplete
    where incomplete.task_id = (disposition->>'taskId')::uuid
  );

  if v_invalid_disposition_count > 0 then
    raise exception 'Hay decisiones para tareas que no están incompletas en este sprint.';
  end if;

  perform public.generate_sprint_report(
    p_project_id,
    p_sprint_id,
    v_user_id,
    coalesce(p_dispositions, '[]'::jsonb)
  );

  select column_record.id
    into v_first_column_id
  from public.columns column_record
  where column_record.project_id = p_project_id
  order by column_record.position, column_record.created_at
  limit 1;

  for v_task in
    select
      disposition,
      (disposition->>'taskId')::uuid as task_id
    from jsonb_array_elements(coalesce(p_dispositions, '[]'::jsonb)) disposition
  loop
    v_action := lower(coalesce(v_task.disposition->>'destination', v_task.disposition->>'action'));
    v_target_sprint_id := nullif(v_task.disposition->>'sprintId', '')::uuid;

    if v_action = 'backlog' then
      update public.tasks
      set
        sprint_id = null,
        in_backlog = true,
        column_id = null,
        updated_at = now()
      where id = v_task.task_id
        and project_id = p_project_id
        and sprint_id = p_sprint_id;
    elsif v_action = 'kanban' then
      if v_first_column_id is null then
        raise exception 'No se encontró una columna inicial para mover tareas a Kanban.';
      end if;

      update public.tasks
      set
        sprint_id = null,
        in_backlog = false,
        column_id = v_first_column_id,
        updated_at = now()
      where id = v_task.task_id
        and project_id = p_project_id
        and sprint_id = p_sprint_id;
    elsif v_action in ('sprint', 'next_sprint', 'new_sprint') then
      if v_target_sprint_id is null then
        raise exception 'Las tareas movidas a sprint necesitan un sprint destino.';
      end if;

      if v_first_column_id is null then
        raise exception 'No se encontró una columna inicial para mover tareas al siguiente sprint.';
      end if;

      if not exists (
        select 1
        from public.sprints target_sprint
        where target_sprint.id = v_target_sprint_id
          and target_sprint.project_id = p_project_id
          and target_sprint.status = 'future'
      ) then
        raise exception 'Solo puedes mover tareas incompletas a sprints futuros del proyecto activo.';
      end if;

      update public.tasks
      set
        sprint_id = v_target_sprint_id,
        in_backlog = false,
        column_id = v_first_column_id,
        updated_at = now()
      where id = v_task.task_id
        and project_id = p_project_id
        and sprint_id = p_sprint_id;
    else
      raise exception 'Destino inválido para una tarea incompleta.';
    end if;
  end loop;

  update public.sprints
  set
    status = 'closed',
    updated_at = now()
  where id = p_sprint_id
    and project_id = p_project_id
  returning * into v_sprint;

  update public.user_project_board_preferences
  set
    selected_scope = 'kanban',
    updated_at = now()
  where project_id = p_project_id
    and selected_scope = 'sprint';

  perform public.record_activity_event(
    'sprint.completed',
    v_project.organization_id,
    p_project_id,
    p_sprint_id,
    null,
    v_user_id,
    jsonb_build_object(
      'completed_tasks', v_completed_tasks,
      'incomplete_tasks', v_incomplete_tasks,
      'dispositions', coalesce(p_dispositions, '[]'::jsonb)
    ),
    'sprint-completed:' || p_sprint_id
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'report.sprint_completed',
    jsonb_build_object(
      'job_key', 'report.sprint_completed:' || p_sprint_id,
      'project_id', p_project_id,
      'sprint_id', p_sprint_id,
      'actor_id', v_user_id
    )
  );

  return v_sprint;
end;
$$;

revoke execute on function public.complete_sprint_command(uuid, uuid, jsonb)
  from PUBLIC, anon;
grant execute on function public.complete_sprint_command(uuid, uuid, jsonb)
  to authenticated;

create or replace function public.audit_task_placement_consistency(
  p_project_id uuid default null
)
returns table (
  task_id uuid,
  project_id uuid,
  problem text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select task.id, task.project_id, 'backlog_has_board_assignment'::text
  from public.tasks task
  where (p_project_id is null or task.project_id = p_project_id)
    and task.in_backlog = true
    and (task.column_id is not null or task.sprint_id is not null)

  union all

  select task.id, task.project_id, 'board_task_missing_column'::text
  from public.tasks task
  where (p_project_id is null or task.project_id = p_project_id)
    and task.in_backlog = false
    and task.column_id is null

  union all

  select task.id, task.project_id, 'column_belongs_to_another_project'::text
  from public.tasks task
  join public.columns column_record on column_record.id = task.column_id
  where (p_project_id is null or task.project_id = p_project_id)
    and column_record.project_id is distinct from task.project_id

  union all

  select task.id, task.project_id, 'sprint_belongs_to_another_project'::text
  from public.tasks task
  join public.sprints sprint on sprint.id = task.sprint_id
  where (p_project_id is null or task.project_id = p_project_id)
    and sprint.project_id is distinct from task.project_id;
$$;

revoke all on function public.audit_task_placement_consistency(uuid)
  from public, anon, authenticated;
grant execute on function public.audit_task_placement_consistency(uuid)
  to service_role;
