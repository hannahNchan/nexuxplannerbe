create table public.user_project_board_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  selected_scope text not null default 'kanban',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_project_board_preferences_pkey primary key (user_id, project_id),
  constraint user_project_board_preferences_scope_check
    check (selected_scope in ('kanban', 'sprint'))
);

comment on table public.user_project_board_preferences is
  'Per-user, per-project preference for the board scope displayed by NexusPlanner.';

comment on column public.user_project_board_preferences.selected_scope is
  'Requested board scope. The effective scope falls back to kanban when no active sprint exists.';

create index user_project_board_preferences_project_idx
  on public.user_project_board_preferences (project_id);

create trigger set_user_project_board_preferences_updated_at
before update on public.user_project_board_preferences
for each row execute function public.set_updated_at();

alter table public.user_project_board_preferences enable row level security;

create policy "Users can view own project board preferences"
  on public.user_project_board_preferences
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    and public.can_view_project(project_id)
  );

create policy "Users can create own project board preferences"
  on public.user_project_board_preferences
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.can_view_project(project_id)
  );

create policy "Users can update own project board preferences"
  on public.user_project_board_preferences
  for update
  to authenticated
  using (
    user_id = (select auth.uid())
    and public.can_view_project(project_id)
  )
  with check (
    user_id = (select auth.uid())
    and public.can_view_project(project_id)
  );

create policy "Users can delete own project board preferences"
  on public.user_project_board_preferences
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    and public.can_view_project(project_id)
  );

revoke all on table public.user_project_board_preferences from public, anon, authenticated;
grant select on table public.user_project_board_preferences to authenticated;
grant all on table public.user_project_board_preferences to service_role;

create or replace function public.get_project_board_view(
  p_project_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_active_sprint public.sprints%rowtype;
  v_selected_scope text := 'kanban';
  v_effective_scope text := 'kanban';
  v_can_mutate boolean := false;
  v_column_order jsonb := '[]'::jsonb;
  v_columns jsonb := '[]'::jsonb;
  v_tasks jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para consultar el tablero.';
  end if;

  if p_project_id is null or not public.can_view_project(p_project_id) then
    raise exception 'No tienes permisos para consultar este proyecto.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  select *
    into v_active_sprint
  from public.sprints
  where project_id = p_project_id
    and status = 'active'
  order by start_date desc nulls last, created_at desc
  limit 1;

  select preference.selected_scope
    into v_selected_scope
  from public.user_project_board_preferences preference
  where preference.user_id = v_user_id
    and preference.project_id = p_project_id;

  v_selected_scope := coalesce(
    v_selected_scope,
    case when v_active_sprint.id is not null then 'sprint' else 'kanban' end
  );
  v_effective_scope := case
    when v_selected_scope = 'sprint' and v_active_sprint.id is not null then 'sprint'
    else 'kanban'
  end;
  v_can_mutate := public.can_mutate_project(p_project_id);

  select coalesce(order_record.column_ids, '[]'::jsonb)
    into v_column_order
  from public.column_order order_record
  where order_record.project_id = p_project_id
  order by order_record.updated_at desc, order_record.created_at desc
  limit 1;

  v_column_order := coalesce(v_column_order, '[]'::jsonb);

  select coalesce(
    jsonb_agg(
      to_jsonb(column_record.id)
      order by
        case when requested_order.ordinality is null then 1 else 0 end,
        requested_order.ordinality,
        column_record.position,
        column_record.created_at
    ),
    '[]'::jsonb
  )
    into v_column_order
  from public.columns column_record
  left join lateral (
    select ordered_column.ordinality
    from jsonb_array_elements_text(v_column_order)
      with ordinality as ordered_column(column_id, ordinality)
    where ordered_column.column_id = column_record.id::text
    limit 1
  ) requested_order on true
  where column_record.project_id = p_project_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', column_record.id,
        'name', column_record.name,
        'position', column_record.position,
        'color', column_record.color,
        'createdAt', column_record.created_at,
        'updatedAt', column_record.updated_at
      )
      order by column_record.position, column_record.created_at
    ),
    '[]'::jsonb
  )
    into v_columns
  from public.columns column_record
  where column_record.project_id = p_project_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', task.id,
        'projectId', task.project_id,
        'columnId', task.column_id,
        'sprintId', task.sprint_id,
        'epicId', task.epic_id,
        'parentTaskId', task.parent_task_id,
        'displayId', task.task_id_display,
        'title', task.title,
        'subtitle', task.subtitle,
        'description', task.description,
        'position', task.position,
        'storyPoints', task.story_points,
        'githubLink', task.github_link,
        'plannedStartDate', task.planned_start_date,
        'plannedEndDate', task.planned_end_date,
        'createdAt', task.created_at,
        'updatedAt', task.updated_at,
        'issueType', case
          when issue_type.id is null then null
          else jsonb_build_object(
            'id', issue_type.id,
            'name', issue_type.name,
            'icon', issue_type.icon,
            'color', issue_type.color
          )
        end,
        'priority', case
          when priority.id is null then null
          else jsonb_build_object(
            'id', priority.id,
            'name', priority.name,
            'level', priority.level,
            'color', priority.color
          )
        end,
        'assignee', case
          when assignee.id is null then null
          else jsonb_build_object(
            'id', assignee.id,
            'fullName', assignee.full_name,
            'avatarUrl', assignee.avatar_url,
            'jobTitle', assignee.job_title
          )
        end,
        'epic', case
          when epic.id is null then null
          else jsonb_build_object(
            'id', epic.id,
            'displayId', epic.epic_id_display,
            'name', epic.name,
            'color', epic.color
          )
        end
      )
      order by task.position, task.created_at
    ),
    '[]'::jsonb
  )
    into v_tasks
  from public.tasks task
  left join public.issue_types issue_type on issue_type.id = task.issue_type_id
  left join public.priorities priority on priority.id = task.priority_id
  left join public.user_profiles assignee on assignee.id = task.assignee_id
  left join public.epics epic on epic.id = task.epic_id
  where task.project_id = p_project_id
    and task.in_backlog = false
    and task.column_id is not null
    and (
      (v_effective_scope = 'kanban' and task.sprint_id is null)
      or
      (v_effective_scope = 'sprint' and task.sprint_id = v_active_sprint.id)
    );

  return jsonb_build_object(
    'project', jsonb_build_object(
      'id', v_project.id,
      'organizationId', v_project.organization_id,
      'title', v_project.title,
      'projectKey', v_project.project_key,
      'visibility', v_project.visibility
    ),
    'selectedScope', v_selected_scope,
    'effectiveScope', v_effective_scope,
    'availableScopes', jsonb_build_array(
      jsonb_build_object(
        'id', 'kanban',
        'label', 'Flujo continuo',
        'available', true
      ),
      jsonb_build_object(
        'id', 'sprint',
        'label', coalesce(v_active_sprint.name, 'Sprint'),
        'available', v_active_sprint.id is not null
      )
    ),
    'activeSprint', case
      when v_active_sprint.id is null then null
      else jsonb_build_object(
        'id', v_active_sprint.id,
        'name', v_active_sprint.name,
        'goal', v_active_sprint.goal,
        'status', v_active_sprint.status,
        'startDate', v_active_sprint.start_date,
        'endDate', v_active_sprint.end_date,
        'createdAt', v_active_sprint.created_at,
        'updatedAt', v_active_sprint.updated_at
      )
    end,
    'capabilities', jsonb_build_object(
      'canCreateTask', v_can_mutate,
      'canManageColumns', v_can_mutate,
      'canCompleteSprint', v_can_mutate
        and v_effective_scope = 'sprint'
        and v_active_sprint.id is not null,
      'showSprintCountdown', v_effective_scope = 'sprint'
        and v_active_sprint.id is not null
    ),
    'defaultColumnId', (
      select column_record.id
      from public.columns column_record
      where column_record.project_id = p_project_id
      order by column_record.position, column_record.created_at
      limit 1
    ),
    'columnOrder', v_column_order,
    'columns', v_columns,
    'tasks', v_tasks
  );
end;
$$;

revoke all on function public.get_project_board_view(uuid) from public;
revoke execute on function public.get_project_board_view(uuid) from PUBLIC, anon;
grant execute on function public.get_project_board_view(uuid) to authenticated;

create or replace function public.set_project_board_scope_command(
  p_project_id uuid,
  p_scope text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_scope text := lower(trim(coalesce(p_scope, '')));
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para cambiar la vista del tablero.';
  end if;

  if p_project_id is null or not public.can_view_project(p_project_id) then
    raise exception 'No tienes permisos para consultar este proyecto.';
  end if;

  if v_scope not in ('kanban', 'sprint') then
    raise exception 'El scope del tablero debe ser kanban o sprint.';
  end if;

  if v_scope = 'sprint' and not exists (
    select 1
    from public.sprints sprint
    where sprint.project_id = p_project_id
      and sprint.status = 'active'
  ) then
    raise exception 'No existe un sprint activo para seleccionar esta vista.';
  end if;

  insert into public.user_project_board_preferences (
    user_id,
    project_id,
    selected_scope
  )
  values (
    v_user_id,
    p_project_id,
    v_scope
  )
  on conflict (user_id, project_id)
  do update set
    selected_scope = excluded.selected_scope,
    updated_at = now();

  return public.get_project_board_view(p_project_id);
end;
$$;

revoke all on function public.set_project_board_scope_command(uuid, text) from public;
revoke execute on function public.set_project_board_scope_command(uuid, text) from PUBLIC, anon;
grant execute on function public.set_project_board_scope_command(uuid, text) to authenticated;
