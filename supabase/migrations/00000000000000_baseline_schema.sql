


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."accept_organization_invitation"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_organization_id uuid;
  v_invitee_id uuid;
begin
  select organization_id, invitee_id
    into v_organization_id, v_invitee_id
  from public.organization_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if v_organization_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can accept this invitation';
  end if;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_organization_id, v_invitee_id, 'member')
  on conflict (organization_id, user_id) do nothing;

  update public.organization_invitations
  set status = 'accepted',
      responded_at = now()
  where id = p_invitation_id;

  return v_organization_id;
end;
$$;


ALTER FUNCTION "public"."accept_organization_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_organization_invitation_command"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_organization_id uuid;
  v_invitee_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para responder invitaciones.';
  end if;

  select organization_id, invitee_id
    into v_organization_id, v_invitee_id
  from public.organization_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if v_organization_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can accept this invitation';
  end if;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_organization_id, v_invitee_id, 'member')
  on conflict (organization_id, user_id) do nothing;

  update public.organization_invitations
  set status = 'accepted',
      responded_at = now()
  where id = p_invitation_id;

  insert into public.activity_events (
    organization_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_organization_id,
    v_invitee_id,
    'organization.invitation_accepted',
    jsonb_build_object('invitationId', p_invitation_id, 'organizationId', v_organization_id)
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.organization_invitation_accepted',
    jsonb_build_object(
      'invitationId', p_invitation_id,
      'organizationId', v_organization_id,
      'actorId', v_invitee_id
    )
  );

  return v_organization_id;
end;
$$;


ALTER FUNCTION "public"."accept_organization_invitation_command"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_project_invitation"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_project_id uuid;
  v_invitee_id uuid;
  v_organization_id uuid;
begin
  select invitation.project_id, invitation.invitee_id, project.organization_id
    into v_project_id, v_invitee_id, v_organization_id
  from public.project_invitations invitation
  join public.projects project on project.id = invitation.project_id
  where invitation.id = p_invitation_id
    and invitation.status = 'pending'
  for update;

  if v_project_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can accept this invitation';
  end if;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_organization_id, v_invitee_id, 'member')
  on conflict (organization_id, user_id) do nothing;

  insert into public.project_members (project_id, user_id, role)
  values (v_project_id, v_invitee_id, 'member')
  on conflict (project_id, user_id) do nothing;

  update public.project_invitations
  set status = 'accepted',
      responded_at = now()
  where id = p_invitation_id;

  return v_project_id;
end;
$$;


ALTER FUNCTION "public"."accept_project_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_project_invitation_command"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_project_id uuid;
  v_invitee_id uuid;
  v_organization_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para responder invitaciones.';
  end if;

  select invitation.project_id, invitation.invitee_id, project.organization_id
    into v_project_id, v_invitee_id, v_organization_id
  from public.project_invitations invitation
  join public.projects project on project.id = invitation.project_id
  where invitation.id = p_invitation_id
    and invitation.status = 'pending'
  for update;

  if v_project_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can accept this invitation';
  end if;

  if not exists (
    select 1
    from public.organization_members organization_member
    where organization_member.organization_id = v_organization_id
      and organization_member.user_id = v_invitee_id
  ) then
    raise exception 'Debes pertenecer a la organización antes de aceptar acceso al proyecto.';
  end if;

  insert into public.project_members (project_id, user_id, role)
  values (v_project_id, v_invitee_id, 'member')
  on conflict (project_id, user_id) do nothing;

  update public.project_invitations
  set status = 'accepted',
      responded_at = now()
  where id = p_invitation_id;

  insert into public.activity_events (
    organization_id,
    project_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_organization_id,
    v_project_id,
    v_invitee_id,
    'project.invitation_accepted',
    jsonb_build_object('invitationId', p_invitation_id)
  );

  return v_project_id;
end;
$$;


ALTER FUNCTION "public"."accept_project_invitation_command"("p_invitation_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."project_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "project_members_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'member'::"text"])))
);


ALTER TABLE "public"."project_members" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_project_member_command"("p_project_id" "uuid", "p_user_id" "uuid", "p_role" "text" DEFAULT 'member'::"text") RETURNS "public"."project_members"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_role text := lower(trim(coalesce(p_role, 'member')));
  v_member public.project_members%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Debes iniciar sesión para agregar miembros al proyecto.';
  end if;

  if v_role not in ('owner', 'member') then
    raise exception 'Rol de proyecto inválido.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id
  for update;

  if v_project.id is null then
    raise exception 'Proyecto no encontrado.';
  end if;

  if not public.is_project_owner(p_project_id) then
    raise exception 'Solo owners del proyecto pueden agregar colaboradores.';
  end if;

  if not exists (
    select 1
    from public.organization_members organization_member
    where organization_member.organization_id = v_project.organization_id
      and organization_member.user_id = p_user_id
  ) then
    raise exception 'El usuario debe pertenecer primero a la organización.';
  end if;

  insert into public.project_members (project_id, user_id, role)
  values (p_project_id, p_user_id, v_role)
  returning * into v_member;

  insert into public.activity_events (
    organization_id,
    project_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_project.organization_id,
    p_project_id,
    v_actor_id,
    'project.member_added',
    jsonb_build_object('userId', p_user_id, 'role', v_role)
  );

  return v_member;
exception
  when unique_violation then
    raise exception 'Este usuario ya es miembro del proyecto.';
end;
$$;


ALTER FUNCTION "public"."add_project_member_command"("p_project_id" "uuid", "p_user_id" "uuid", "p_role" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tasks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "column_id" "uuid",
    "title" "text" NOT NULL,
    "description" "text",
    "position" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "issue_type_id" "uuid",
    "priority_id" "uuid",
    "story_points" "text",
    "assignee_id" "uuid",
    "parent_task_id" "uuid",
    "task_id_display" character varying(50),
    "in_backlog" boolean DEFAULT false NOT NULL,
    "project_id" "uuid",
    "github_link" "text",
    "epic_id" "uuid",
    "sprint_id" "uuid",
    "subtitle" "text",
    "planned_start_date" "date",
    "planned_end_date" "date"
);

ALTER TABLE ONLY "public"."tasks" REPLICA IDENTITY FULL;


ALTER TABLE "public"."tasks" OWNER TO "postgres";


COMMENT ON COLUMN "public"."tasks"."issue_type_id" IS 'Tipo de issue';



COMMENT ON COLUMN "public"."tasks"."priority_id" IS 'Nivel de prioridad';



COMMENT ON COLUMN "public"."tasks"."story_points" IS 'Puntos de historia estimados';



COMMENT ON COLUMN "public"."tasks"."assignee_id" IS 'Usuario asignado a la tarea';



COMMENT ON COLUMN "public"."tasks"."parent_task_id" IS 'Tarea padre (para subtareas)';



COMMENT ON COLUMN "public"."tasks"."task_id_display" IS 'ID visual de la tarea (ej: PIANOLRN-1)';



COMMENT ON COLUMN "public"."tasks"."in_backlog" IS 'Si es true, la tarea está en el backlog (no en Kanban)';



COMMENT ON COLUMN "public"."tasks"."project_id" IS 'Proyecto al que pertenece la tarea (especialmente para tareas en backlog)';



COMMENT ON COLUMN "public"."tasks"."github_link" IS 'Enlace al issue o PR de GitHub asociado';



COMMENT ON COLUMN "public"."tasks"."epic_id" IS 'Épica asociada a esta tarea';



COMMENT ON COLUMN "public"."tasks"."sprint_id" IS 'Sprint al que pertenece la tarea (NULL si está en backlog)';



COMMENT ON COLUMN "public"."tasks"."subtitle" IS 'Subtítulo corto mostrado en tarjetas y backlog';



COMMENT ON COLUMN "public"."tasks"."planned_start_date" IS 'Planned start date used by roadmap timeline task bars.';



COMMENT ON COLUMN "public"."tasks"."planned_end_date" IS 'Planned end date used by roadmap timeline task bars.';



CREATE OR REPLACE FUNCTION "public"."assign_task_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_assignee_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."tasks"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_previous_assignee uuid;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para asignar tareas.';
  end if;

  if p_project_id is null or not public.can_edit_project(p_project_id) then
    raise exception 'No tienes permisos para asignar tareas en este proyecto.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  select assignee_id
    into v_previous_assignee
  from public.tasks
  where id = p_task_id
    and project_id = p_project_id
  for update;

  if not found then
    raise exception 'La tarea no pertenece al proyecto activo.';
  end if;

  if p_assignee_id is not null and not exists (
    select 1
    from public.project_members member
    where member.project_id = p_project_id
      and member.user_id = p_assignee_id
  ) then
    raise exception 'Solo puedes asignar tareas a miembros del proyecto.';
  end if;

  update public.tasks
  set
    assignee_id = p_assignee_id,
    updated_at = now()
  where id = p_task_id
    and project_id = p_project_id
  returning * into v_task;

  if p_assignee_id is distinct from v_previous_assignee then
    insert into public.activity_events (
      organization_id,
      project_id,
      sprint_id,
      task_id,
      actor_id,
      event_type,
      payload
    )
    values (
      v_project.organization_id,
      p_project_id,
      v_task.sprint_id,
      v_task.id,
      v_user_id,
      'task.assigned',
      jsonb_build_object(
        'previous_assignee_id', v_previous_assignee,
        'assignee_id', p_assignee_id,
        'task_id_display', v_task.task_id_display
      )
    );

    perform public.enqueue_command_job(
      'nexusplanner-events',
      'notification.task_assigned',
      jsonb_build_object(
        'project_id', p_project_id,
        'task_id', v_task.id,
        'actor_id', v_user_id,
        'assignee_id', p_assignee_id
      )
    );
  end if;

  return v_task;
end;
$$;


ALTER FUNCTION "public"."assign_task_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_assignee_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."activity_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "project_id" "uuid",
    "sprint_id" "uuid",
    "task_id" "uuid",
    "actor_id" "uuid",
    "event_type" "text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "event_key" "text"
);


ALTER TABLE "public"."activity_events" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."automation_condition_matches"("p_condition" "jsonb", "p_event" "public"."activity_events") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_field text := coalesce(p_condition->>'field', '');
  v_operator text := lower(coalesce(p_condition->>'operator', 'equals'));
  v_expected text := coalesce(p_condition->>'value', '');
  v_actual text := public.automation_event_value(p_event, v_field);
begin
  if coalesce(p_condition->>'type', 'field') = 'always' then
    return true;
  end if;

  if v_operator in ('equals', 'eq') then
    return coalesce(v_actual, '') = v_expected;
  elsif v_operator in ('not_equals', 'neq') then
    return coalesce(v_actual, '') <> v_expected;
  elsif v_operator = 'contains' then
    return position(lower(v_expected) in lower(coalesce(v_actual, ''))) > 0;
  elsif v_operator = 'not_empty' then
    return nullif(trim(coalesce(v_actual, '')), '') is not null;
  elsif v_operator = 'empty' then
    return nullif(trim(coalesce(v_actual, '')), '') is null;
  end if;

  return false;
end;
$$;


ALTER FUNCTION "public"."automation_condition_matches"("p_condition" "jsonb", "p_event" "public"."activity_events") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."automation_event_value"("p_event" "public"."activity_events", "p_field" "text") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_field text := trim(coalesce(p_field, ''));
begin
  if v_field = 'event_type' then
    return p_event.event_type;
  elsif v_field = 'project_id' then
    return p_event.project_id::text;
  elsif v_field = 'organization_id' then
    return p_event.organization_id::text;
  elsif v_field = 'task_id' then
    return p_event.task_id::text;
  elsif v_field = 'sprint_id' then
    return p_event.sprint_id::text;
  elsif v_field = 'actor_id' then
    return p_event.actor_id::text;
  elsif v_field = 'payload' then
    return p_event.payload::text;
  elsif v_field <> '' then
    return p_event.payload #>> string_to_array(v_field, '.');
  end if;

  return null;
end;
$$;


ALTER FUNCTION "public"."automation_event_value"("p_event" "public"."activity_events", "p_field" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."automation_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "enabled" boolean DEFAULT true NOT NULL,
    "trigger_event" "text" NOT NULL,
    "conditions" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "actions" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_run_at" timestamp with time zone,
    CONSTRAINT "automation_rules_actions_array" CHECK (("jsonb_typeof"("actions") = 'array'::"text")),
    CONSTRAINT "automation_rules_conditions_array" CHECK (("jsonb_typeof"("conditions") = 'array'::"text")),
    CONSTRAINT "automation_rules_name_not_empty" CHECK (("btrim"("name") <> ''::"text")),
    CONSTRAINT "automation_rules_trigger_event_not_empty" CHECK (("btrim"("trigger_event") <> ''::"text"))
);


ALTER TABLE "public"."automation_rules" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."automation_rule_matches_event"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_condition jsonb;
begin
  if p_rule.enabled is not true then
    return false;
  end if;

  if p_rule.project_id <> p_event.project_id then
    return false;
  end if;

  if p_rule.trigger_event <> p_event.event_type then
    return false;
  end if;

  for v_condition in
    select value
    from jsonb_array_elements(coalesce(p_rule.conditions, '[]'::jsonb))
  loop
    if not public.automation_condition_matches(v_condition, p_event) then
      return false;
    end if;
  end loop;

  return true;
end;
$$;


ALTER FUNCTION "public"."automation_rule_matches_event"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_add_project_member"("p_project_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.projects project
    where project.id = p_project_id
      and public.can_manage_project(project.id)
      and exists (
        select 1
        from public.organization_members organization_member
        where organization_member.organization_id = project.organization_id
          and organization_member.user_id = p_user_id
      )
      and not exists (
        select 1
        from public.project_members project_member
        where project_member.project_id = project.id
          and project_member.user_id = p_user_id
      )
  );
$$;


ALTER FUNCTION "public"."can_add_project_member"("p_project_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_assign_project_user"("p_project_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select p_user_id is null
    or exists (
      select 1
      from public.project_members member
      where member.project_id = p_project_id
        and member.user_id = p_user_id
    );
$$;


ALTER FUNCTION "public"."can_assign_project_user"("p_project_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_create_project_in_organization"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_view_organization(p_organization_id);
$$;


ALTER FUNCTION "public"."can_create_project_in_organization"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_edit_project"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_mutate_project(p_project_id);
$$;


ALTER FUNCTION "public"."can_edit_project"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_invite_to_organization"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_manage_organization(p_organization_id);
$$;


ALTER FUNCTION "public"."can_invite_to_organization"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_invite_to_project"("p_project_id" "uuid", "p_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_add_project_member(p_project_id, p_user_id);
$$;


ALTER FUNCTION "public"."can_invite_to_project"("p_project_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_manage_organization"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(public.current_organization_role(p_organization_id), '') in ('owner', 'admin');
$$;


ALTER FUNCTION "public"."can_manage_organization"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_manage_project"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(public.current_project_role(p_project_id), '') = 'owner';
$$;


ALTER FUNCTION "public"."can_manage_project"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_mutate_project"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.current_project_role(p_project_id) is not null;
$$;


ALTER FUNCTION "public"."can_mutate_project"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_organization"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.current_organization_role(p_organization_id) is not null;
$$;


ALTER FUNCTION "public"."can_view_organization"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_project"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.projects project
    where project.id = p_project_id
      and (
        public.current_project_role(project.id) is not null
        or (
          project.visibility = 'organization'
          and public.can_view_organization(project.organization_id)
        )
      )
  );
$$;


ALTER FUNCTION "public"."can_view_project"("p_project_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."command_jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "queue_name" "text" NOT NULL,
    "job_type" "text" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'queued'::"text" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "last_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "available_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    "max_attempts" integer DEFAULT 5 NOT NULL,
    "locked_at" timestamp with time zone,
    "locked_by" "text",
    "job_key" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "command_jobs_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'processing'::"text", 'done'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."command_jobs" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_command_jobs"("p_queue_name" "text", "p_limit" integer DEFAULT 10, "p_worker_id" "text" DEFAULT NULL::"text") RETURNS SETOF "public"."command_jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if nullif(trim(coalesce(p_queue_name, '')), '') is null then
    raise exception 'queue_name is required';
  end if;

  return query
  with picked as (
    select job.id
    from public.command_jobs job
    where job.queue_name = trim(p_queue_name)
      and job.status in ('queued', 'failed')
      and job.available_at <= now()
      and job.attempts < job.max_attempts
    order by job.available_at asc, job.created_at asc
    limit least(greatest(coalesce(p_limit, 10), 1), 50)
    for update skip locked
  )
  update public.command_jobs job
  set
    status = 'processing',
    attempts = job.attempts + 1,
    locked_at = now(),
    locked_by = nullif(trim(coalesce(p_worker_id, '')), ''),
    last_error = null,
    updated_at = now()
  from picked
  where job.id = picked.id
  returning job.*;
end;
$$;


ALTER FUNCTION "public"."claim_command_jobs"("p_queue_name" "text", "p_limit" integer, "p_worker_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_command_job"("p_job_id" "uuid", "p_worker_id" "text" DEFAULT NULL::"text") RETURNS "public"."command_jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_job public.command_jobs%rowtype;
begin
  update public.command_jobs job
  set
    status = 'done',
    processed_at = now(),
    locked_at = null,
    locked_by = null,
    last_error = null,
    updated_at = now()
  where job.id = p_job_id
    and job.status = 'processing'
    and (
      nullif(trim(coalesce(p_worker_id, '')), '') is null
      or job.locked_by = nullif(trim(coalesce(p_worker_id, '')), '')
    )
  returning job.* into v_job;

  if v_job.id is null then
    raise exception 'No processing command job found for completion.';
  end if;

  return v_job;
end;
$$;


ALTER FUNCTION "public"."complete_command_job"("p_job_id" "uuid", "p_worker_id" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sprints" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "goal" "text",
    "status" "text" DEFAULT 'future'::"text" NOT NULL,
    "start_date" timestamp with time zone,
    "end_date" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sprints_date_order_check" CHECK ((("end_date" IS NULL) OR (("start_date" IS NOT NULL) AND ("end_date" > "start_date")))),
    CONSTRAINT "sprints_status_check" CHECK (("status" = ANY (ARRAY['future'::"text", 'active'::"text", 'closed'::"text"])))
);


ALTER TABLE "public"."sprints" OWNER TO "postgres";


COMMENT ON TABLE "public"."sprints" IS 'Sprints asociados a proyectos. Solo un sprint puede estar activo por proyecto.';



COMMENT ON COLUMN "public"."sprints"."name" IS 'Nombre identificador del sprint';



COMMENT ON COLUMN "public"."sprints"."goal" IS 'Objetivo del sprint (descripción del propósito)';



COMMENT ON COLUMN "public"."sprints"."status" IS 'Estado: future (planificado), active (en ejecución), closed (finalizado)';



COMMENT ON COLUMN "public"."sprints"."start_date" IS 'Fecha de inicio del sprint (cuando pasa a active)';



COMMENT ON COLUMN "public"."sprints"."end_date" IS 'Fecha de fin del sprint (límite del timebox)';



CREATE OR REPLACE FUNCTION "public"."complete_sprint_command"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_dispositions" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "public"."sprints"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_sprint public.sprints%rowtype;
  v_first_column_id uuid;
  v_completed_tasks integer := 0;
  v_incomplete_tasks integer := 0;
  v_disposition_count integer;
  v_invalid_disposition_count integer;
  v_task record;
  v_action text;
  v_target_sprint_id uuid;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para completar sprints.';
  end if;

  if p_project_id is null or not public.can_edit_project(p_project_id) then
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

  select count(*)
    into v_disposition_count
  from jsonb_array_elements(coalesce(p_dispositions, '[]'::jsonb)) disposition
  where (disposition->>'taskId')::uuid in (select task_id from tmp_incomplete_tasks);

  if v_disposition_count <> v_incomplete_tasks then
    raise exception 'Cada tarea incompleta necesita una decisión antes de completar el sprint.';
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

  select id
    into v_first_column_id
  from public.columns
  where project_id = p_project_id
  order by position asc
  limit 1;

  for v_task in
    select
      disposition,
      (disposition->>'taskId')::uuid as task_id
    from jsonb_array_elements(coalesce(p_dispositions, '[]'::jsonb)) disposition
  loop
    v_action := coalesce(v_task.disposition->>'destination', v_task.disposition->>'action');
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

  insert into public.activity_events (
    organization_id,
    project_id,
    sprint_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_project.organization_id,
    p_project_id,
    p_sprint_id,
    v_user_id,
    'sprint.completed',
    jsonb_build_object(
      'completed_tasks', v_completed_tasks,
      'incomplete_tasks', v_incomplete_tasks,
      'dispositions', coalesce(p_dispositions, '[]'::jsonb)
    )
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'report.sprint_completed',
    jsonb_build_object(
      'job_key', 'report.sprint_completed:' || p_sprint_id::text,
      'project_id', p_project_id,
      'sprint_id', p_sprint_id,
      'actor_id', v_user_id
    )
  );

  return v_sprint;
end;
$$;


ALTER FUNCTION "public"."complete_sprint_command"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_dispositions" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_command"("p_name" "text", "p_logo_url" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_organization public.organizations%rowtype;
  v_name text := trim(coalesce(p_name, ''));
  v_logo_url text := nullif(trim(coalesce(p_logo_url, '')), '');
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear una organización.';
  end if;

  if v_name = '' then
    raise exception 'El nombre de la organización es obligatorio.';
  end if;

  insert into public.organizations (name, logo_url, created_by)
  values (v_name, v_logo_url, v_user_id)
  returning * into v_organization;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_organization.id, v_user_id, 'owner');

  insert into public.activity_events (
    organization_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_organization.id,
    v_user_id,
    'organization.created',
    jsonb_build_object('organizationId', v_organization.id, 'name', v_organization.name)
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.organization_created',
    jsonb_build_object('organizationId', v_organization.id, 'actorId', v_user_id)
  );

  return to_jsonb(v_organization) || jsonb_build_object('role', 'owner');
end;
$$;


ALTER FUNCTION "public"."create_organization_command"("p_name" "text", "p_logo_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_invitation_command"("p_organization_id" "uuid", "p_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
declare
  v_inviter_id uuid := auth.uid();
  v_invitee_id uuid;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_invitation_id uuid;
begin
  if v_inviter_id is null then
    raise exception 'Debes iniciar sesión para invitar personas.';
  end if;

  if p_organization_id is null then
    raise exception 'La organización es obligatoria.';
  end if;

  if v_email = '' then
    raise exception 'El correo es obligatorio.';
  end if;

  if v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Escribe un correo válido.';
  end if;

  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Solo owner/admin pueden invitar personas a la organización.';
  end if;

  select users.id
    into v_invitee_id
  from auth.users users
  where lower(users.email) = v_email
  limit 1;

  if v_invitee_id is null then
    raise exception 'No encontramos una cuenta registrada con ese correo.';
  end if;

  if v_invitee_id = v_inviter_id then
    raise exception 'No puedes invitarte a ti misma a la organización.';
  end if;

  if exists (
    select 1
    from public.organization_members member
    where member.organization_id = p_organization_id
      and member.user_id = v_invitee_id
  ) then
    raise exception 'Este usuario ya pertenece a la organización.';
  end if;

  insert into public.organization_invitations (
    organization_id,
    inviter_id,
    invitee_id
  )
  values (
    p_organization_id,
    v_inviter_id,
    v_invitee_id
  )
  returning id into v_invitation_id;

  insert into public.activity_events (
    organization_id,
    actor_id,
    event_type,
    payload
  )
  values (
    p_organization_id,
    v_inviter_id,
    'organization.invitation_created',
    jsonb_build_object(
      'invitationId', v_invitation_id,
      'organizationId', p_organization_id,
      'inviteeId', v_invitee_id
    )
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'notification.organization_invitation_created',
    jsonb_build_object(
      'invitationId', v_invitation_id,
      'organizationId', p_organization_id,
      'inviteeId', v_invitee_id,
      'actorId', v_inviter_id
    )
  );

  return v_invitation_id;
exception
  when unique_violation then
    raise exception 'Este usuario ya tiene una invitación pendiente.';
end;
$_$;


ALTER FUNCTION "public"."create_organization_invitation_command"("p_organization_id" "uuid", "p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_invitation_for_user_command"("p_organization_id" "uuid", "p_invitee_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_inviter_id uuid := auth.uid();
  v_invitation_id uuid;
begin
  if v_inviter_id is null then
    raise exception 'Debes iniciar sesión para invitar personas.';
  end if;

  if p_organization_id is null then
    raise exception 'La organización es obligatoria.';
  end if;

  if p_invitee_id is null then
    raise exception 'El usuario invitado es obligatorio.';
  end if;

  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Solo owner/admin pueden invitar personas a la organización.';
  end if;

  if p_invitee_id = v_inviter_id then
    raise exception 'No puedes invitarte a ti misma a la organización.';
  end if;

  if exists (
    select 1
    from public.organization_members member
    where member.organization_id = p_organization_id
      and member.user_id = p_invitee_id
  ) then
    raise exception 'Este usuario ya pertenece a la organización.';
  end if;

  insert into public.organization_invitations (
    organization_id,
    inviter_id,
    invitee_id
  )
  values (
    p_organization_id,
    v_inviter_id,
    p_invitee_id
  )
  returning id into v_invitation_id;

  insert into public.activity_events (
    organization_id,
    actor_id,
    event_type,
    payload
  )
  values (
    p_organization_id,
    v_inviter_id,
    'organization.invitation_created',
    jsonb_build_object(
      'invitationId', v_invitation_id,
      'organizationId', p_organization_id,
      'inviteeId', p_invitee_id
    )
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'notification.organization_invitation_created',
    jsonb_build_object(
      'invitationId', v_invitation_id,
      'organizationId', p_organization_id,
      'inviteeId', p_invitee_id,
      'actorId', v_inviter_id
    )
  );

  return v_invitation_id;
exception
  when unique_violation then
    raise exception 'Este usuario ya tiene una invitación pendiente.';
end;
$$;


ALTER FUNCTION "public"."create_organization_invitation_for_user_command"("p_organization_id" "uuid", "p_invitee_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_member_added_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_organization public.organizations%rowtype;
begin
  select *
    into v_organization
  from public.organizations
  where id = new.organization_id;

  perform public.create_user_notification(
    new.user_id,
    'organization_member_added',
    'Nuevo acceso a organización',
    'Ahora perteneces a ' || coalesce(v_organization.name, 'esta organización') || '.',
    v_actor_id,
    new.organization_id,
    null,
    null,
    jsonb_build_object(
      'organizationId', new.organization_id,
      'organizationName', v_organization.name,
      'role', new.role
    ),
    'organization_member_added:' || new.id::text,
    true
  );

  return new;
end;
$$;


ALTER FUNCTION "public"."create_organization_member_added_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_with_owner"("p_name" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_organization public.organizations%rowtype;
  v_name text := trim(coalesce(p_name, ''));
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear una organización.';
  end if;

  if v_name = '' then
    raise exception 'El nombre de la organización es obligatorio.';
  end if;

  insert into public.organizations (name, created_by)
  values (v_name, v_user_id)
  returning * into v_organization;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_organization.id, v_user_id, 'owner');

  return to_jsonb(v_organization) || jsonb_build_object('role', 'owner');
end;
$$;


ALTER FUNCTION "public"."create_organization_with_owner"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_project_command"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[] DEFAULT ARRAY[]::"text"[], "p_visibility" "text" DEFAULT 'organization'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_column_ids uuid[];
  v_normalized_key text := upper(trim(coalesce(p_project_key, '')));
  v_tags text[];
  v_visibility text := coalesce(nullif(trim(p_visibility), ''), 'organization');
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear un proyecto.';
  end if;

  if p_organization_id is null or not public.is_organization_member(p_organization_id) then
    raise exception 'Debes seleccionar una organización válida.';
  end if;

  if v_visibility not in ('organization', 'private') then
    raise exception 'Visibilidad de proyecto inválida.';
  end if;

  if trim(coalesce(p_title, '')) = '' then
    raise exception 'El nombre del proyecto es obligatorio.';
  end if;

  if v_normalized_key = '' then
    raise exception 'Las siglas del proyecto son obligatorias.';
  end if;

  if v_normalized_key !~ '^[A-Z0-9]{2,10}$' then
    raise exception 'Las siglas deben tener entre 2 y 10 caracteres (solo mayúsculas y números).';
  end if;

  if exists (
    select 1
    from public.projects
    where upper(project_key) = v_normalized_key
  ) then
    raise exception 'Las siglas "%" ya están en uso por otro proyecto.', v_normalized_key
      using errcode = '23505';
  end if;

  select coalesce(array_agg(distinct normalized_tag order by normalized_tag), array[]::text[])
  into v_tags
  from (
    select trim(tag_value) as normalized_tag
    from unnest(coalesce(p_tags, array[]::text[])) as tags(tag_value)
    where trim(tag_value) <> ''
  ) normalized_tags;

  insert into public.projects (
    user_id,
    organization_id,
    title,
    description,
    project_key,
    task_sequence,
    epic_sequence,
    visibility
  )
  values (
    v_user_id,
    p_organization_id,
    trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''),
    v_normalized_key,
    0,
    0,
    v_visibility
  )
  returning * into v_project;

  insert into public.project_members (project_id, user_id, role)
  values (v_project.id, v_user_id, 'owner');

  if array_length(v_tags, 1) > 0 then
    insert into public.project_tags (project_id, tag)
    select v_project.id, tag
    from unnest(v_tags) as tags(tag);
  end if;

  with inserted_columns as (
    insert into public.columns (project_id, name, position)
    values
      (v_project.id, 'Por hacer', 0),
      (v_project.id, 'En progreso', 1),
      (v_project.id, 'En revisión', 2),
      (v_project.id, 'Hecho', 3)
    returning id, position
  )
  select array_agg(id order by position)
  into v_column_ids
  from inserted_columns;

  if coalesce(array_length(v_column_ids, 1), 0) <> 4 then
    raise exception 'No se pudieron crear las columnas iniciales del proyecto.';
  end if;

  insert into public.column_order (project_id, column_ids)
  values (v_project.id, to_jsonb(v_column_ids))
  on conflict (project_id) do update
  set column_ids = excluded.column_ids;

  insert into public.activity_events (
    organization_id,
    project_id,
    actor_id,
    event_type,
    payload
  )
  values (
    p_organization_id,
    v_project.id,
    v_user_id,
    'project.created',
    jsonb_build_object(
      'projectId', v_project.id,
      'organizationId', p_organization_id,
      'projectKey', v_project.project_key,
      'title', v_project.title
    )
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.project_created',
    jsonb_build_object(
      'projectId', v_project.id,
      'organizationId', p_organization_id,
      'actorId', v_user_id
    )
  );

  return to_jsonb(v_project) || jsonb_build_object('tags', to_jsonb(v_tags));
end;
$_$;


ALTER FUNCTION "public"."create_project_command"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_project_invitation_command"("p_project_id" "uuid", "p_invitee_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_inviter_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_invitation_id uuid;
begin
  if v_inviter_id is null then
    raise exception 'Debes iniciar sesión para invitar personas al proyecto.';
  end if;

  if p_invitee_id is null then
    raise exception 'El usuario invitado es obligatorio.';
  end if;

  if p_invitee_id = v_inviter_id then
    raise exception 'No puedes invitarte a ti misma al proyecto.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id
  for update;

  if v_project.id is null then
    raise exception 'Proyecto no encontrado.';
  end if;

  if not public.is_project_owner(p_project_id) then
    raise exception 'Solo owners del proyecto pueden invitar colaboradores.';
  end if;

  if not exists (
    select 1
    from public.organization_members organization_member
    where organization_member.organization_id = v_project.organization_id
      and organization_member.user_id = p_invitee_id
  ) then
    raise exception 'El usuario debe pertenecer primero a la organización.';
  end if;

  if exists (
    select 1
    from public.project_members project_member
    where project_member.project_id = p_project_id
      and project_member.user_id = p_invitee_id
  ) then
    raise exception 'Este usuario ya es miembro del proyecto.';
  end if;

  insert into public.project_invitations (
    project_id,
    inviter_id,
    invitee_id
  )
  values (
    p_project_id,
    v_inviter_id,
    p_invitee_id
  )
  returning id into v_invitation_id;

  insert into public.activity_events (
    organization_id,
    project_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_project.organization_id,
    p_project_id,
    v_inviter_id,
    'project.invitation_created',
    jsonb_build_object('invitationId', v_invitation_id, 'inviteeId', p_invitee_id)
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'notification.project_invitation_created',
    jsonb_build_object(
      'invitationId', v_invitation_id,
      'projectId', p_project_id,
      'inviteeId', p_invitee_id,
      'actorId', v_inviter_id
    )
  );

  return v_invitation_id;
exception
  when unique_violation then
    raise exception 'Este usuario ya tiene una invitación pendiente.';
end;
$$;


ALTER FUNCTION "public"."create_project_invitation_command"("p_project_id" "uuid", "p_invitee_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_project_member_added_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_project public.projects%rowtype;
begin
  select *
    into v_project
  from public.projects
  where id = new.project_id;

  perform public.create_user_notification(
    new.user_id,
    'project_member_added',
    'Nuevo acceso a proyecto',
    'Te agregaron al proyecto ' || coalesce(v_project.title, 'sin nombre') || '.',
    v_actor_id,
    v_project.organization_id,
    new.project_id,
    null,
    jsonb_build_object(
      'projectId', new.project_id,
      'projectTitle', v_project.title,
      'role', new.role
    ),
    'project_member_added:' || new.id::text,
    true
  );

  return new;
end;
$$;


ALTER FUNCTION "public"."create_project_member_added_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_project_with_defaults"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[] DEFAULT ARRAY[]::"text"[], "p_visibility" "text" DEFAULT 'organization'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_column_ids uuid[];
  v_normalized_key text := upper(trim(coalesce(p_project_key, '')));
  v_tags text[];
  v_visibility text := coalesce(nullif(trim(p_visibility), ''), 'organization');
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear un proyecto.';
  end if;

  if p_organization_id is null or not public.is_organization_member(p_organization_id) then
    raise exception 'Debes seleccionar una organización válida.';
  end if;

  if v_visibility not in ('organization', 'private') then
    raise exception 'Visibilidad de proyecto inválida.';
  end if;

  if trim(coalesce(p_title, '')) = '' then
    raise exception 'El nombre del proyecto es obligatorio.';
  end if;

  if v_normalized_key = '' then
    raise exception 'Las siglas del proyecto son obligatorias.';
  end if;

  if v_normalized_key !~ '^[A-Z0-9]{2,10}$' then
    raise exception 'Las siglas deben tener entre 2 y 10 caracteres (solo mayúsculas y números).';
  end if;

  if exists (
    select 1
    from public.projects
    where upper(project_key) = v_normalized_key
  ) then
    raise exception 'Las siglas "%" ya están en uso por otro proyecto.', v_normalized_key
      using errcode = '23505';
  end if;

  select coalesce(array_agg(distinct normalized_tag order by normalized_tag), array[]::text[])
  into v_tags
  from (
    select trim(tag_value) as normalized_tag
    from unnest(coalesce(p_tags, array[]::text[])) as tags(tag_value)
    where trim(tag_value) <> ''
  ) normalized_tags;

  insert into public.projects (
    user_id,
    organization_id,
    title,
    description,
    project_key,
    task_sequence,
    epic_sequence,
    visibility
  )
  values (
    v_user_id,
    p_organization_id,
    trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''),
    v_normalized_key,
    0,
    0,
    v_visibility
  )
  returning * into v_project;

  insert into public.project_members (
    project_id,
    user_id,
    role
  )
  values (
    v_project.id,
    v_user_id,
    'owner'
  );

  if array_length(v_tags, 1) > 0 then
    insert into public.project_tags (
      project_id,
      tag
    )
    select v_project.id, tag
    from unnest(v_tags) as tags(tag);
  end if;

  with inserted_columns as (
    insert into public.columns (
      project_id,
      name,
      position
    )
    values
      (v_project.id, 'Por hacer', 0),
      (v_project.id, 'En progreso', 1),
      (v_project.id, 'En revisión', 2),
      (v_project.id, 'Hecho', 3)
    returning id, position
  )
  select array_agg(id order by position)
  into v_column_ids
  from inserted_columns;

  if coalesce(array_length(v_column_ids, 1), 0) <> 4 then
    raise exception 'No se pudieron crear las columnas iniciales del proyecto.';
  end if;

  insert into public.column_order (
    project_id,
    column_ids
  )
  values (
    v_project.id,
    to_jsonb(v_column_ids)
  )
  on conflict (project_id) do update
  set column_ids = excluded.column_ids;

  return to_jsonb(v_project) || jsonb_build_object('tags', to_jsonb(v_tags));
end;
$_$;


ALTER FUNCTION "public"."create_project_with_defaults"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_sprint_completed_notifications"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_member record;
begin
  if new.status <> 'closed' then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status is not distinct from new.status then
    return new;
  end if;

  select *
    into v_project
  from public.projects
  where id = new.project_id;

  for v_member in
    select project_member.user_id
    from public.project_members project_member
    where project_member.project_id = new.project_id
  loop
    perform public.create_user_notification(
      v_member.user_id,
      'sprint_completed',
      'Sprint completado',
      'Se cerró el sprint ' || coalesce(new.name, 'sin nombre') || '.',
      v_actor_id,
      v_project.organization_id,
      new.project_id,
      null,
      jsonb_build_object(
        'projectId', new.project_id,
        'projectTitle', v_project.title,
        'sprintId', new.id,
        'sprintName', new.name
      ),
      'sprint_completed:' || new.id::text || ':' || v_member.user_id::text,
      true
    );
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "public"."create_sprint_completed_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_task_assignment_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid;
  v_project public.projects%rowtype;
  v_task_label text;
begin
  if new.assignee_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.assignee_id is not distinct from old.assignee_id then
    return new;
  end if;

  begin
    v_actor_id := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  exception
    when others then
      v_actor_id := null;
  end;

  if v_actor_id is null then
    v_actor_id := auth.uid();
  end if;

  select *
    into v_project
  from public.projects
  where id = new.project_id;

  v_task_label := coalesce(new.task_id_display, new.title, 'tarea');

  perform public.create_user_notification(
    new.assignee_id,
    'task_assigned',
    'Ticket asignado',
    'Te asignaron ' || v_task_label || coalesce(' en ' || v_project.title, ''),
    v_actor_id,
    v_project.organization_id,
    new.project_id,
    new.id,
    jsonb_build_object(
      'taskId', new.id,
      'taskIdDisplay', new.task_id_display,
      'taskTitle', new.title,
      'projectId', new.project_id,
      'projectTitle', v_project.title
    ),
    null,
    true
  );

  return new;
end;
$$;


ALTER FUNCTION "public"."create_task_assignment_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_task_command"("p_project_id" "uuid", "p_title" "text", "p_subtitle" "text" DEFAULT NULL::"text", "p_description" "text" DEFAULT NULL::"text", "p_destination" "text" DEFAULT 'backlog'::"text", "p_column_id" "uuid" DEFAULT NULL::"uuid", "p_sprint_id" "uuid" DEFAULT NULL::"uuid", "p_position" integer DEFAULT 0, "p_issue_type_id" "uuid" DEFAULT NULL::"uuid", "p_priority_id" "uuid" DEFAULT NULL::"uuid", "p_story_points" "text" DEFAULT NULL::"text", "p_assignee_id" "uuid" DEFAULT NULL::"uuid", "p_epic_id" "uuid" DEFAULT NULL::"uuid", "p_github_link" "text" DEFAULT NULL::"text") RETURNS "public"."tasks"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_next_sequence integer;
  v_destination text := coalesce(nullif(trim(p_destination), ''), 'backlog');
  v_in_backlog boolean;
  v_column_id uuid := p_column_id;
  v_sprint_id uuid := p_sprint_id;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión para crear tareas.';
  end if;

  if p_project_id is null or not public.can_edit_project(p_project_id) then
    raise exception 'No tienes permisos para crear tareas en este proyecto.';
  end if;

  if trim(coalesce(p_title, '')) = '' then
    raise exception 'El título de la tarea es obligatorio.';
  end if;

  if v_destination not in ('backlog', 'scrum') then
    raise exception 'Destino de tarea inválido.';
  end if;

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
      select id
        into v_column_id
      from public.columns
      where project_id = p_project_id
      order by position asc
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

    if v_sprint_id is not null and not exists (
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

  insert into public.activity_events (
    organization_id,
    project_id,
    sprint_id,
    task_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_project.organization_id,
    p_project_id,
    v_sprint_id,
    v_task.id,
    v_user_id,
    'task.created',
    jsonb_build_object(
      'destination', v_destination,
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
    )
  );

  perform public.enqueue_command_job(
    'nexusplanner-events',
    'activity.task_created',
    jsonb_build_object(
      'project_id', p_project_id,
      'task_id', v_task.id,
      'actor_id', v_user_id
    )
  );

  return v_task;
end;
$$;


ALTER FUNCTION "public"."create_task_command"("p_project_id" "uuid", "p_title" "text", "p_subtitle" "text", "p_description" "text", "p_destination" "text", "p_column_id" "uuid", "p_sprint_id" "uuid", "p_position" integer, "p_issue_type_id" "uuid", "p_priority_id" "uuid", "p_story_points" "text", "p_assignee_id" "uuid", "p_epic_id" "uuid", "p_github_link" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "actor_id" "uuid",
    "project_id" "uuid",
    "task_id" "uuid",
    "type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid",
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "dedupe_key" "text",
    CONSTRAINT "user_notifications_type_check" CHECK (("type" = ANY (ARRAY['task_assigned'::"text", 'project_member_added'::"text", 'organization_member_added'::"text", 'sprint_completed'::"text", 'sprint_due_soon'::"text", 'sprint_overdue'::"text", 'automation_rule'::"text"])))
);

ALTER TABLE ONLY "public"."user_notifications" REPLICA IDENTITY FULL;


ALTER TABLE "public"."user_notifications" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_user_notification"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_message" "text", "p_actor_id" "uuid" DEFAULT NULL::"uuid", "p_organization_id" "uuid" DEFAULT NULL::"uuid", "p_project_id" "uuid" DEFAULT NULL::"uuid", "p_task_id" "uuid" DEFAULT NULL::"uuid", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_dedupe_key" "text" DEFAULT NULL::"text", "p_skip_if_actor" boolean DEFAULT true) RETURNS "public"."user_notifications"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := coalesce(p_actor_id, auth.uid());
  v_type text := lower(trim(coalesce(p_type, '')));
  v_title text := trim(coalesce(p_title, ''));
  v_message text := trim(coalesce(p_message, ''));
  v_organization_id uuid := p_organization_id;
  v_project_organization_id uuid;
  v_task_project_id uuid;
  v_notification public.user_notifications%rowtype;
begin
  if p_user_id is null then
    raise exception 'Notification recipient is required.';
  end if;

  if p_skip_if_actor and v_actor_id is not null and p_user_id = v_actor_id then
    return null;
  end if;

  if v_type not in (
    'task_assigned',
    'project_member_added',
    'organization_member_added',
    'sprint_completed',
    'sprint_due_soon',
    'sprint_overdue',
    'automation_rule'
  ) then
    raise exception 'Unsupported notification type: %', v_type;
  end if;

  if v_title = '' then
    raise exception 'Notification title is required.';
  end if;

  if v_message = '' then
    raise exception 'Notification message is required.';
  end if;

  if p_project_id is not null then
    select project.organization_id
      into v_project_organization_id
    from public.projects project
    where project.id = p_project_id;

    if v_project_organization_id is null then
      raise exception 'Notification project does not exist.';
    end if;

    if v_organization_id is null then
      v_organization_id := v_project_organization_id;
    elsif v_organization_id <> v_project_organization_id then
      raise exception 'Notification organization does not match project.';
    end if;
  end if;

  if p_task_id is not null then
    select task.project_id
      into v_task_project_id
    from public.tasks task
    where task.id = p_task_id;

    if v_task_project_id is null then
      raise exception 'Notification task does not exist.';
    end if;

    if p_project_id is null then
      select project.organization_id
        into v_organization_id
      from public.projects project
      where project.id = v_task_project_id;
    elsif p_project_id <> v_task_project_id then
      raise exception 'Notification task does not belong to project.';
    end if;
  end if;

  insert into public.user_notifications (
    user_id,
    actor_id,
    organization_id,
    project_id,
    task_id,
    type,
    title,
    message,
    payload,
    dedupe_key
  )
  values (
    p_user_id,
    v_actor_id,
    v_organization_id,
    p_project_id,
    p_task_id,
    v_type,
    v_title,
    v_message,
    coalesce(p_payload, '{}'::jsonb),
    nullif(trim(coalesce(p_dedupe_key, '')), '')
  )
  on conflict (dedupe_key) where dedupe_key is not null
  do update set dedupe_key = excluded.dedupe_key
  returning * into v_notification;

  return v_notification;
end;
$$;


ALTER FUNCTION "public"."create_user_notification"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_message" "text", "p_actor_id" "uuid", "p_organization_id" "uuid", "p_project_id" "uuid", "p_task_id" "uuid", "p_payload" "jsonb", "p_dedupe_key" "text", "p_skip_if_actor" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_role"("p_organization_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select member.role
  from public.organization_members member
  where member.organization_id = p_organization_id
    and member.user_id = (select auth.uid())
  limit 1;
$$;


ALTER FUNCTION "public"."current_organization_role"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_project_role"("p_project_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select member.role
  from public.project_members member
  where member.project_id = p_project_id
    and member.user_id = (select auth.uid())
  limit 1;
$$;


ALTER FUNCTION "public"."current_project_role"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decline_organization_invitation"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_organization_id uuid;
  v_invitee_id uuid;
begin
  select organization_id, invitee_id
    into v_organization_id, v_invitee_id
  from public.organization_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if v_organization_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can decline this invitation';
  end if;

  update public.organization_invitations
  set status = 'declined',
      responded_at = now()
  where id = p_invitation_id;

  return v_organization_id;
end;
$$;


ALTER FUNCTION "public"."decline_organization_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decline_organization_invitation_command"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_organization_id uuid;
  v_invitee_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para responder invitaciones.';
  end if;

  select organization_id, invitee_id
    into v_organization_id, v_invitee_id
  from public.organization_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if v_organization_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can decline this invitation';
  end if;

  update public.organization_invitations
  set status = 'declined',
      responded_at = now()
  where id = p_invitation_id;

  return v_organization_id;
end;
$$;


ALTER FUNCTION "public"."decline_organization_invitation_command"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decline_project_invitation"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_project_id uuid;
  v_invitee_id uuid;
begin
  select project_id, invitee_id
    into v_project_id, v_invitee_id
  from public.project_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if v_project_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can decline this invitation';
  end if;

  update public.project_invitations
  set status = 'declined',
      responded_at = now()
  where id = p_invitation_id;

  return v_project_id;
end;
$$;


ALTER FUNCTION "public"."decline_project_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decline_project_invitation_command"("p_invitation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_project_id uuid;
  v_invitee_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para responder invitaciones.';
  end if;

  select project_id, invitee_id
    into v_project_id, v_invitee_id
  from public.project_invitations
  where id = p_invitation_id
    and status = 'pending'
  for update;

  if v_project_id is null then
    raise exception 'Invitation not found or already handled';
  end if;

  if v_invitee_id <> auth.uid() then
    raise exception 'Only the invited user can decline this invitation';
  end if;

  update public.project_invitations
  set status = 'declined',
      responded_at = now()
  where id = p_invitation_id;

  return v_project_id;
end;
$$;


ALTER FUNCTION "public"."decline_project_invitation_command"("p_invitation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enqueue_command_job"("p_queue_name" "text", "p_job_type" "text", "p_payload" "jsonb", "p_delay_seconds" integer DEFAULT 0) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_job_id uuid;
  v_job_key text := nullif(coalesce(p_payload, '{}'::jsonb) ->> 'job_key', '');
begin
  if nullif(trim(coalesce(p_queue_name, '')), '') is null then
    raise exception 'queue_name is required';
  end if;

  if nullif(trim(coalesce(p_job_type, '')), '') is null then
    raise exception 'job_type is required';
  end if;

  insert into public.command_jobs (
    queue_name,
    job_type,
    payload,
    available_at,
    job_key
  )
  values (
    trim(p_queue_name),
    trim(p_job_type),
    coalesce(p_payload, '{}'::jsonb),
    now() + make_interval(secs => greatest(coalesce(p_delay_seconds, 0), 0)),
    v_job_key
  )
  on conflict (job_key) where job_key is not null do update
    set updated_at = public.command_jobs.updated_at
  returning id into v_job_id;

  return v_job_id;
end;
$$;


ALTER FUNCTION "public"."enqueue_command_job"("p_queue_name" "text", "p_job_type" "text", "p_payload" "jsonb", "p_delay_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_epic_dependency_acyclic"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if exists (
    with recursive dependency_path as (
      select
        ed.epic_id as current_epic_id,
        array[ed.depends_on_epic_id, ed.epic_id] as visited_epic_ids
      from public.epic_dependencies ed
      where ed.depends_on_epic_id = new.epic_id
        and ed.id is distinct from new.id

      union all

      select
        ed.epic_id,
        dependency_path.visited_epic_ids || ed.epic_id
      from dependency_path
      join public.epic_dependencies ed
        on ed.depends_on_epic_id = dependency_path.current_epic_id
      where ed.id is distinct from new.id
        and not ed.epic_id = any(dependency_path.visited_epic_ids)
    )
    select 1
    from dependency_path
    where current_epic_id = new.depends_on_epic_id
  ) then
    raise exception 'This epic dependency would create a cycle.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_epic_dependency_acyclic"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_epic_dependency_same_project"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  dependent_project_id uuid;
  source_project_id uuid;
begin
  select project_id into dependent_project_id
  from public.epics
  where id = new.epic_id;

  select project_id into source_project_id
  from public.epics
  where id = new.depends_on_epic_id;

  if dependent_project_id is null or source_project_id is null or dependent_project_id is distinct from source_project_id then
    raise exception 'Epic dependencies must stay within a single project.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_epic_dependency_same_project"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_task_dependency_acyclic"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if exists (
    with recursive dependency_path as (
      select
        td.task_id as current_task_id,
        array[td.depends_on_task_id, td.task_id] as visited_task_ids
      from public.task_dependencies td
      where td.depends_on_task_id = new.task_id
        and td.id is distinct from new.id

      union all

      select
        td.task_id,
        dependency_path.visited_task_ids || td.task_id
      from dependency_path
      join public.task_dependencies td
        on td.depends_on_task_id = dependency_path.current_task_id
      where td.id is distinct from new.id
        and not td.task_id = any(dependency_path.visited_task_ids)
    )
    select 1
    from dependency_path
    where current_task_id = new.depends_on_task_id
  ) then
    raise exception 'This task dependency would create a cycle.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_task_dependency_acyclic"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_task_dependency_same_project"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  dependent_project_id uuid;
  source_project_id uuid;
begin
  select project_id into dependent_project_id
  from public.tasks
  where id = new.task_id;

  select project_id into source_project_id
  from public.tasks
  where id = new.depends_on_task_id;

  if dependent_project_id is null or source_project_id is null or dependent_project_id is distinct from source_project_id then
    raise exception 'Task dependencies must stay within a single project.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_task_dependency_same_project"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_task_epic_same_project"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
declare
  epic_project_id uuid;
begin
  if new.epic_id is null then
    return new;
  end if;

  select project_id into epic_project_id
  from public.epics
  where id = new.epic_id;

  if epic_project_id is null or new.project_id is null or epic_project_id is distinct from new.project_id then
    raise exception 'Task epic must belong to the same project as the task.';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."ensure_task_epic_same_project"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."evaluate_automation_rules_for_activity_event"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_rule public.automation_rules%rowtype;
  v_action jsonb;
  v_action_index integer;
  v_actions_attempted integer;
  v_actions_succeeded integer;
  v_actions_failed integer;
  v_result jsonb;
  v_action_result jsonb;
  v_run_id uuid;
  v_error_message text;
begin
  if new.project_id is null then
    return new;
  end if;

  for v_rule in
    select *
    from public.automation_rules rule
    where rule.project_id = new.project_id
      and rule.enabled is true
      and rule.trigger_event = new.event_type
  loop
    if not public.automation_rule_matches_event(v_rule, new) then
      continue;
    end if;

    insert into public.automation_runs (
      rule_id,
      organization_id,
      project_id,
      activity_event_id,
      status,
      event_type,
      result
    )
    values (
      v_rule.id,
      new.organization_id,
      new.project_id,
      new.id,
      'pending',
      new.event_type,
      jsonb_build_object('actions', '[]'::jsonb)
    )
    returning id into v_run_id;

    v_actions_attempted := 0;
    v_actions_succeeded := 0;
    v_actions_failed := 0;
    v_result := jsonb_build_object('actions', '[]'::jsonb);
    v_error_message := null;
    v_action_index := 0;

    for v_action in
      select value
      from jsonb_array_elements(coalesce(v_rule.actions, '[]'::jsonb))
    loop
      v_action_index := v_action_index + 1;
      v_actions_attempted := v_actions_attempted + 1;

      begin
        v_action_result := public.execute_automation_action(v_rule, new, v_run_id, v_action, v_action_index);
        v_actions_succeeded := v_actions_succeeded + 1;
        v_result := jsonb_set(
          v_result,
          '{actions}',
          (v_result->'actions') || jsonb_build_array(v_action_result),
          true
        );
      exception
        when others then
          v_actions_failed := v_actions_failed + 1;
          v_error_message := coalesce(v_error_message || ' | ', '') || sqlerrm;
          v_result := jsonb_set(
            v_result,
            '{actions}',
            (v_result->'actions') || jsonb_build_array(
              jsonb_build_object('type', coalesce(v_action->>'type', ''), 'error', sqlerrm)
            ),
            true
          );
      end;
    end loop;

    update public.automation_runs
    set
      status = case
        when v_actions_failed = 0 then 'succeeded'
        when v_actions_succeeded = 0 then 'failed'
        else 'partial'
      end,
      actions_attempted = v_actions_attempted,
      actions_succeeded = v_actions_succeeded,
      actions_failed = v_actions_failed,
      result = v_result,
      error_message = v_error_message,
      completed_at = now()
    where id = v_run_id;

    update public.automation_rules
    set last_run_at = now()
    where id = v_rule.id;
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "public"."evaluate_automation_rules_for_activity_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."execute_automation_action"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events", "p_run_id" "uuid", "p_action" "jsonb", "p_action_index" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_type text := lower(coalesce(p_action->>'type', ''));
  v_title text := coalesce(nullif(trim(p_action->>'title'), ''), 'Automatización ejecutada');
  v_message text := coalesce(
    nullif(trim(p_action->>'message'), ''),
    'La regla "' || p_rule.name || '" se ejecutó para el evento ' || p_event.event_type || '.'
  );
  v_member record;
  v_created_count integer := 0;
  v_job_type text;
begin
  if v_type = 'notify_project_owners' then
    for v_member in
      select user_id
      from public.project_members
      where project_id = p_rule.project_id
        and role = 'owner'
    loop
      perform public.create_user_notification(
        v_member.user_id,
        'automation_rule',
        v_title,
        v_message,
        p_event.actor_id,
        p_event.organization_id,
        p_event.project_id,
        p_event.task_id,
        jsonb_build_object(
          'automationRuleId', p_rule.id,
          'automationRunId', p_run_id,
          'activityEventId', p_event.id,
          'eventType', p_event.event_type,
          'action', p_action
        ),
        'automation_rule:' || p_run_id::text || ':' || p_action_index::text || ':' || v_member.user_id::text,
        false
      );
      v_created_count := v_created_count + 1;
    end loop;

    return jsonb_build_object('type', v_type, 'notifications_created', v_created_count);
  elsif v_type = 'notify_actor' then
    if p_event.actor_id is null then
      return jsonb_build_object('type', v_type, 'notifications_created', 0, 'skipped', 'event_without_actor');
    end if;

    perform public.create_user_notification(
      p_event.actor_id,
      'automation_rule',
      v_title,
      v_message,
      p_event.actor_id,
      p_event.organization_id,
      p_event.project_id,
      p_event.task_id,
      jsonb_build_object(
        'automationRuleId', p_rule.id,
        'automationRunId', p_run_id,
        'activityEventId', p_event.id,
        'eventType', p_event.event_type,
        'action', p_action
      ),
      'automation_rule:' || p_run_id::text || ':' || p_action_index::text || ':' || p_event.actor_id::text,
      false
    );

    return jsonb_build_object('type', v_type, 'notifications_created', 1);
  elsif v_type in ('enqueue_email', 'enqueue_webhook') then
    v_job_type := case
      when v_type = 'enqueue_email' then 'automation.email'
      else 'automation.webhook'
    end;

    perform public.enqueue_command_job(
      v_job_type,
      'queued',
      jsonb_build_object(
        'job_key', v_job_type || ':' || p_run_id::text || ':' || p_action_index::text,
        'automationRuleId', p_rule.id,
        'automationRunId', p_run_id,
        'activityEventId', p_event.id,
        'eventType', p_event.event_type,
        'projectId', p_event.project_id,
        'organizationId', p_event.organization_id,
        'action', p_action
      ),
      0
    );

    return jsonb_build_object('type', v_type, 'job_type', v_job_type, 'queued', true);
  end if;

  raise exception 'Unsupported automation action type: %', v_type;
end;
$$;


ALTER FUNCTION "public"."execute_automation_action"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events", "p_run_id" "uuid", "p_action" "jsonb", "p_action_index" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fail_command_job"("p_job_id" "uuid", "p_error" "text", "p_retry_delay_seconds" integer DEFAULT 60, "p_worker_id" "text" DEFAULT NULL::"text") RETURNS "public"."command_jobs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_job public.command_jobs%rowtype;
begin
  update public.command_jobs job
  set
    status = 'failed',
    available_at = now() + make_interval(secs => greatest(coalesce(p_retry_delay_seconds, 60), 0)),
    locked_at = null,
    locked_by = null,
    last_error = left(coalesce(p_error, 'Command job failed'), 2000),
    updated_at = now()
  where job.id = p_job_id
    and job.status = 'processing'
    and (
      nullif(trim(coalesce(p_worker_id, '')), '') is null
      or job.locked_by = nullif(trim(coalesce(p_worker_id, '')), '')
    )
  returning job.* into v_job;

  if v_job.id is null then
    raise exception 'No processing command job found for failure.';
  end if;

  return v_job;
end;
$$;


ALTER FUNCTION "public"."fail_command_job"("p_job_id" "uuid", "p_error" "text", "p_retry_delay_seconds" integer, "p_worker_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_epic_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_project_key varchar(10);
    v_next_sequence integer;
begin
    if new.project_id is null then
        new.epic_id_display := null;
        return new;
    end if;

    update public.projects
    set issue_sequence = issue_sequence + 1,
        epic_sequence = greatest(epic_sequence + 1, issue_sequence + 1)
    where id = new.project_id
    returning project_key, issue_sequence into v_project_key, v_next_sequence;

    new.epic_id_display := v_project_key || '-' || v_next_sequence;

    return new;
end;
$$;


ALTER FUNCTION "public"."generate_epic_id"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."generate_epic_id"() IS 'Genera automáticamente el epic_id_display al crear una épica';



CREATE TABLE IF NOT EXISTS "public"."sprint_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "sprint_id" "uuid" NOT NULL,
    "report_type" "text" DEFAULT 'sprint_summary'::"text" NOT NULL,
    "generated_by" "uuid",
    "sprint_name" "text" NOT NULL,
    "sprint_goal" "text",
    "sprint_status" "text" NOT NULL,
    "sprint_start_date" "date",
    "sprint_end_date" "date",
    "closed_at" timestamp with time zone,
    "total_tasks" integer DEFAULT 0 NOT NULL,
    "completed_tasks" integer DEFAULT 0 NOT NULL,
    "incomplete_tasks" integer DEFAULT 0 NOT NULL,
    "total_story_points" numeric DEFAULT 0 NOT NULL,
    "completed_story_points" numeric DEFAULT 0 NOT NULL,
    "incomplete_story_points" numeric DEFAULT 0 NOT NULL,
    "completion_rate" numeric DEFAULT 0 NOT NULL,
    "story_point_completion_rate" numeric DEFAULT 0 NOT NULL,
    "snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "generated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sprint_reports_type_check" CHECK (("report_type" = 'sprint_summary'::"text"))
);


ALTER TABLE "public"."sprint_reports" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_sprint_report"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_actor_id" "uuid" DEFAULT NULL::"uuid", "p_dispositions" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "public"."sprint_reports"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_project public.projects%rowtype;
  v_sprint public.sprints%rowtype;
  v_report public.sprint_reports%rowtype;
  v_total_tasks integer := 0;
  v_completed_tasks integer := 0;
  v_incomplete_tasks integer := 0;
  v_total_story_points numeric := 0;
  v_completed_story_points numeric := 0;
  v_incomplete_story_points numeric := 0;
  v_completion_rate numeric := 0;
  v_story_point_completion_rate numeric := 0;
  v_tasks_snapshot jsonb := '[]'::jsonb;
  v_status_snapshot jsonb := '{}'::jsonb;
begin
  if p_project_id is null or p_sprint_id is null then
    raise exception 'project_id and sprint_id are required to generate a sprint report.';
  end if;

  if jsonb_typeof(coalesce(p_dispositions, '[]'::jsonb)) <> 'array' then
    raise exception 'Sprint report dispositions must be an array.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'Project does not exist for sprint report.';
  end if;

  select *
    into v_sprint
  from public.sprints
  where id = p_sprint_id
    and project_id = p_project_id;

  if v_sprint.id is null then
    raise exception 'Sprint does not belong to project for sprint report.';
  end if;

  with task_rows as (
    select
      task.id,
      task.title,
      task.task_id_display,
      task.story_points,
      public.story_points_to_number(task.story_points) as story_points_number,
      task.assignee_id,
      task.epic_id,
      epic.name as epic_name,
      epic.color as epic_color,
      task.priority_id,
      priority.name as priority_name,
      priority.color as priority_color,
      task.column_id,
      column_record.name as column_name,
      column_record.position as column_position,
      task.position,
      task.created_at,
      task.updated_at,
      (
        column_record.id is not null
        and lower(trim(
          translate(
            column_record.name,
            'ÁÉÍÓÚÜÑáéíóúüñ',
            'AEIOUUNaeiouun'
          )
        )) in ('done', 'hecho', 'finalizado', 'completado', 'cerrado')
      ) as is_completed
    from public.tasks task
    left join public.columns column_record on column_record.id = task.column_id
    left join public.epics epic on epic.id = task.epic_id and epic.project_id = task.project_id
    left join public.priorities priority on priority.id = task.priority_id
    where task.project_id = p_project_id
      and task.sprint_id = p_sprint_id
  ),
  totals as (
    select
      count(*)::integer as total_tasks,
      count(*) filter (where is_completed)::integer as completed_tasks,
      count(*) filter (where not is_completed)::integer as incomplete_tasks,
      coalesce(sum(story_points_number), 0) as total_story_points,
      coalesce(sum(story_points_number) filter (where is_completed), 0) as completed_story_points,
      coalesce(sum(story_points_number) filter (where not is_completed), 0) as incomplete_story_points
    from task_rows
  ),
  tasks_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'title', title,
          'task_id_display', task_id_display,
          'story_points', story_points,
          'story_points_number', story_points_number,
          'assignee_id', assignee_id,
          'epic_id', epic_id,
          'epic_name', epic_name,
          'epic_color', epic_color,
          'priority_id', priority_id,
          'priority_name', priority_name,
          'priority_color', priority_color,
          'column_id', column_id,
          'column_name', column_name,
          'is_completed', is_completed,
          'created_at', created_at,
          'updated_at', updated_at
        )
        order by coalesce(column_position, 999999), position, created_at
      ),
      '[]'::jsonb
    ) as tasks
    from task_rows
  ),
  status_json as (
    select coalesce(
      jsonb_object_agg(
        coalesce(column_name, 'Sin columna'),
        jsonb_build_object(
          'tasks', task_count,
          'story_points', story_points
        )
      ),
      '{}'::jsonb
    ) as status_totals
    from (
      select
        column_name,
        count(*)::integer as task_count,
        coalesce(sum(story_points_number), 0) as story_points
      from task_rows
      group by column_name
    ) grouped
  )
  select
    totals.total_tasks,
    totals.completed_tasks,
    totals.incomplete_tasks,
    totals.total_story_points,
    totals.completed_story_points,
    totals.incomplete_story_points,
    case
      when totals.total_tasks = 0 then 0
      else round((totals.completed_tasks::numeric / totals.total_tasks::numeric) * 100, 2)
    end,
    case
      when totals.total_story_points = 0 then 0
      else round((totals.completed_story_points / totals.total_story_points) * 100, 2)
    end,
    tasks_json.tasks,
    status_json.status_totals
  into
    v_total_tasks,
    v_completed_tasks,
    v_incomplete_tasks,
    v_total_story_points,
    v_completed_story_points,
    v_incomplete_story_points,
    v_completion_rate,
    v_story_point_completion_rate,
    v_tasks_snapshot,
    v_status_snapshot
  from totals
  cross join tasks_json
  cross join status_json;

  insert into public.sprint_reports (
    organization_id,
    project_id,
    sprint_id,
    report_type,
    generated_by,
    sprint_name,
    sprint_goal,
    sprint_status,
    sprint_start_date,
    sprint_end_date,
    closed_at,
    total_tasks,
    completed_tasks,
    incomplete_tasks,
    total_story_points,
    completed_story_points,
    incomplete_story_points,
    completion_rate,
    story_point_completion_rate,
    snapshot,
    generated_at,
    updated_at
  )
  values (
    v_project.organization_id,
    p_project_id,
    p_sprint_id,
    'sprint_summary',
    p_actor_id,
    v_sprint.name,
    v_sprint.goal,
    v_sprint.status,
    v_sprint.start_date,
    v_sprint.end_date,
    now(),
    v_total_tasks,
    v_completed_tasks,
    v_incomplete_tasks,
    v_total_story_points,
    v_completed_story_points,
    v_incomplete_story_points,
    v_completion_rate,
    v_story_point_completion_rate,
    jsonb_build_object(
      'sprint', jsonb_build_object(
        'id', v_sprint.id,
        'name', v_sprint.name,
        'goal', v_sprint.goal,
        'status', v_sprint.status,
        'start_date', v_sprint.start_date,
        'end_date', v_sprint.end_date
      ),
      'totals_by_status', v_status_snapshot,
      'tasks', v_tasks_snapshot,
      'dispositions', coalesce(p_dispositions, '[]'::jsonb)
    ),
    now(),
    now()
  )
  on conflict (project_id, sprint_id, report_type) do update
  set
    generated_by = excluded.generated_by,
    sprint_name = excluded.sprint_name,
    sprint_goal = excluded.sprint_goal,
    sprint_status = excluded.sprint_status,
    sprint_start_date = excluded.sprint_start_date,
    sprint_end_date = excluded.sprint_end_date,
    closed_at = excluded.closed_at,
    total_tasks = excluded.total_tasks,
    completed_tasks = excluded.completed_tasks,
    incomplete_tasks = excluded.incomplete_tasks,
    total_story_points = excluded.total_story_points,
    completed_story_points = excluded.completed_story_points,
    incomplete_story_points = excluded.incomplete_story_points,
    completion_rate = excluded.completion_rate,
    story_point_completion_rate = excluded.story_point_completion_rate,
    snapshot = excluded.snapshot,
    generated_at = excluded.generated_at,
    updated_at = now()
  returning * into v_report;

  return v_report;
end;
$$;


ALTER FUNCTION "public"."generate_sprint_report"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_actor_id" "uuid", "p_dispositions" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_task_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_project_id uuid;
    v_project_key varchar(10);
    v_next_sequence integer;
begin
    if new.project_id is not null then
        v_project_id := new.project_id;
    elsif new.column_id is not null then
        select c.project_id into v_project_id
        from public.columns c
        where c.id = new.column_id;

        new.project_id := v_project_id;
    else
        new.task_id_display := null;
        return new;
    end if;

    if v_project_id is null then
        new.task_id_display := null;
        return new;
    end if;

    update public.projects
    set issue_sequence = issue_sequence + 1,
        task_sequence = greatest(task_sequence + 1, issue_sequence + 1)
    where id = v_project_id
    returning project_key, issue_sequence into v_project_key, v_next_sequence;

    new.task_id_display := v_project_key || '-' || v_next_sequence;

    return new;
end;
$$;


ALTER FUNCTION "public"."generate_task_id"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."generate_task_id"() IS 'Genera automáticamente el task_id_display. Tareas en backlog no tienen ID hasta moverse al Kanban';



CREATE OR REPLACE FUNCTION "public"."handle_new_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.user_profiles (id, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture')
  )
  on conflict (id) do update
    set full_name = coalesce(excluded.full_name, public.user_profiles.full_name),
        avatar_url = coalesce(excluded.avatar_url, public.user_profiles.avatar_url),
        updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_organization_admin"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_manage_organization(p_organization_id);
$$;


ALTER FUNCTION "public"."is_organization_admin"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_organization_member"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_view_organization(p_organization_id);
$$;


ALTER FUNCTION "public"."is_organization_member"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_project_member"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_mutate_project(p_project_id);
$$;


ALTER FUNCTION "public"."is_project_member"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_project_owner"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.can_manage_project(p_project_id);
$$;


ALTER FUNCTION "public"."is_project_owner"("p_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."move_task_column_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_column_id" "uuid", "p_position" integer DEFAULT NULL::integer) RETURNS "public"."tasks"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_task public.tasks%rowtype;
  v_previous_column_id uuid;
  v_next_position integer;
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

  if p_column_id is null then
    raise exception 'La columna destino es requerida.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id;

  if v_project.id is null then
    raise exception 'El proyecto no existe.';
  end if;

  if not exists (
    select 1
    from public.columns column_record
    where column_record.id = p_column_id
      and column_record.project_id = p_project_id
  ) then
    raise exception 'La columna no pertenece al proyecto activo.';
  end if;

  select *
    into v_task
  from public.tasks
  where id = p_task_id
    and project_id = p_project_id
  for update;

  if not found then
    raise exception 'La tarea no pertenece al proyecto activo.';
  end if;

  v_previous_column_id := v_task.column_id;

  if p_position is null then
    select coalesce(max(position), -1) + 1
      into v_next_position
    from public.tasks
    where project_id = p_project_id
      and column_id = p_column_id
      and sprint_id is not distinct from v_task.sprint_id
      and id <> p_task_id;
  else
    v_next_position := greatest(p_position, 0);
  end if;

  update public.tasks
  set
    column_id = p_column_id,
    position = v_next_position,
    in_backlog = false,
    updated_at = now()
  where id = p_task_id
    and project_id = p_project_id
  returning * into v_task;

  if p_column_id is distinct from v_previous_column_id then
    perform public.record_activity_event(
      'task.moved',
      v_project.organization_id,
      p_project_id,
      v_task.sprint_id,
      v_task.id,
      v_user_id,
      jsonb_build_object(
        'previous_column_id', v_previous_column_id,
        'column_id', p_column_id,
        'task_id_display', v_task.task_id_display
      ),
      'task-moved:' || v_task.id || ':' || extract(epoch from v_task.updated_at)::text
    );
  end if;

  return v_task;
end;
$$;


ALTER FUNCTION "public"."move_task_column_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_column_id" "uuid", "p_position" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_activity_event"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_auth_user_id uuid := auth.uid();
  v_project_organization_id uuid;
  v_task_project_id uuid;
  v_task_sprint_id uuid;
  v_sprint_project_id uuid;
begin
  new.event_type := lower(trim(coalesce(new.event_type, '')));
  new.payload := coalesce(new.payload, '{}'::jsonb);
  new.event_key := nullif(trim(coalesce(new.event_key, '')), '');

  if new.event_type = '' then
    raise exception 'activity_events.event_type is required.';
  end if;

  if new.actor_id is null then
    new.actor_id := v_auth_user_id;
  end if;

  if new.actor_id is null then
    raise exception 'activity_events.actor_id is required.';
  end if;

  if v_auth_user_id is not null and new.actor_id <> v_auth_user_id then
    raise exception 'activity_events.actor_id must match the authenticated user.';
  end if;

  if new.project_id is not null then
    select project.organization_id
      into v_project_organization_id
    from public.projects project
    where project.id = new.project_id;

    if v_project_organization_id is null then
      raise exception 'activity_events.project_id does not reference an existing project.';
    end if;

    if new.organization_id is null then
      new.organization_id := v_project_organization_id;
    elsif new.organization_id <> v_project_organization_id then
      raise exception 'activity_events.organization_id does not match project organization.';
    end if;
  end if;

  if new.organization_id is null then
    raise exception 'activity_events must be scoped to an organization or project.';
  end if;

  if new.task_id is not null then
    select task.project_id, task.sprint_id
      into v_task_project_id, v_task_sprint_id
    from public.tasks task
    where task.id = new.task_id;

    if v_task_project_id is null then
      raise exception 'activity_events.task_id does not reference an existing task.';
    end if;

    if new.project_id is null then
      new.project_id := v_task_project_id;

      select project.organization_id
        into new.organization_id
      from public.projects project
      where project.id = new.project_id;
    elsif new.project_id <> v_task_project_id then
      raise exception 'activity_events.task_id does not belong to activity_events.project_id.';
    end if;

    if new.sprint_id is null and v_task_sprint_id is not null then
      new.sprint_id := v_task_sprint_id;
    elsif new.sprint_id is not null
      and v_task_sprint_id is not null
      and new.sprint_id <> v_task_sprint_id then
      raise exception 'activity_events.sprint_id does not match task sprint.';
    end if;
  end if;

  if new.sprint_id is not null then
    select sprint.project_id
      into v_sprint_project_id
    from public.sprints sprint
    where sprint.id = new.sprint_id;

    if v_sprint_project_id is null then
      raise exception 'activity_events.sprint_id does not reference an existing sprint.';
    end if;

    if new.project_id is null then
      new.project_id := v_sprint_project_id;

      select project.organization_id
        into new.organization_id
      from public.projects project
      where project.id = new.project_id;
    elsif new.project_id <> v_sprint_project_id then
      raise exception 'activity_events.sprint_id does not belong to activity_events.project_id.';
    end if;
  end if;

  if new.created_at is null then
    new.created_at := now();
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."normalize_activity_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_sprint_report_before_write"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  if new.report_type = 'sprint_summary' and new.closed_at is not null then
    new.sprint_status := 'closed';
    new.snapshot := jsonb_set(
      coalesce(new.snapshot, '{}'::jsonb),
      '{sprint,status}',
      to_jsonb('closed'::text),
      true
    );
  end if;

  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "public"."normalize_sprint_report_before_write"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_activity_event"("p_event_type" "text", "p_organization_id" "uuid" DEFAULT NULL::"uuid", "p_project_id" "uuid" DEFAULT NULL::"uuid", "p_sprint_id" "uuid" DEFAULT NULL::"uuid", "p_task_id" "uuid" DEFAULT NULL::"uuid", "p_actor_id" "uuid" DEFAULT NULL::"uuid", "p_payload" "jsonb" DEFAULT '{}'::"jsonb", "p_event_key" "text" DEFAULT NULL::"text") RETURNS "public"."activity_events"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_event public.activity_events%rowtype;
begin
  insert into public.activity_events (
    organization_id,
    project_id,
    sprint_id,
    task_id,
    actor_id,
    event_type,
    payload,
    event_key
  )
  values (
    p_organization_id,
    p_project_id,
    p_sprint_id,
    p_task_id,
    coalesce(p_actor_id, auth.uid()),
    p_event_type,
    coalesce(p_payload, '{}'::jsonb),
    nullif(trim(coalesce(p_event_key, '')), '')
  )
  on conflict (event_key) where event_key is not null
  do update set event_key = excluded.event_key
  returning * into v_event;

  return v_event;
end;
$$;


ALTER FUNCTION "public"."record_activity_event"("p_event_type" "text", "p_organization_id" "uuid", "p_project_id" "uuid", "p_sprint_id" "uuid", "p_task_id" "uuid", "p_actor_id" "uuid", "p_payload" "jsonb", "p_event_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_organization_member_command"("p_organization_id" "uuid", "p_member_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_member public.organization_members%rowtype;
  v_owner_count integer;
begin
  if v_actor_id is null then
    raise exception 'Debes iniciar sesión para quitar miembros.';
  end if;

  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Solo owner/admin pueden quitar miembros de la organización.';
  end if;

  select *
    into v_member
  from public.organization_members
  where id = p_member_id
    and organization_id = p_organization_id
  for update;

  if v_member.id is null then
    raise exception 'Miembro de organización no encontrado.';
  end if;

  if v_member.role = 'owner' then
    select count(*)
      into v_owner_count
    from public.organization_members
    where organization_id = p_organization_id
      and role = 'owner';

    if v_owner_count <= 1 then
      raise exception 'La organización debe conservar al menos un owner.';
    end if;
  end if;

  delete from public.project_members project_member
  using public.projects project
  where project.id = project_member.project_id
    and project.organization_id = p_organization_id
    and project_member.user_id = v_member.user_id;

  delete from public.organization_members
  where id = p_member_id;

  insert into public.activity_events (
    organization_id,
    actor_id,
    event_type,
    payload
  )
  values (
    p_organization_id,
    v_actor_id,
    'organization.member_removed',
    jsonb_build_object('memberId', p_member_id, 'userId', v_member.user_id)
  );

  return v_member.user_id;
end;
$$;


ALTER FUNCTION "public"."remove_organization_member_command"("p_organization_id" "uuid", "p_member_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_project_member_command"("p_project_id" "uuid", "p_member_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_project public.projects%rowtype;
  v_member public.project_members%rowtype;
  v_owner_count integer;
begin
  if v_actor_id is null then
    raise exception 'Debes iniciar sesión para quitar colaboradores.';
  end if;

  select *
    into v_project
  from public.projects
  where id = p_project_id
  for update;

  if v_project.id is null then
    raise exception 'Proyecto no encontrado.';
  end if;

  if not public.is_project_owner(p_project_id) then
    raise exception 'Solo owners del proyecto pueden quitar colaboradores.';
  end if;

  select *
    into v_member
  from public.project_members
  where id = p_member_id
    and project_id = p_project_id
  for update;

  if v_member.id is null then
    raise exception 'Miembro de proyecto no encontrado.';
  end if;

  if v_member.role = 'owner' then
    select count(*)
      into v_owner_count
    from public.project_members
    where project_id = p_project_id
      and role = 'owner';

    if v_owner_count <= 1 then
      raise exception 'El proyecto debe conservar al menos un owner.';
    end if;
  end if;

  delete from public.project_members
  where id = p_member_id;

  insert into public.activity_events (
    organization_id,
    project_id,
    actor_id,
    event_type,
    payload
  )
  values (
    v_project.organization_id,
    p_project_id,
    v_actor_id,
    'project.member_removed',
    jsonb_build_object('memberId', p_member_id, 'userId', v_member.user_id)
  );

  return v_member.user_id;
end;
$$;


ALTER FUNCTION "public"."remove_project_member_command"("p_project_id" "uuid", "p_member_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_stale_command_jobs"("p_timeout_seconds" integer DEFAULT 300) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_count integer;
begin
  update public.command_jobs job
  set
    status = 'failed',
    available_at = now(),
    locked_at = null,
    locked_by = null,
    last_error = 'Worker lock expired before completion.',
    updated_at = now()
  where job.status = 'processing'
    and job.locked_at < now() - make_interval(secs => greatest(coalesce(p_timeout_seconds, 300), 1));

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


ALTER FUNCTION "public"."reset_stale_command_jobs"("p_timeout_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_command_job_maintenance"("p_stale_timeout_seconds" integer DEFAULT 300) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_reset_count integer := 0;
begin
  v_reset_count := public.reset_stale_command_jobs(
    greatest(coalesce(p_stale_timeout_seconds, 300), 60)
  );

  return jsonb_build_object(
    'reset_stale_jobs', v_reset_count,
    'ran_at', now()
  );
end;
$$;


ALTER FUNCTION "public"."run_command_job_maintenance"("p_stale_timeout_seconds" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."scan_sprint_deadlines"("p_today" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_due_soon_count integer := 0;
  v_overdue_count integer := 0;
  v_sprint record;
  v_member record;
begin
  for v_sprint in
    select
      sprint.id,
      sprint.project_id,
      sprint.name,
      sprint.end_date,
      project.organization_id,
      project.title as project_title
    from public.sprints sprint
    join public.projects project on project.id = sprint.project_id
    where sprint.status = 'active'
      and sprint.end_date is not null
      and sprint.end_date::date = p_today + 1
  loop
    for v_member in
      select project_member.user_id
      from public.project_members project_member
      where project_member.project_id = v_sprint.project_id
    loop
      perform public.create_user_notification(
        v_member.user_id,
        'sprint_due_soon',
        'Sprint por vencer',
        'El sprint ' || coalesce(v_sprint.name, 'sin nombre') || ' termina mañana.',
        null,
        v_sprint.organization_id,
        v_sprint.project_id,
        null,
        jsonb_build_object(
          'projectId', v_sprint.project_id,
          'projectTitle', v_sprint.project_title,
          'sprintId', v_sprint.id,
          'sprintName', v_sprint.name,
          'endDate', v_sprint.end_date
        ),
        'sprint_due_soon:' || v_sprint.id::text || ':' || v_member.user_id::text,
        false
      );

      v_due_soon_count := v_due_soon_count + 1;
    end loop;
  end loop;

  for v_sprint in
    select
      sprint.id,
      sprint.project_id,
      sprint.name,
      sprint.end_date,
      project.organization_id,
      project.title as project_title
    from public.sprints sprint
    join public.projects project on project.id = sprint.project_id
    where sprint.status = 'active'
      and sprint.end_date is not null
      and sprint.end_date::date < p_today
  loop
    for v_member in
      select project_member.user_id
      from public.project_members project_member
      where project_member.project_id = v_sprint.project_id
    loop
      perform public.create_user_notification(
        v_member.user_id,
        'sprint_overdue',
        'Sprint vencido',
        'El sprint ' || coalesce(v_sprint.name, 'sin nombre') || ' ya venció y requiere cierre.',
        null,
        v_sprint.organization_id,
        v_sprint.project_id,
        null,
        jsonb_build_object(
          'projectId', v_sprint.project_id,
          'projectTitle', v_sprint.project_title,
          'sprintId', v_sprint.id,
          'sprintName', v_sprint.name,
          'endDate', v_sprint.end_date,
          'daysOverdue', p_today - v_sprint.end_date::date
        ),
        'sprint_overdue:' || v_sprint.id::text || ':' || v_member.user_id::text || ':' || p_today::text,
        false
      );

      v_overdue_count := v_overdue_count + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'due_soon_notifications_attempted', v_due_soon_count,
    'overdue_notifications_attempted', v_overdue_count,
    'ran_for_date', p_today,
    'ran_at', now()
  );
end;
$$;


ALTER FUNCTION "public"."scan_sprint_deadlines"("p_today" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."story_points_to_number"("p_value" "text") RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    AS $_$
  select case
    when nullif(trim(coalesce(p_value, '')), '') is null then 0
    when trim(p_value) ~ '^[0-9]+(\\.[0-9]+)?$' then trim(p_value)::numeric
    else 0
  end;
$_$;


ALTER FUNCTION "public"."story_points_to_number"("p_value" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_automation_rule_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin
  new.updated_at := now();
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."touch_automation_rule_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_column_order_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_column_order_updated_at"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organization_members" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "organization_members_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'admin'::"text", 'member'::"text"])))
);


ALTER TABLE "public"."organization_members" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_organization_member_role_command"("p_organization_id" "uuid", "p_member_id" "uuid", "p_role" "text") RETURNS "public"."organization_members"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_actor_id uuid := auth.uid();
  v_member public.organization_members%rowtype;
  v_updated_member public.organization_members%rowtype;
  v_role text := lower(trim(coalesce(p_role, '')));
  v_owner_count integer;
begin
  if v_actor_id is null then
    raise exception 'Debes iniciar sesión para cambiar roles.';
  end if;

  if v_role not in ('owner', 'admin', 'member') then
    raise exception 'Rol de organización inválido.';
  end if;

  if not public.is_organization_admin(p_organization_id) then
    raise exception 'Solo owner/admin pueden cambiar roles de organización.';
  end if;

  select *
    into v_member
  from public.organization_members
  where id = p_member_id
    and organization_id = p_organization_id
  for update;

  if v_member.id is null then
    raise exception 'Miembro de organización no encontrado.';
  end if;

  if v_member.role = 'owner' and v_role <> 'owner' then
    select count(*)
      into v_owner_count
    from public.organization_members
    where organization_id = p_organization_id
      and role = 'owner';

    if v_owner_count <= 1 then
      raise exception 'La organización debe conservar al menos un owner.';
    end if;
  end if;

  update public.organization_members
  set role = v_role
  where id = p_member_id
  returning * into v_updated_member;

  insert into public.activity_events (
    organization_id,
    actor_id,
    event_type,
    payload
  )
  values (
    p_organization_id,
    v_actor_id,
    'organization.member_role_updated',
    jsonb_build_object(
      'memberId', p_member_id,
      'userId', v_member.user_id,
      'previousRole', v_member.role,
      'role', v_role
    )
  );

  return v_updated_member;
end;
$$;


ALTER FUNCTION "public"."update_organization_member_role_command"("p_organization_id" "uuid", "p_member_id" "uuid", "p_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_single_active_sprint"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Solo validar si el sprint está pasando a 'active'
  IF NEW.status = 'active' THEN
    -- Verificar si ya existe otro sprint activo en este proyecto
    IF EXISTS (
      SELECT 1 FROM public.sprints
      WHERE project_id = NEW.project_id
        AND status = 'active'
        AND id != NEW.id
    ) THEN
      RAISE EXCEPTION 'Solo puede existir un sprint activo por proyecto simultáneamente';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_single_active_sprint"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."automation_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rule_id" "uuid" NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "activity_event_id" "uuid",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "event_type" "text" NOT NULL,
    "actions_attempted" integer DEFAULT 0 NOT NULL,
    "actions_succeeded" integer DEFAULT 0 NOT NULL,
    "actions_failed" integer DEFAULT 0 NOT NULL,
    "result" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    CONSTRAINT "automation_runs_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'succeeded'::"text", 'failed'::"text", 'partial'::"text"])))
);


ALTER TABLE "public"."automation_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."boards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."boards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."column_order" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "board_id" "uuid",
    "column_ids" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "project_id" "uuid"
);


ALTER TABLE "public"."column_order" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."columns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "board_id" "uuid",
    "name" "text" NOT NULL,
    "position" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "project_id" "uuid"
);


ALTER TABLE "public"."columns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."editor_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "board_id" "uuid",
    "content" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_manual_save" boolean DEFAULT false,
    "is_snapshot" boolean DEFAULT false,
    "project_id" "uuid"
);


ALTER TABLE "public"."editor_notes" OWNER TO "postgres";


COMMENT ON COLUMN "public"."editor_notes"."is_snapshot" IS 'false = nota activa (auto-guardado), true = snapshot (versión manual guardada por el usuario)';



CREATE TABLE IF NOT EXISTS "public"."epic_dependencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "epic_id" "uuid" NOT NULL,
    "depends_on_epic_id" "uuid" NOT NULL,
    "dependency_type" "text" DEFAULT 'finish-to-start'::"text" NOT NULL,
    "lag_days" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "epic_dependencies_dependency_type_check" CHECK (("dependency_type" = ANY (ARRAY['finish-to-start'::"text", 'start-to-start'::"text", 'finish-to-finish'::"text", 'start-to-finish'::"text"]))),
    CONSTRAINT "epic_dependencies_no_self_reference" CHECK (("epic_id" <> "depends_on_epic_id"))
);


ALTER TABLE "public"."epic_dependencies" OWNER TO "postgres";


COMMENT ON TABLE "public"."epic_dependencies" IS 'Dependencias entre épicas (opcional, puede ser cross-project)';



COMMENT ON COLUMN "public"."epic_dependencies"."epic_id" IS 'Épica que tiene la dependencia';



COMMENT ON COLUMN "public"."epic_dependencies"."depends_on_epic_id" IS 'Épica de la cual depende (puede ser de otro proyecto)';



COMMENT ON COLUMN "public"."epic_dependencies"."dependency_type" IS 'Tipo de dependencia';



COMMENT ON COLUMN "public"."epic_dependencies"."lag_days" IS 'Días de margen (puede ser negativo)';



CREATE TABLE IF NOT EXISTS "public"."epic_phases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "color" "text",
    "position" integer NOT NULL
);


ALTER TABLE "public"."epic_phases" OWNER TO "postgres";


COMMENT ON TABLE "public"."epic_phases" IS 'Fases de las épicas (Pendiente, Descubrimiento, etc)';



CREATE TABLE IF NOT EXISTS "public"."epics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "owner_id" "uuid",
    "phase_id" "uuid",
    "estimated_effort" "text",
    "epic_id_display" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "project_id" "uuid",
    "start_date" "date",
    "end_date" "date",
    "color" "text" DEFAULT '#3B82F6'::"text"
);


ALTER TABLE "public"."epics" OWNER TO "postgres";


COMMENT ON TABLE "public"."epics" IS 'Tabla de épicas del proyecto';



COMMENT ON COLUMN "public"."epics"."estimated_effort" IS 'Esfuerzo estimado en puntos Fibonacci';



COMMENT ON COLUMN "public"."epics"."epic_id_display" IS 'ID visual de la épica (ej: PIANOLRN-1)';



COMMENT ON COLUMN "public"."epics"."project_id" IS 'Referencia al proyecto al que pertenece la épica';



COMMENT ON COLUMN "public"."epics"."start_date" IS 'Fecha de inicio de la épica';



COMMENT ON COLUMN "public"."epics"."end_date" IS 'Fecha de finalización de la épica';



COMMENT ON COLUMN "public"."epics"."color" IS 'Color visual de la épica en tablas y tarjetas';



CREATE TABLE IF NOT EXISTS "public"."issue_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "icon" "text",
    "color" "text",
    "position" integer NOT NULL
);


ALTER TABLE "public"."issue_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."issue_types" IS 'Tipos de issues: Bug, Story, Task, Epic, Sub-task';



CREATE TABLE IF NOT EXISTS "public"."organization_invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "inviter_id" "uuid" NOT NULL,
    "invitee_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    CONSTRAINT "organization_invitations_no_self_invite" CHECK (("inviter_id" <> "invitee_id")),
    CONSTRAINT "organization_invitations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text"])))
);


ALTER TABLE "public"."organization_invitations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "logo_url" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."point_systems" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "is_default" boolean DEFAULT false
);


ALTER TABLE "public"."point_systems" OWNER TO "postgres";


COMMENT ON TABLE "public"."point_systems" IS 'Sistemas de puntuación: Fibonacci, Lineal, T-Shirt';



CREATE TABLE IF NOT EXISTS "public"."point_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "system_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "numeric_value" integer,
    "position" integer NOT NULL
);


ALTER TABLE "public"."point_values" OWNER TO "postgres";


COMMENT ON TABLE "public"."point_values" IS 'Valores específicos para cada sistema de puntos';



CREATE TABLE IF NOT EXISTS "public"."priorities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "level" integer NOT NULL,
    "color" "text",
    "position" integer NOT NULL
);


ALTER TABLE "public"."priorities" OWNER TO "postgres";


COMMENT ON TABLE "public"."priorities" IS 'Niveles de prioridad para las tareas';



CREATE TABLE IF NOT EXISTS "public"."project_invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "inviter_id" "uuid" NOT NULL,
    "invitee_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    CONSTRAINT "project_invitations_no_self_invite" CHECK (("inviter_id" <> "invitee_id")),
    CONSTRAINT "project_invitations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text"])))
);


ALTER TABLE "public"."project_invitations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "tag" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."project_tags" OWNER TO "postgres";


COMMENT ON TABLE "public"."project_tags" IS 'Tags asociados a los proyectos';



CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "project_key" character varying(10) DEFAULT 'TEMP'::character varying NOT NULL,
    "task_sequence" integer DEFAULT 0 NOT NULL,
    "epic_sequence" integer DEFAULT 0 NOT NULL,
    "allow_board_task_creation" boolean DEFAULT false NOT NULL,
    "banner_url" "text",
    "issue_sequence" integer DEFAULT 0 NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "visibility" "text" DEFAULT 'organization'::"text" NOT NULL,
    CONSTRAINT "projects_visibility_check" CHECK (("visibility" = ANY (ARRAY['organization'::"text", 'private'::"text"])))
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


COMMENT ON TABLE "public"."projects" IS 'Proyectos principales del usuario';



COMMENT ON COLUMN "public"."projects"."project_key" IS 'Siglas del proyecto usadas para generar IDs (ej: PIANOLRN)';



COMMENT ON COLUMN "public"."projects"."task_sequence" IS 'Contador auto-incremental para IDs de tareas';



COMMENT ON COLUMN "public"."projects"."epic_sequence" IS 'Contador auto-incremental para IDs de épicas';



COMMENT ON COLUMN "public"."projects"."issue_sequence" IS 'Contador único por proyecto para IDs visibles de tareas y épicas';



CREATE TABLE IF NOT EXISTS "public"."roadmap_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "child_level_issue_scheduling" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."roadmap_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_dependencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_id" "uuid" NOT NULL,
    "depends_on_task_id" "uuid" NOT NULL,
    "dependency_type" "text" DEFAULT 'finish-to-start'::"text" NOT NULL,
    "lag_days" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "task_dependencies_no_self_reference" CHECK (("task_id" <> "depends_on_task_id")),
    CONSTRAINT "task_dependencies_type_check" CHECK (("dependency_type" = ANY (ARRAY['finish-to-start'::"text", 'start-to-start'::"text", 'finish-to-finish'::"text", 'start-to-finish'::"text"])))
);


ALTER TABLE "public"."task_dependencies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "job_title" "text",
    "skills" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "organization" "text",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "preferences" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_profiles"."preferences" IS 'User-scoped UI and product preferences stored as JSONB, for example themeMode.';



ALTER TABLE ONLY "public"."activity_events"
    ADD CONSTRAINT "activity_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."automation_rules"
    ADD CONSTRAINT "automation_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."automation_runs"
    ADD CONSTRAINT "automation_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."boards"
    ADD CONSTRAINT "boards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."column_order"
    ADD CONSTRAINT "column_order_board_unique" UNIQUE ("board_id");



ALTER TABLE ONLY "public"."column_order"
    ADD CONSTRAINT "column_order_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."column_order"
    ADD CONSTRAINT "column_order_project_id_key" UNIQUE ("project_id");



ALTER TABLE ONLY "public"."columns"
    ADD CONSTRAINT "columns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."command_jobs"
    ADD CONSTRAINT "command_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."editor_notes"
    ADD CONSTRAINT "editor_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."epic_dependencies"
    ADD CONSTRAINT "epic_dependencies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."epic_dependencies"
    ADD CONSTRAINT "epic_dependencies_unique" UNIQUE ("epic_id", "depends_on_epic_id");



ALTER TABLE ONLY "public"."epic_phases"
    ADD CONSTRAINT "epic_phases_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."epic_phases"
    ADD CONSTRAINT "epic_phases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."epics"
    ADD CONSTRAINT "epics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."issue_types"
    ADD CONSTRAINT "issue_types_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."issue_types"
    ADD CONSTRAINT "issue_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_invitations"
    ADD CONSTRAINT "organization_invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_organization_id_user_id_key" UNIQUE ("organization_id", "user_id");



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."point_systems"
    ADD CONSTRAINT "point_systems_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."point_systems"
    ADD CONSTRAINT "point_systems_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."point_values"
    ADD CONSTRAINT "point_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."priorities"
    ADD CONSTRAINT "priorities_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."priorities"
    ADD CONSTRAINT "priorities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_invitations"
    ADD CONSTRAINT "project_invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_user_id_key" UNIQUE ("project_id", "user_id");



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_user_unique" UNIQUE ("project_id", "user_id");



ALTER TABLE ONLY "public"."project_tags"
    ADD CONSTRAINT "project_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_project_key_unique" UNIQUE ("project_key");



ALTER TABLE ONLY "public"."roadmap_settings"
    ADD CONSTRAINT "roadmap_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roadmap_settings"
    ADD CONSTRAINT "roadmap_settings_user_project_unique" UNIQUE ("user_id", "project_id");



ALTER TABLE ONLY "public"."sprint_reports"
    ADD CONSTRAINT "sprint_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sprint_reports"
    ADD CONSTRAINT "sprint_reports_unique_type_per_sprint" UNIQUE ("project_id", "sprint_id", "report_type");



ALTER TABLE ONLY "public"."sprints"
    ADD CONSTRAINT "sprints_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_dependencies"
    ADD CONSTRAINT "task_dependencies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_dependencies"
    ADD CONSTRAINT "task_dependencies_unique" UNIQUE ("task_id", "depends_on_task_id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



CREATE INDEX "activity_events_actor_created_idx" ON "public"."activity_events" USING "btree" ("actor_id", "created_at" DESC);



CREATE UNIQUE INDEX "activity_events_event_key_uidx" ON "public"."activity_events" USING "btree" ("event_key") WHERE ("event_key" IS NOT NULL);



CREATE INDEX "activity_events_organization_created_idx" ON "public"."activity_events" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "activity_events_project_created_idx" ON "public"."activity_events" USING "btree" ("project_id", "created_at" DESC);



CREATE INDEX "activity_events_type_created_idx" ON "public"."activity_events" USING "btree" ("event_type", "created_at" DESC);



CREATE INDEX "automation_rules_organization_idx" ON "public"."automation_rules" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "automation_rules_project_enabled_idx" ON "public"."automation_rules" USING "btree" ("project_id", "enabled", "trigger_event");



CREATE INDEX "automation_runs_project_created_idx" ON "public"."automation_runs" USING "btree" ("project_id", "created_at" DESC);



CREATE INDEX "automation_runs_rule_created_idx" ON "public"."automation_runs" USING "btree" ("rule_id", "created_at" DESC);



CREATE UNIQUE INDEX "command_jobs_job_key_uidx" ON "public"."command_jobs" USING "btree" ("job_key") WHERE ("job_key" IS NOT NULL);



CREATE INDEX "command_jobs_processing_lock_idx" ON "public"."command_jobs" USING "btree" ("status", "locked_at") WHERE ("status" = 'processing'::"text");



CREATE INDEX "command_jobs_queue_status_available_idx" ON "public"."command_jobs" USING "btree" ("queue_name", "status", "available_at", "created_at");



CREATE INDEX "command_jobs_worker_claim_idx" ON "public"."command_jobs" USING "btree" ("queue_name", "status", "available_at", "created_at") WHERE ("status" = ANY (ARRAY['queued'::"text", 'failed'::"text"]));



CREATE INDEX "idx_column_order_board_id" ON "public"."column_order" USING "btree" ("board_id");



CREATE INDEX "idx_column_order_project_id" ON "public"."column_order" USING "btree" ("project_id");



CREATE INDEX "idx_columns_project_id" ON "public"."columns" USING "btree" ("project_id");



CREATE INDEX "idx_editor_notes_board_snapshot" ON "public"."editor_notes" USING "btree" ("board_id", "is_snapshot", "updated_at" DESC);



CREATE INDEX "idx_editor_notes_board_updated" ON "public"."editor_notes" USING "btree" ("board_id", "updated_at" DESC);



CREATE INDEX "idx_epic_dependencies_depends_on_epic_id" ON "public"."epic_dependencies" USING "btree" ("depends_on_epic_id");



CREATE INDEX "idx_epic_dependencies_epic_id" ON "public"."epic_dependencies" USING "btree" ("epic_id");



CREATE INDEX "idx_epics_epic_id_display" ON "public"."epics" USING "btree" ("epic_id_display");



CREATE INDEX "idx_epics_owner" ON "public"."epics" USING "btree" ("owner_id");



CREATE INDEX "idx_epics_phase" ON "public"."epics" USING "btree" ("phase_id");



CREATE INDEX "idx_epics_project_id" ON "public"."epics" USING "btree" ("project_id");



CREATE INDEX "idx_epics_user" ON "public"."epics" USING "btree" ("user_id");



CREATE INDEX "idx_point_values_system" ON "public"."point_values" USING "btree" ("system_id");



CREATE INDEX "idx_project_members_project_id" ON "public"."project_members" USING "btree" ("project_id");



CREATE INDEX "idx_project_members_user_id" ON "public"."project_members" USING "btree" ("user_id");



CREATE INDEX "idx_project_tags_project_id" ON "public"."project_tags" USING "btree" ("project_id");



CREATE INDEX "idx_project_tags_tag" ON "public"."project_tags" USING "btree" ("tag");



CREATE INDEX "idx_projects_project_key" ON "public"."projects" USING "btree" ("project_key");



CREATE INDEX "idx_projects_user_id" ON "public"."projects" USING "btree" ("user_id");



CREATE INDEX "idx_sprints_project_id" ON "public"."sprints" USING "btree" ("project_id");



CREATE INDEX "idx_sprints_project_status" ON "public"."sprints" USING "btree" ("project_id", "status");



CREATE INDEX "idx_sprints_status" ON "public"."sprints" USING "btree" ("status");



CREATE INDEX "idx_tasks_assignee" ON "public"."tasks" USING "btree" ("assignee_id");



CREATE INDEX "idx_tasks_epic_id" ON "public"."tasks" USING "btree" ("epic_id");



CREATE INDEX "idx_tasks_github_link" ON "public"."tasks" USING "btree" ("github_link") WHERE ("github_link" IS NOT NULL);



CREATE INDEX "idx_tasks_in_backlog" ON "public"."tasks" USING "btree" ("in_backlog");



CREATE INDEX "idx_tasks_issue_type" ON "public"."tasks" USING "btree" ("issue_type_id");



CREATE INDEX "idx_tasks_parent_task_id" ON "public"."tasks" USING "btree" ("parent_task_id");



CREATE INDEX "idx_tasks_priority" ON "public"."tasks" USING "btree" ("priority_id");



CREATE INDEX "idx_tasks_project_backlog" ON "public"."tasks" USING "btree" ("column_id", "in_backlog");



CREATE INDEX "idx_tasks_project_id" ON "public"."tasks" USING "btree" ("project_id");



CREATE INDEX "idx_tasks_sprint_id" ON "public"."tasks" USING "btree" ("sprint_id");



CREATE INDEX "idx_tasks_task_id_display" ON "public"."tasks" USING "btree" ("task_id_display");



CREATE INDEX "organization_invitations_invitee_status_idx" ON "public"."organization_invitations" USING "btree" ("invitee_id", "status", "created_at" DESC);



CREATE UNIQUE INDEX "organization_invitations_pending_unique" ON "public"."organization_invitations" USING "btree" ("organization_id", "invitee_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "organization_members_user_id_idx" ON "public"."organization_members" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "project_invitations_invitee_status_idx" ON "public"."project_invitations" USING "btree" ("invitee_id", "status", "created_at" DESC);



CREATE UNIQUE INDEX "project_invitations_pending_unique" ON "public"."project_invitations" USING "btree" ("project_id", "invitee_id") WHERE ("status" = 'pending'::"text");



CREATE INDEX "projects_organization_id_idx" ON "public"."projects" USING "btree" ("organization_id", "created_at" DESC);



CREATE UNIQUE INDEX "projects_project_key_upper_unique" ON "public"."projects" USING "btree" ("upper"(("project_key")::"text"));



CREATE INDEX "sprint_reports_project_generated_idx" ON "public"."sprint_reports" USING "btree" ("project_id", "generated_at" DESC);



CREATE INDEX "sprint_reports_sprint_idx" ON "public"."sprint_reports" USING "btree" ("sprint_id");



CREATE UNIQUE INDEX "sprints_one_active_per_project_idx" ON "public"."sprints" USING "btree" ("project_id") WHERE ("status" = 'active'::"text");



CREATE UNIQUE INDEX "user_notifications_dedupe_key_uidx" ON "public"."user_notifications" USING "btree" ("dedupe_key") WHERE ("dedupe_key" IS NOT NULL);



CREATE INDEX "user_notifications_organization_created_idx" ON "public"."user_notifications" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "user_notifications_project_created_idx" ON "public"."user_notifications" USING "btree" ("project_id", "created_at" DESC);



CREATE INDEX "user_notifications_user_read_created_idx" ON "public"."user_notifications" USING "btree" ("user_id", "read_at", "created_at" DESC);



CREATE OR REPLACE TRIGGER "enforce_single_active_sprint" BEFORE INSERT OR UPDATE ON "public"."sprints" FOR EACH ROW EXECUTE FUNCTION "public"."validate_single_active_sprint"();



CREATE OR REPLACE TRIGGER "ensure_epic_dependency_acyclic_before_write" BEFORE INSERT OR UPDATE OF "epic_id", "depends_on_epic_id" ON "public"."epic_dependencies" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_epic_dependency_acyclic"();



CREATE OR REPLACE TRIGGER "ensure_epic_dependency_same_project_before_write" BEFORE INSERT OR UPDATE OF "epic_id", "depends_on_epic_id" ON "public"."epic_dependencies" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_epic_dependency_same_project"();



CREATE OR REPLACE TRIGGER "ensure_task_dependency_acyclic_before_write" BEFORE INSERT OR UPDATE OF "task_id", "depends_on_task_id" ON "public"."task_dependencies" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_task_dependency_acyclic"();



CREATE OR REPLACE TRIGGER "ensure_task_dependency_same_project_before_write" BEFORE INSERT OR UPDATE OF "task_id", "depends_on_task_id" ON "public"."task_dependencies" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_task_dependency_same_project"();



CREATE OR REPLACE TRIGGER "ensure_task_epic_same_project_before_write" BEFORE INSERT OR UPDATE OF "project_id", "epic_id" ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_task_epic_same_project"();



CREATE OR REPLACE TRIGGER "evaluate_automation_rules_after_activity_event" AFTER INSERT ON "public"."activity_events" FOR EACH ROW EXECUTE FUNCTION "public"."evaluate_automation_rules_for_activity_event"();



CREATE OR REPLACE TRIGGER "normalize_activity_event_before_insert" BEFORE INSERT ON "public"."activity_events" FOR EACH ROW EXECUTE FUNCTION "public"."normalize_activity_event"();



CREATE OR REPLACE TRIGGER "normalize_sprint_report_before_write_trigger" BEFORE INSERT OR UPDATE ON "public"."sprint_reports" FOR EACH ROW EXECUTE FUNCTION "public"."normalize_sprint_report_before_write"();



CREATE OR REPLACE TRIGGER "organization_member_added_notification_trigger" AFTER INSERT ON "public"."organization_members" FOR EACH ROW EXECUTE FUNCTION "public"."create_organization_member_added_notification"();



CREATE OR REPLACE TRIGGER "project_member_added_notification_trigger" AFTER INSERT ON "public"."project_members" FOR EACH ROW EXECUTE FUNCTION "public"."create_project_member_added_notification"();



CREATE OR REPLACE TRIGGER "set_column_order_updated_at" BEFORE UPDATE ON "public"."column_order" FOR EACH ROW EXECUTE FUNCTION "public"."update_column_order_updated_at"();



CREATE OR REPLACE TRIGGER "set_columns_updated_at" BEFORE UPDATE ON "public"."columns" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_editor_notes_updated_at" BEFORE UPDATE ON "public"."editor_notes" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_tasks_updated_at" BEFORE UPDATE ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_user_profiles_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "sprint_completed_notifications_trigger" AFTER UPDATE OF "status" ON "public"."sprints" FOR EACH ROW EXECUTE FUNCTION "public"."create_sprint_completed_notifications"();



CREATE OR REPLACE TRIGGER "task_assignment_notification_trigger" AFTER INSERT OR UPDATE OF "assignee_id" ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."create_task_assignment_notification"();



CREATE OR REPLACE TRIGGER "touch_automation_rule_updated_at_before_write" BEFORE INSERT OR UPDATE ON "public"."automation_rules" FOR EACH ROW EXECUTE FUNCTION "public"."touch_automation_rule_updated_at"();



CREATE OR REPLACE TRIGGER "trigger_generate_epic_id" BEFORE INSERT ON "public"."epics" FOR EACH ROW EXECUTE FUNCTION "public"."generate_epic_id"();



CREATE OR REPLACE TRIGGER "trigger_generate_task_id" BEFORE INSERT ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."generate_task_id"();



ALTER TABLE ONLY "public"."activity_events"
    ADD CONSTRAINT "activity_events_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."activity_events"
    ADD CONSTRAINT "activity_events_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."activity_events"
    ADD CONSTRAINT "activity_events_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."activity_events"
    ADD CONSTRAINT "activity_events_sprint_id_fkey" FOREIGN KEY ("sprint_id") REFERENCES "public"."sprints"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."activity_events"
    ADD CONSTRAINT "activity_events_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."tasks"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."automation_rules"
    ADD CONSTRAINT "automation_rules_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."automation_rules"
    ADD CONSTRAINT "automation_rules_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."automation_rules"
    ADD CONSTRAINT "automation_rules_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."automation_runs"
    ADD CONSTRAINT "automation_runs_activity_event_id_fkey" FOREIGN KEY ("activity_event_id") REFERENCES "public"."activity_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."automation_runs"
    ADD CONSTRAINT "automation_runs_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."automation_runs"
    ADD CONSTRAINT "automation_runs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."automation_runs"
    ADD CONSTRAINT "automation_runs_rule_id_fkey" FOREIGN KEY ("rule_id") REFERENCES "public"."automation_rules"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."boards"
    ADD CONSTRAINT "boards_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."column_order"
    ADD CONSTRAINT "column_order_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."columns"
    ADD CONSTRAINT "columns_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "public"."boards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."columns"
    ADD CONSTRAINT "columns_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."editor_notes"
    ADD CONSTRAINT "editor_notes_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "public"."boards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."editor_notes"
    ADD CONSTRAINT "editor_notes_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."epic_dependencies"
    ADD CONSTRAINT "epic_dependencies_depends_on_epic_id_fkey" FOREIGN KEY ("depends_on_epic_id") REFERENCES "public"."epics"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."epic_dependencies"
    ADD CONSTRAINT "epic_dependencies_epic_id_fkey" FOREIGN KEY ("epic_id") REFERENCES "public"."epics"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."epics"
    ADD CONSTRAINT "epics_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."epics"
    ADD CONSTRAINT "epics_phase_id_fkey" FOREIGN KEY ("phase_id") REFERENCES "public"."epic_phases"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."epics"
    ADD CONSTRAINT "epics_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."epics"
    ADD CONSTRAINT "epics_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_invitations"
    ADD CONSTRAINT "organization_invitations_invitee_id_fkey" FOREIGN KEY ("invitee_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_invitations"
    ADD CONSTRAINT "organization_invitations_inviter_id_fkey" FOREIGN KEY ("inviter_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_invitations"
    ADD CONSTRAINT "organization_invitations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_members"
    ADD CONSTRAINT "organization_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."point_values"
    ADD CONSTRAINT "point_values_system_id_fkey" FOREIGN KEY ("system_id") REFERENCES "public"."point_systems"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_invitations"
    ADD CONSTRAINT "project_invitations_invitee_id_fkey" FOREIGN KEY ("invitee_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_invitations"
    ADD CONSTRAINT "project_invitations_inviter_id_fkey" FOREIGN KEY ("inviter_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_invitations"
    ADD CONSTRAINT "project_invitations_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_members"
    ADD CONSTRAINT "project_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_tags"
    ADD CONSTRAINT "project_tags_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roadmap_settings"
    ADD CONSTRAINT "roadmap_settings_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roadmap_settings"
    ADD CONSTRAINT "roadmap_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sprint_reports"
    ADD CONSTRAINT "sprint_reports_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sprint_reports"
    ADD CONSTRAINT "sprint_reports_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sprint_reports"
    ADD CONSTRAINT "sprint_reports_sprint_id_fkey" FOREIGN KEY ("sprint_id") REFERENCES "public"."sprints"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sprints"
    ADD CONSTRAINT "sprints_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_dependencies"
    ADD CONSTRAINT "task_dependencies_depends_on_task_id_fkey" FOREIGN KEY ("depends_on_task_id") REFERENCES "public"."tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_dependencies"
    ADD CONSTRAINT "task_dependencies_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_assignee_id_fkey" FOREIGN KEY ("assignee_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_column_id_fkey" FOREIGN KEY ("column_id") REFERENCES "public"."columns"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_epic_id_fkey" FOREIGN KEY ("epic_id") REFERENCES "public"."epics"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_issue_type_id_fkey" FOREIGN KEY ("issue_type_id") REFERENCES "public"."issue_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_parent_task_id_fkey" FOREIGN KEY ("parent_task_id") REFERENCES "public"."tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_priority_id_fkey" FOREIGN KEY ("priority_id") REFERENCES "public"."priorities"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_sprint_id_fkey" FOREIGN KEY ("sprint_id") REFERENCES "public"."sprints"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notifications"
    ADD CONSTRAINT "user_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Authenticated users can create organizations" ON "public"."organizations" FOR INSERT TO "authenticated" WITH CHECK (("created_by" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Invitees can view invited projects" ON "public"."projects" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."project_invitations" "invitation"
  WHERE (("invitation"."project_id" = "projects"."id") AND ("invitation"."invitee_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("invitation"."status" = 'pending'::"text")))));



CREATE POLICY "Members can update project tasks" ON "public"."tasks" FOR UPDATE TO "authenticated" USING ("public"."is_project_member"("project_id")) WITH CHECK ("public"."is_project_member"("project_id"));



CREATE POLICY "Members can view column order" ON "public"."column_order" FOR SELECT TO "authenticated" USING ("public"."is_project_member"("project_id"));



CREATE POLICY "Members can view organization members" ON "public"."organization_members" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_organization_member"("organization_id")));



CREATE POLICY "Members can view organizations" ON "public"."organizations" FOR SELECT TO "authenticated" USING ("public"."is_organization_member"("id"));



CREATE POLICY "Members can view project columns" ON "public"."columns" FOR SELECT TO "authenticated" USING ("public"."is_project_member"("project_id"));



CREATE POLICY "Members can view project sprints" ON "public"."sprints" FOR SELECT TO "authenticated" USING ("public"."is_project_member"("project_id"));



CREATE POLICY "Members can view project tags" ON "public"."project_tags" FOR SELECT TO "authenticated" USING ("public"."is_project_member"("project_id"));



CREATE POLICY "Members can view project tasks" ON "public"."tasks" FOR SELECT TO "authenticated" USING ("public"."is_project_member"("project_id"));



CREATE POLICY "Organization admins can add members" ON "public"."organization_members" FOR INSERT TO "authenticated" WITH CHECK ("public"."is_organization_admin"("organization_id"));



CREATE POLICY "Organization admins can create invitations" ON "public"."organization_invitations" FOR INSERT TO "authenticated" WITH CHECK ((("inviter_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("invitee_id" <> ( SELECT "auth"."uid"() AS "uid")) AND "public"."is_organization_admin"("organization_id") AND (NOT (EXISTS ( SELECT 1
   FROM "public"."organization_members" "member"
  WHERE (("member"."organization_id" = "organization_invitations"."organization_id") AND ("member"."user_id" = "organization_invitations"."invitee_id")))))));



CREATE POLICY "Organization admins can remove members" ON "public"."organization_members" FOR DELETE TO "authenticated" USING ("public"."is_organization_admin"("organization_id"));



CREATE POLICY "Organization admins can update members" ON "public"."organization_members" FOR UPDATE TO "authenticated" USING ("public"."is_organization_admin"("organization_id")) WITH CHECK ("public"."is_organization_admin"("organization_id"));



CREATE POLICY "Organization admins can update organizations" ON "public"."organizations" FOR UPDATE TO "authenticated" USING ("public"."is_organization_admin"("id")) WITH CHECK ("public"."is_organization_admin"("id"));



CREATE POLICY "Organization invitation participants can view invitations" ON "public"."organization_invitations" FOR SELECT TO "authenticated" USING ((("invitee_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("inviter_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_organization_admin"("organization_id")));



CREATE POLICY "Organization members can create projects" ON "public"."projects" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND "public"."is_organization_member"("organization_id")));



CREATE POLICY "Organization members can view visible column order" ON "public"."column_order" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Organization members can view visible project columns" ON "public"."columns" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Organization members can view visible project epics" ON "public"."epics" FOR SELECT TO "authenticated" USING ((("project_id" IS NOT NULL) AND "public"."can_view_project"("project_id")));



CREATE POLICY "Organization members can view visible project notes" ON "public"."editor_notes" FOR SELECT TO "authenticated" USING ((("project_id" IS NOT NULL) AND "public"."can_view_project"("project_id")));



CREATE POLICY "Organization members can view visible project sprints" ON "public"."sprints" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Organization members can view visible project tags" ON "public"."project_tags" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Organization members can view visible project tasks" ON "public"."tasks" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Organization members can view visible roadmap settings" ON "public"."roadmap_settings" FOR SELECT TO "authenticated" USING ((("project_id" IS NOT NULL) AND "public"."can_view_project"("project_id")));



CREATE POLICY "Project members can view related invitations" ON "public"."project_invitations" FOR SELECT TO "authenticated" USING ((("invitee_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("inviter_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."is_project_member"("project_id")));



CREATE POLICY "Project owners can add organization members" ON "public"."project_members" FOR INSERT TO "authenticated" WITH CHECK (((("role" = 'owner'::"text") AND ("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."projects" "project"
  WHERE (("project"."id" = "project_members"."project_id") AND ("project"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))) OR ("public"."is_project_owner"("project_id") AND (EXISTS ( SELECT 1
   FROM "public"."projects" "project"
  WHERE (("project"."id" = "project_members"."project_id") AND "public"."is_organization_member"("project"."organization_id")))) AND (EXISTS ( SELECT 1
   FROM ("public"."organization_members" "org_member"
     JOIN "public"."projects" "project" ON (("project"."organization_id" = "org_member"."organization_id")))
  WHERE (("project"."id" = "project_members"."project_id") AND ("org_member"."user_id" = "project_members"."user_id")))))));



CREATE POLICY "Project owners can create automation rules" ON "public"."automation_rules" FOR INSERT TO "authenticated" WITH CHECK (("public"."can_manage_project"("project_id") AND (EXISTS ( SELECT 1
   FROM "public"."projects" "project"
  WHERE (("project"."id" = "automation_rules"."project_id") AND ("project"."organization_id" = "project"."organization_id"))))));



CREATE POLICY "Project owners can create invitations" ON "public"."project_invitations" FOR INSERT TO "authenticated" WITH CHECK ((("inviter_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("invitee_id" <> ( SELECT "auth"."uid"() AS "uid")) AND "public"."is_project_owner"("project_id") AND (NOT (EXISTS ( SELECT 1
   FROM "public"."project_members" "existing_member"
  WHERE (("existing_member"."project_id" = "project_invitations"."project_id") AND ("existing_member"."user_id" = "project_invitations"."invitee_id")))))));



CREATE POLICY "Project owners can delete automation rules" ON "public"."automation_rules" FOR DELETE TO "authenticated" USING ("public"."can_manage_project"("project_id"));



CREATE POLICY "Project owners can delete projects" ON "public"."projects" FOR DELETE TO "authenticated" USING ("public"."is_project_owner"("id"));



CREATE POLICY "Project owners can remove members" ON "public"."project_members" FOR DELETE TO "authenticated" USING ("public"."is_project_owner"("project_id"));



CREATE POLICY "Project owners can update automation rules" ON "public"."automation_rules" FOR UPDATE TO "authenticated" USING ("public"."can_manage_project"("project_id")) WITH CHECK (("public"."can_manage_project"("project_id") AND (EXISTS ( SELECT 1
   FROM "public"."projects" "project"
  WHERE (("project"."id" = "automation_rules"."project_id") AND ("project"."organization_id" = "project"."organization_id"))))));



CREATE POLICY "Project owners can update members" ON "public"."project_members" FOR UPDATE TO "authenticated" USING ("public"."is_project_owner"("project_id")) WITH CHECK ("public"."is_project_owner"("project_id"));



CREATE POLICY "Project owners can update projects" ON "public"."projects" FOR UPDATE TO "authenticated" USING ("public"."is_project_owner"("id")) WITH CHECK (("public"."is_project_owner"("id") AND "public"."is_organization_member"("organization_id")));



CREATE POLICY "Project viewers can read sprint reports" ON "public"."sprint_reports" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Users can create column order in their boards" ON "public"."column_order" FOR INSERT TO "authenticated" WITH CHECK (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can create notes in their boards" ON "public"."editor_notes" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."boards"
  WHERE (("boards"."id" = "editor_notes"."board_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create project notes" ON "public"."editor_notes" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "editor_notes"."project_id") AND ("projects"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Users can create tasks in their boards" ON "public"."tasks" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."boards" ON (("boards"."id" = "columns"."board_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create their own boards" ON "public"."boards" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete column order from their projects" ON "public"."column_order" FOR DELETE USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can delete column order of their boards" ON "public"."column_order" FOR DELETE TO "authenticated" USING (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can delete columns from their projects" ON "public"."columns" FOR DELETE USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can delete notes of their boards" ON "public"."editor_notes" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."boards"
  WHERE (("boards"."id" = "editor_notes"."board_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete own projects" ON "public"."projects" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete project notes" ON "public"."editor_notes" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "editor_notes"."project_id") AND ("projects"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Users can delete sprints in their projects" ON "public"."sprints" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "sprints"."project_id") AND ("projects"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete task dependencies" ON "public"."task_dependencies" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ((("public"."tasks" "dependent_task"
     LEFT JOIN "public"."projects" "direct_project" ON (("direct_project"."id" = "dependent_task"."project_id")))
     LEFT JOIN "public"."columns" "dependent_column" ON (("dependent_column"."id" = "dependent_task"."column_id")))
     LEFT JOIN "public"."projects" "column_project" ON (("column_project"."id" = "dependent_column"."project_id")))
  WHERE (("dependent_task"."id" = "task_dependencies"."task_id") AND (("direct_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("column_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "Users can delete tasks from their projects" ON "public"."tasks" FOR DELETE USING (("column_id" IN ( SELECT "c"."id"
   FROM ("public"."columns" "c"
     JOIN "public"."projects" "p" ON (("c"."project_id" = "p"."id")))
  WHERE ("p"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can delete tasks in their projects" ON "public"."tasks" FOR DELETE USING (((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "tasks"."project_id") AND ("projects"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."projects" ON (("projects"."id" = "columns"."project_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("projects"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can delete tasks of their boards" ON "public"."tasks" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."boards" ON (("boards"."id" = "columns"."board_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can delete their own boards" ON "public"."boards" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert column order to their projects" ON "public"."column_order" FOR INSERT WITH CHECK (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can insert columns to their projects" ON "public"."columns" FOR INSERT WITH CHECK (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can insert own profile" ON "public"."user_profiles" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users can insert own projects" ON "public"."projects" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert sprints in their projects" ON "public"."sprints" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "sprints"."project_id") AND ("projects"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can insert task dependencies" ON "public"."task_dependencies" FOR INSERT TO "authenticated" WITH CHECK (((EXISTS ( SELECT 1
   FROM ((("public"."tasks" "dependent_task"
     LEFT JOIN "public"."projects" "direct_project" ON (("direct_project"."id" = "dependent_task"."project_id")))
     LEFT JOIN "public"."columns" "dependent_column" ON (("dependent_column"."id" = "dependent_task"."column_id")))
     LEFT JOIN "public"."projects" "column_project" ON (("column_project"."id" = "dependent_column"."project_id")))
  WHERE (("dependent_task"."id" = "task_dependencies"."task_id") AND (("direct_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("column_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))) AND (EXISTS ( SELECT 1
   FROM ((("public"."tasks" "source_task"
     LEFT JOIN "public"."projects" "direct_project" ON (("direct_project"."id" = "source_task"."project_id")))
     LEFT JOIN "public"."columns" "source_column" ON (("source_column"."id" = "source_task"."column_id")))
     LEFT JOIN "public"."projects" "column_project" ON (("column_project"."id" = "source_column"."project_id")))
  WHERE (("source_task"."id" = "task_dependencies"."depends_on_task_id") AND (("direct_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("column_project"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "Users can insert tasks in their projects" ON "public"."tasks" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "tasks"."project_id") AND ("projects"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."projects" ON (("projects"."id" = "columns"."project_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("projects"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can insert tasks to their projects" ON "public"."tasks" FOR INSERT WITH CHECK (("column_id" IN ( SELECT "c"."id"
   FROM ("public"."columns" "c"
     JOIN "public"."projects" "p" ON (("c"."project_id" = "p"."id")))
  WHERE ("p"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can insert their roadmap settings" ON "public"."roadmap_settings" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can join owned organization on creation" ON "public"."organization_members" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("role" = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "organization"
  WHERE (("organization"."id" = "organization_members"."organization_id") AND ("organization"."created_by" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "Users can manage epic dependencies" ON "public"."epic_dependencies" USING ((EXISTS ( SELECT 1
   FROM "public"."epics"
  WHERE (("epics"."id" = "epic_dependencies"."epic_id") AND ("epics"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can manage tags of own projects" ON "public"."project_tags" USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "project_tags"."project_id") AND ("projects"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can read task dependencies" ON "public"."task_dependencies" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM ((("public"."tasks" "dependent_task"
     LEFT JOIN "public"."projects" "direct_project" ON (("direct_project"."id" = "dependent_task"."project_id")))
     LEFT JOIN "public"."columns" "dependent_column" ON (("dependent_column"."id" = "dependent_task"."column_id")))
     LEFT JOIN "public"."projects" "column_project" ON (("column_project"."id" = "dependent_column"."project_id")))
  WHERE (("dependent_task"."id" = "task_dependencies"."task_id") AND (("direct_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("column_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))) AND (EXISTS ( SELECT 1
   FROM ((("public"."tasks" "source_task"
     LEFT JOIN "public"."projects" "direct_project" ON (("direct_project"."id" = "source_task"."project_id")))
     LEFT JOIN "public"."columns" "source_column" ON (("source_column"."id" = "source_task"."column_id")))
     LEFT JOIN "public"."projects" "column_project" ON (("column_project"."id" = "source_column"."project_id")))
  WHERE (("source_task"."id" = "task_dependencies"."depends_on_task_id") AND (("direct_project"."user_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("column_project"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "Users can read their roadmap settings" ON "public"."roadmap_settings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can update column order from their projects" ON "public"."column_order" FOR UPDATE USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can update column order of their boards" ON "public"."column_order" FOR UPDATE TO "authenticated" USING (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"())))) WITH CHECK (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can update columns from their projects" ON "public"."columns" FOR UPDATE USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can update notes of their boards" ON "public"."editor_notes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."boards"
  WHERE (("boards"."id" = "editor_notes"."board_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update own notifications" ON "public"."user_notifications" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update own profile" ON "public"."user_profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "Users can update own projects" ON "public"."projects" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update project notes" ON "public"."editor_notes" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "editor_notes"."project_id") AND ("projects"."user_id" = ( SELECT "auth"."uid"() AS "uid")))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "editor_notes"."project_id") AND ("projects"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Users can update sprints in their projects" ON "public"."sprints" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "sprints"."project_id") AND ("projects"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "sprints"."project_id") AND ("projects"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update tasks from their projects" ON "public"."tasks" FOR UPDATE USING (("column_id" IN ( SELECT "c"."id"
   FROM ("public"."columns" "c"
     JOIN "public"."projects" "p" ON (("c"."project_id" = "p"."id")))
  WHERE ("p"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can update tasks in their projects" ON "public"."tasks" FOR UPDATE USING (((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "tasks"."project_id") AND ("projects"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."projects" ON (("projects"."id" = "columns"."project_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("projects"."user_id" = "auth"."uid"())))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "tasks"."project_id") AND ("projects"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."projects" ON (("projects"."id" = "columns"."project_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("projects"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can update tasks of their boards" ON "public"."tasks" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."boards" ON (("boards"."id" = "columns"."board_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update their own boards" ON "public"."boards" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their roadmap settings" ON "public"."roadmap_settings" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can view accessible activity events" ON "public"."activity_events" FOR SELECT TO "authenticated" USING (((("project_id" IS NOT NULL) AND "public"."can_view_project"("project_id")) OR (("project_id" IS NULL) AND ("organization_id" IS NOT NULL) AND "public"."can_view_organization"("organization_id"))));



CREATE POLICY "Users can view accessible automation rules" ON "public"."automation_rules" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Users can view accessible automation runs" ON "public"."automation_runs" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("project_id"));



CREATE POLICY "Users can view accessible project members" ON "public"."project_members" FOR SELECT TO "authenticated" USING ((("user_id" = ( SELECT "auth"."uid"() AS "uid")) OR "public"."can_view_project"("project_id")));



CREATE POLICY "Users can view accessible projects" ON "public"."projects" FOR SELECT TO "authenticated" USING ("public"."can_view_project"("id"));



CREATE POLICY "Users can view column order from their projects" ON "public"."column_order" FOR SELECT USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view column order of their boards" ON "public"."column_order" FOR SELECT TO "authenticated" USING (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view columns from their projects" ON "public"."columns" FOR SELECT USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view notes of their boards" ON "public"."editor_notes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."boards"
  WHERE (("boards"."id" = "editor_notes"."board_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view own notifications" ON "public"."user_notifications" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view own projects" ON "public"."projects" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view profiles" ON "public"."user_profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Users can view project notes" ON "public"."editor_notes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "editor_notes"."project_id") AND ("projects"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Users can view sprints from their projects" ON "public"."sprints" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "sprints"."project_id") AND ("projects"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view tasks from their projects" ON "public"."tasks" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."projects"
  WHERE (("projects"."id" = "tasks"."project_id") AND ("projects"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."projects" ON (("projects"."id" = "columns"."project_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("projects"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can view tasks of their boards" ON "public"."tasks" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."columns"
     JOIN "public"."boards" ON (("boards"."id" = "columns"."board_id")))
  WHERE (("columns"."id" = "tasks"."column_id") AND ("boards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view their own boards" ON "public"."boards" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."activity_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."automation_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."automation_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."boards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."column_order" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."columns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "columns_delete_policy" ON "public"."columns" FOR DELETE TO "authenticated" USING (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "columns_insert_policy" ON "public"."columns" FOR INSERT TO "authenticated" WITH CHECK (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "columns_select_policy" ON "public"."columns" FOR SELECT TO "authenticated" USING (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



CREATE POLICY "columns_update_policy" ON "public"."columns" FOR UPDATE TO "authenticated" USING (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"())))) WITH CHECK (("board_id" IN ( SELECT "boards"."id"
   FROM "public"."boards"
  WHERE ("boards"."user_id" = "auth"."uid"()))));



ALTER TABLE "public"."command_jobs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."editor_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."epic_dependencies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_invitations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organization_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."project_invitations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."project_members" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."project_tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."roadmap_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sprint_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sprints" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."task_dependencies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_organization_invitation"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_organization_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_organization_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_organization_invitation"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_organization_invitation_command"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_organization_invitation_command"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_organization_invitation_command"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_project_invitation"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_project_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_project_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_project_invitation"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."accept_project_invitation_command"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."accept_project_invitation_command"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_project_invitation_command"("p_invitation_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."project_members" TO "anon";
GRANT ALL ON TABLE "public"."project_members" TO "authenticated";
GRANT ALL ON TABLE "public"."project_members" TO "service_role";



REVOKE ALL ON FUNCTION "public"."add_project_member_command"("p_project_id" "uuid", "p_user_id" "uuid", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."add_project_member_command"("p_project_id" "uuid", "p_user_id" "uuid", "p_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_project_member_command"("p_project_id" "uuid", "p_user_id" "uuid", "p_role" "text") TO "service_role";



GRANT ALL ON TABLE "public"."tasks" TO "anon";
GRANT ALL ON TABLE "public"."tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."tasks" TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_task_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_assignee_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_task_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_assignee_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_task_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_assignee_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."activity_events" TO "anon";
GRANT ALL ON TABLE "public"."activity_events" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_events" TO "service_role";



REVOKE ALL ON FUNCTION "public"."automation_condition_matches"("p_condition" "jsonb", "p_event" "public"."activity_events") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."automation_condition_matches"("p_condition" "jsonb", "p_event" "public"."activity_events") TO "service_role";



REVOKE ALL ON FUNCTION "public"."automation_event_value"("p_event" "public"."activity_events", "p_field" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."automation_event_value"("p_event" "public"."activity_events", "p_field" "text") TO "service_role";



GRANT ALL ON TABLE "public"."automation_rules" TO "anon";
GRANT ALL ON TABLE "public"."automation_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."automation_rules" TO "service_role";



REVOKE ALL ON FUNCTION "public"."automation_rule_matches_event"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."automation_rule_matches_event"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_add_project_member"("p_project_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_add_project_member"("p_project_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_add_project_member"("p_project_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_assign_project_user"("p_project_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_assign_project_user"("p_project_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_assign_project_user"("p_project_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_create_project_in_organization"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_create_project_in_organization"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_create_project_in_organization"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_edit_project"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_edit_project"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_edit_project"("p_project_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_invite_to_organization"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_invite_to_organization"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_invite_to_organization"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_invite_to_project"("p_project_id" "uuid", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_invite_to_project"("p_project_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_invite_to_project"("p_project_id" "uuid", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_manage_organization"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_manage_organization"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_manage_organization"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_manage_project"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_manage_project"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_manage_project"("p_project_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_mutate_project"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_mutate_project"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_mutate_project"("p_project_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_view_organization"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_view_organization"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_view_organization"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."can_view_project"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_view_project"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_view_project"("p_project_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."command_jobs" TO "anon";
GRANT ALL ON TABLE "public"."command_jobs" TO "authenticated";
GRANT ALL ON TABLE "public"."command_jobs" TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_command_jobs"("p_queue_name" "text", "p_limit" integer, "p_worker_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_command_jobs"("p_queue_name" "text", "p_limit" integer, "p_worker_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_command_job"("p_job_id" "uuid", "p_worker_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_command_job"("p_job_id" "uuid", "p_worker_id" "text") TO "service_role";



GRANT ALL ON TABLE "public"."sprints" TO "anon";
GRANT ALL ON TABLE "public"."sprints" TO "authenticated";
GRANT ALL ON TABLE "public"."sprints" TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_sprint_command"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_dispositions" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_sprint_command"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_dispositions" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_sprint_command"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_dispositions" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_organization_command"("p_name" "text", "p_logo_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_organization_command"("p_name" "text", "p_logo_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_command"("p_name" "text", "p_logo_url" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_organization_invitation_command"("p_organization_id" "uuid", "p_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_organization_invitation_command"("p_organization_id" "uuid", "p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_invitation_command"("p_organization_id" "uuid", "p_email" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_organization_invitation_for_user_command"("p_organization_id" "uuid", "p_invitee_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_organization_invitation_for_user_command"("p_organization_id" "uuid", "p_invitee_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_invitation_for_user_command"("p_organization_id" "uuid", "p_invitee_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_organization_member_added_notification"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_organization_member_added_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_member_added_notification"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_organization_with_owner"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_organization_with_owner"("p_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_organization_with_owner"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_with_owner"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_project_command"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_project_command"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_project_command"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_project_invitation_command"("p_project_id" "uuid", "p_invitee_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_project_invitation_command"("p_project_id" "uuid", "p_invitee_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_project_invitation_command"("p_project_id" "uuid", "p_invitee_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_project_member_added_notification"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_project_member_added_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_project_member_added_notification"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_project_with_defaults"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_project_with_defaults"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_project_with_defaults"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_project_with_defaults"("p_title" "text", "p_description" "text", "p_project_key" "text", "p_organization_id" "uuid", "p_tags" "text"[], "p_visibility" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_sprint_completed_notifications"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_sprint_completed_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_sprint_completed_notifications"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_task_assignment_notification"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_task_assignment_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_task_assignment_notification"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_task_command"("p_project_id" "uuid", "p_title" "text", "p_subtitle" "text", "p_description" "text", "p_destination" "text", "p_column_id" "uuid", "p_sprint_id" "uuid", "p_position" integer, "p_issue_type_id" "uuid", "p_priority_id" "uuid", "p_story_points" "text", "p_assignee_id" "uuid", "p_epic_id" "uuid", "p_github_link" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_task_command"("p_project_id" "uuid", "p_title" "text", "p_subtitle" "text", "p_description" "text", "p_destination" "text", "p_column_id" "uuid", "p_sprint_id" "uuid", "p_position" integer, "p_issue_type_id" "uuid", "p_priority_id" "uuid", "p_story_points" "text", "p_assignee_id" "uuid", "p_epic_id" "uuid", "p_github_link" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_task_command"("p_project_id" "uuid", "p_title" "text", "p_subtitle" "text", "p_description" "text", "p_destination" "text", "p_column_id" "uuid", "p_sprint_id" "uuid", "p_position" integer, "p_issue_type_id" "uuid", "p_priority_id" "uuid", "p_story_points" "text", "p_assignee_id" "uuid", "p_epic_id" "uuid", "p_github_link" "text") TO "service_role";



GRANT ALL ON TABLE "public"."user_notifications" TO "anon";
GRANT ALL ON TABLE "public"."user_notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."user_notifications" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_user_notification"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_message" "text", "p_actor_id" "uuid", "p_organization_id" "uuid", "p_project_id" "uuid", "p_task_id" "uuid", "p_payload" "jsonb", "p_dedupe_key" "text", "p_skip_if_actor" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_user_notification"("p_user_id" "uuid", "p_type" "text", "p_title" "text", "p_message" "text", "p_actor_id" "uuid", "p_organization_id" "uuid", "p_project_id" "uuid", "p_task_id" "uuid", "p_payload" "jsonb", "p_dedupe_key" "text", "p_skip_if_actor" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_organization_role"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_organization_role"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_role"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_project_role"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_project_role"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_project_role"("p_project_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."decline_organization_invitation"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decline_organization_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decline_organization_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_organization_invitation"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."decline_organization_invitation_command"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decline_organization_invitation_command"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_organization_invitation_command"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."decline_project_invitation"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decline_project_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decline_project_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_project_invitation"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."decline_project_invitation_command"("p_invitation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decline_project_invitation_command"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_project_invitation_command"("p_invitation_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."enqueue_command_job"("p_queue_name" "text", "p_job_type" "text", "p_payload" "jsonb", "p_delay_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enqueue_command_job"("p_queue_name" "text", "p_job_type" "text", "p_payload" "jsonb", "p_delay_seconds" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_epic_dependency_acyclic"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_epic_dependency_acyclic"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_epic_dependency_acyclic"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_epic_dependency_same_project"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_epic_dependency_same_project"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_epic_dependency_same_project"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_task_dependency_acyclic"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_task_dependency_acyclic"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_task_dependency_acyclic"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_task_dependency_same_project"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_task_dependency_same_project"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_task_dependency_same_project"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_task_epic_same_project"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_task_epic_same_project"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_task_epic_same_project"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."evaluate_automation_rules_for_activity_event"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."evaluate_automation_rules_for_activity_event"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."execute_automation_action"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events", "p_run_id" "uuid", "p_action" "jsonb", "p_action_index" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."execute_automation_action"("p_rule" "public"."automation_rules", "p_event" "public"."activity_events", "p_run_id" "uuid", "p_action" "jsonb", "p_action_index" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."fail_command_job"("p_job_id" "uuid", "p_error" "text", "p_retry_delay_seconds" integer, "p_worker_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fail_command_job"("p_job_id" "uuid", "p_error" "text", "p_retry_delay_seconds" integer, "p_worker_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_epic_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_epic_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_epic_id"() TO "service_role";



GRANT ALL ON TABLE "public"."sprint_reports" TO "service_role";
GRANT SELECT ON TABLE "public"."sprint_reports" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."generate_sprint_report"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_actor_id" "uuid", "p_dispositions" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."generate_sprint_report"("p_project_id" "uuid", "p_sprint_id" "uuid", "p_actor_id" "uuid", "p_dispositions" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_task_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_task_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_task_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user_profile"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user_profile"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_organization_admin"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_organization_admin"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_organization_admin"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_organization_member"("p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_organization_member"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_organization_member"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_project_member"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_project_member"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_project_member"("p_project_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_project_owner"("p_project_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_project_owner"("p_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_project_owner"("p_project_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."move_task_column_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_column_id" "uuid", "p_position" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."move_task_column_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_column_id" "uuid", "p_position" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."move_task_column_command"("p_project_id" "uuid", "p_task_id" "uuid", "p_column_id" "uuid", "p_position" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."normalize_activity_event"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_activity_event"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."normalize_sprint_report_before_write"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_sprint_report_before_write"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_activity_event"("p_event_type" "text", "p_organization_id" "uuid", "p_project_id" "uuid", "p_sprint_id" "uuid", "p_task_id" "uuid", "p_actor_id" "uuid", "p_payload" "jsonb", "p_event_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_activity_event"("p_event_type" "text", "p_organization_id" "uuid", "p_project_id" "uuid", "p_sprint_id" "uuid", "p_task_id" "uuid", "p_actor_id" "uuid", "p_payload" "jsonb", "p_event_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_organization_member_command"("p_organization_id" "uuid", "p_member_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_organization_member_command"("p_organization_id" "uuid", "p_member_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_organization_member_command"("p_organization_id" "uuid", "p_member_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_project_member_command"("p_project_id" "uuid", "p_member_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."remove_project_member_command"("p_project_id" "uuid", "p_member_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_project_member_command"("p_project_id" "uuid", "p_member_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reset_stale_command_jobs"("p_timeout_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_stale_command_jobs"("p_timeout_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."run_command_job_maintenance"("p_stale_timeout_seconds" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."run_command_job_maintenance"("p_stale_timeout_seconds" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."scan_sprint_deadlines"("p_today" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."scan_sprint_deadlines"("p_today" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."story_points_to_number"("p_value" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."story_points_to_number"("p_value" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."touch_automation_rule_updated_at"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."touch_automation_rule_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_column_order_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_column_order_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_column_order_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."organization_members" TO "anon";
GRANT ALL ON TABLE "public"."organization_members" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_members" TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_organization_member_role_command"("p_organization_id" "uuid", "p_member_id" "uuid", "p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_organization_member_role_command"("p_organization_id" "uuid", "p_member_id" "uuid", "p_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_organization_member_role_command"("p_organization_id" "uuid", "p_member_id" "uuid", "p_role" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_single_active_sprint"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_single_active_sprint"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_single_active_sprint"() TO "service_role";



GRANT ALL ON TABLE "public"."automation_runs" TO "anon";
GRANT ALL ON TABLE "public"."automation_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."automation_runs" TO "service_role";



GRANT ALL ON TABLE "public"."boards" TO "anon";
GRANT ALL ON TABLE "public"."boards" TO "authenticated";
GRANT ALL ON TABLE "public"."boards" TO "service_role";



GRANT ALL ON TABLE "public"."column_order" TO "anon";
GRANT ALL ON TABLE "public"."column_order" TO "authenticated";
GRANT ALL ON TABLE "public"."column_order" TO "service_role";



GRANT ALL ON TABLE "public"."columns" TO "anon";
GRANT ALL ON TABLE "public"."columns" TO "authenticated";
GRANT ALL ON TABLE "public"."columns" TO "service_role";



GRANT ALL ON TABLE "public"."editor_notes" TO "anon";
GRANT ALL ON TABLE "public"."editor_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."editor_notes" TO "service_role";



GRANT ALL ON TABLE "public"."epic_dependencies" TO "anon";
GRANT ALL ON TABLE "public"."epic_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."epic_dependencies" TO "service_role";



GRANT ALL ON TABLE "public"."epic_phases" TO "anon";
GRANT ALL ON TABLE "public"."epic_phases" TO "authenticated";
GRANT ALL ON TABLE "public"."epic_phases" TO "service_role";



GRANT ALL ON TABLE "public"."epics" TO "anon";
GRANT ALL ON TABLE "public"."epics" TO "authenticated";
GRANT ALL ON TABLE "public"."epics" TO "service_role";



GRANT ALL ON TABLE "public"."issue_types" TO "anon";
GRANT ALL ON TABLE "public"."issue_types" TO "authenticated";
GRANT ALL ON TABLE "public"."issue_types" TO "service_role";



GRANT ALL ON TABLE "public"."organization_invitations" TO "anon";
GRANT ALL ON TABLE "public"."organization_invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_invitations" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."point_systems" TO "anon";
GRANT ALL ON TABLE "public"."point_systems" TO "authenticated";
GRANT ALL ON TABLE "public"."point_systems" TO "service_role";



GRANT ALL ON TABLE "public"."point_values" TO "anon";
GRANT ALL ON TABLE "public"."point_values" TO "authenticated";
GRANT ALL ON TABLE "public"."point_values" TO "service_role";



GRANT ALL ON TABLE "public"."priorities" TO "anon";
GRANT ALL ON TABLE "public"."priorities" TO "authenticated";
GRANT ALL ON TABLE "public"."priorities" TO "service_role";



GRANT ALL ON TABLE "public"."project_invitations" TO "anon";
GRANT ALL ON TABLE "public"."project_invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."project_invitations" TO "service_role";



GRANT ALL ON TABLE "public"."project_tags" TO "anon";
GRANT ALL ON TABLE "public"."project_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."project_tags" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."roadmap_settings" TO "anon";
GRANT ALL ON TABLE "public"."roadmap_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."roadmap_settings" TO "service_role";



GRANT ALL ON TABLE "public"."task_dependencies" TO "anon";
GRANT ALL ON TABLE "public"."task_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."task_dependencies" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







