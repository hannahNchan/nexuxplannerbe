import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type AgentCommandAction = "validate_plan" | "apply_plan";

type AgentCommandRequest = {
  action: AgentCommandAction;
  payload?: {
    plan?: unknown;
    dry_run?: boolean;
  };
};

type PlanRecord = Record<string, unknown>;

type OperationSummary = {
  organizations: number;
  projects: number;
  epics: number;
  sprints: number;
  tasks: number;
  scheduledTasks: number;
};

const isRecord = (value: unknown): value is PlanRecord =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const asString = (value: unknown): string | null =>
  typeof value === "string" && value.trim() ? value.trim() : null;

const asArray = (value: unknown): PlanRecord[] =>
  Array.isArray(value) ? value.filter(isRecord) : [];

const getRef = (value: PlanRecord, fallback: string): string =>
  asString(value.ref) ?? asString(value.key) ?? asString(value.id) ?? fallback;

const getProjectKey = (project: PlanRecord): string | null =>
  asString(project.project_key) ?? asString(project.key);

const getTaskStartDate = (task: PlanRecord): string | null =>
  asString(task.planned_start_date) ?? asString(task.start_date) ?? asString(task.start);

const getTaskEndDate = (task: PlanRecord, fallback: string): string =>
  asString(task.planned_end_date) ?? asString(task.end_date) ?? asString(task.end) ?? fallback;

const createEmptySummary = (): OperationSummary => ({
  organizations: 0,
  projects: 0,
  epics: 0,
  sprints: 0,
  tasks: 0,
  scheduledTasks: 0,
});

const validatePlan = (plan: unknown) => {
  const errors: string[] = [];
  const warnings: string[] = [];
  const operations = createEmptySummary();

  if (!isRecord(plan)) {
    return {
      ok: false,
      errors: ["El plan debe ser un objeto JSON."],
      warnings,
      operations,
    };
  }

  const organization = isRecord(plan.organization) ? plan.organization : null;
  if (!organization) {
    errors.push("El plan necesita organization.");
  } else if (!asString(organization.id) && !asString(organization.name)) {
    errors.push("organization necesita id o name.");
  } else if (!asString(organization.id)) {
    operations.organizations = 1;
  }

  const projects = asArray(plan.projects);
  if (projects.length === 0) {
    errors.push("El plan necesita al menos un proyecto en projects[].");
  }

  projects.forEach((project, projectIndex) => {
    const projectPath = `projects[${projectIndex}]`;
    const projectId = asString(project.id);
    const title = asString(project.title) ?? asString(project.name);
    const projectKey = getProjectKey(project);

    if (!projectId && !title) {
      errors.push(`${projectPath} necesita id o title.`);
    }

    if (!projectId && !projectKey) {
      errors.push(`${projectPath} necesita project_key/key para crear proyecto.`);
    }

    if (!projectId) operations.projects += 1;

    const sprints = asArray(project.sprints);
    const epics = asArray(project.epics);
    const tasks = asArray(project.tasks);

    operations.sprints += sprints.filter((sprint) => !asString(sprint.id)).length;
    operations.epics += epics.filter((epic) => !asString(epic.id)).length;
    operations.tasks += tasks.filter((task) => !asString(task.id)).length;

    sprints.forEach((sprint, sprintIndex) => {
      const sprintPath = `${projectPath}.sprints[${sprintIndex}]`;
      const duration = asString(sprint.duration) ?? "7d";
      if (!asString(sprint.id) && !asString(sprint.name)) {
        errors.push(`${sprintPath} necesita id o name.`);
      }
      if (!["7d", "15d", "1m"].includes(duration)) {
        errors.push(`${sprintPath}.duration debe ser 7d, 15d o 1m.`);
      }
    });

    epics.forEach((epic, epicIndex) => {
      const epicPath = `${projectPath}.epics[${epicIndex}]`;
      if (!asString(epic.id) && !asString(epic.name) && !asString(epic.title)) {
        errors.push(`${epicPath} necesita id, name o title.`);
      }
      const startDate = asString(epic.start_date) ?? asString(epic.start);
      const endDate = asString(epic.end_date) ?? asString(epic.end);
      if (startDate && endDate && endDate < startDate) {
        errors.push(`${epicPath} tiene end_date anterior a start_date.`);
      }
    });

    tasks.forEach((task, taskIndex) => {
      const taskPath = `${projectPath}.tasks[${taskIndex}]`;
      if (!asString(task.id) && !asString(task.title) && !asString(task.name)) {
        errors.push(`${taskPath} necesita id, title o name.`);
      }
      const startDate = getTaskStartDate(task);
      const endDate = startDate ? getTaskEndDate(task, startDate) : null;
      if (startDate) operations.scheduledTasks += 1;
      if (startDate && endDate && endDate < startDate) {
        errors.push(`${taskPath} tiene fecha final anterior a fecha inicial.`);
      }
      if (!startDate && (asString(task.end_date) || asString(task.end) || asString(task.planned_end_date))) {
        warnings.push(`${taskPath} tiene fecha final sin inicio; el servidor no la planificará.`);
      }
    });
  });

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    operations,
  };
};

const rpcSingle = async (
  supabase: ReturnType<typeof createClient>,
  rpcName: string,
  payload: Record<string, unknown>,
) => {
  const { data, error } = await supabase.rpc(rpcName, payload).single();
  if (error) throw error;
  return data as PlanRecord;
};

const applyPlan = async (supabase: ReturnType<typeof createClient>, plan: PlanRecord) => {
  const validation = validatePlan(plan);
  if (!validation.ok) {
    return { applied: false, validation, results: null };
  }

  const organization = plan.organization as PlanRecord;
  const existingOrganizationId = asString(organization.id);
  const createdOrganization = existingOrganizationId
    ? null
    : await rpcSingle(supabase, "create_organization_command", {
      p_name: asString(organization.name),
      p_logo_url: asString(organization.logo_url),
    });
  const organizationId = existingOrganizationId ?? (createdOrganization?.id as string);

  const results = {
    organizationId,
    projects: [] as PlanRecord[],
  };

  for (const project of asArray(plan.projects)) {
    const createdProject = asString(project.id)
      ? { id: asString(project.id), title: asString(project.title) ?? asString(project.name) }
      : await rpcSingle(supabase, "create_project_command", {
        p_title: asString(project.title) ?? asString(project.name),
        p_description: asString(project.description),
        p_project_key: getProjectKey(project),
        p_organization_id: organizationId,
        p_tags: Array.isArray(project.tags) ? project.tags.filter((tag) => typeof tag === "string") : [],
        p_visibility: asString(project.visibility) ?? "organization",
      });
    const projectId = createdProject.id as string;
    const epicRefs = new Map<string, string>();
    const sprintRefs = new Map<string, string>();
    const projectResult = {
      id: projectId,
      ref: getRef(project, projectId),
      epics: [] as PlanRecord[],
      sprints: [] as PlanRecord[],
      tasks: [] as PlanRecord[],
    };

    for (const sprint of asArray(project.sprints)) {
      const sprintRef = getRef(sprint, asString(sprint.name) ?? `sprint-${projectResult.sprints.length + 1}`);
      const sprintId = asString(sprint.id);
      const sprintResult = sprintId
        ? { id: sprintId, ref: sprintRef }
        : await rpcSingle(supabase, "create_sprint_command", {
          p_project_id: projectId,
          p_name: asString(sprint.name),
          p_goal: asString(sprint.goal),
          p_start_date: asString(sprint.start_date) ?? asString(sprint.start) ?? new Date().toISOString(),
          p_duration: asString(sprint.duration) ?? "7d",
          p_status: asString(sprint.status) ?? "future",
        });
      sprintRefs.set(sprintRef, sprintResult.id as string);
      projectResult.sprints.push({ ...sprintResult, ref: sprintRef });
    }

    for (const epic of asArray(project.epics)) {
      const epicRef = getRef(epic, asString(epic.name) ?? asString(epic.title) ?? `epic-${projectResult.epics.length + 1}`);
      const epicId = asString(epic.id);
      const epicResult = epicId
        ? { id: epicId, ref: epicRef }
        : await rpcSingle(supabase, "create_epic_command", {
          p_project_id: projectId,
          p_name: asString(epic.name) ?? asString(epic.title),
          p_color: asString(epic.color),
          p_owner_id: asString(epic.owner_id),
          p_phase_id: asString(epic.phase_id),
          p_estimated_effort: asString(epic.estimated_effort) ?? asString(epic.effort),
          p_start_date: asString(epic.start_date) ?? asString(epic.start),
          p_end_date: asString(epic.end_date) ?? asString(epic.end),
        });
      epicRefs.set(epicRef, epicResult.id as string);
      projectResult.epics.push({ ...epicResult, ref: epicRef });
    }

    for (const task of asArray(project.tasks)) {
      const taskRef = getRef(task, asString(task.title) ?? asString(task.name) ?? `task-${projectResult.tasks.length + 1}`);
      const epicId = asString(task.epic_id) ?? epicRefs.get(asString(task.epic_ref) ?? "");
      const sprintId = asString(task.sprint_id) ?? sprintRefs.get(asString(task.sprint_ref) ?? "");
      const taskId = asString(task.id);
      const taskResult = taskId
        ? { id: taskId, ref: taskRef }
        : await rpcSingle(supabase, "create_task_command", {
          p_project_id: projectId,
          p_title: asString(task.title) ?? asString(task.name),
          p_subtitle: asString(task.subtitle),
          p_description: asString(task.description),
          p_destination: asString(task.destination) ?? (sprintId ? "scrum" : "backlog"),
          p_column_id: asString(task.column_id) ?? null,
          p_sprint_id: sprintId ?? null,
          p_position: Number(task.position ?? projectResult.tasks.length),
          p_issue_type_id: asString(task.issue_type_id),
          p_priority_id: asString(task.priority_id),
          p_story_points: asString(task.story_points) ?? asString(task.points),
          p_assignee_id: asString(task.assignee_id),
          p_epic_id: epicId ?? null,
          p_github_link: asString(task.github_link),
        });
      const resolvedTaskId = taskResult.id as string;
      const plannedStartDate = getTaskStartDate(task);

      if (plannedStartDate) {
        await rpcSingle(supabase, "schedule_task_command", {
          p_project_id: projectId,
          p_task_id: resolvedTaskId,
          p_planned_start_date: plannedStartDate,
          p_planned_end_date: getTaskEndDate(task, plannedStartDate),
        });
      }

      projectResult.tasks.push({ ...taskResult, ref: taskRef });
    }

    results.projects.push(projectResult);
  }

  return { applied: true, validation, results };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json()) as AgentCommandRequest;
    const plan = body.payload?.plan;

    if (body.action === "validate_plan") {
      return jsonResponse({ data: validatePlan(plan) });
    }

    if (body.action === "apply_plan") {
      const supabaseUrl = Deno.env.get("SUPABASE_URL");
      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
      const authorization = req.headers.get("Authorization");

      if (!supabaseUrl || !supabaseAnonKey || !authorization) {
        return jsonResponse({ error: "Missing Supabase configuration or Authorization header" }, 401);
      }

      const supabase = createClient(supabaseUrl, supabaseAnonKey, {
        global: {
          headers: { Authorization: authorization },
        },
      });

      if (body.payload?.dry_run) {
        return jsonResponse({ data: validatePlan(plan) });
      }

      if (!isRecord(plan)) {
        return jsonResponse({ error: "El plan debe ser un objeto JSON." }, 400);
      }

      const result = await applyPlan(supabase, plan);
      const status = result.validation.ok ? 200 : 400;
      return jsonResponse({ data: result }, status);
    }

    return jsonResponse({ error: "Unsupported agent command" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Agent command failed";
    return jsonResponse({ error: message }, 400);
  }
});
