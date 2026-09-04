#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const CONFIG_PATH = join(homedir(), ".nexusplanner", "config.json");

const commandMatrix = [
  ["auth", "status | token"],
  ["config", "get | set <url|anon-key|token|org|project> <value>"],
  ["org", "list | create <name> [--logo-url url] | delete <id> | switch <id>"],
  ["project", "list [--org id] | create <title> --key KEY [--org id] [--description text] | switch <id>"],
  ["epic", "list [--project id] | create <title>"],
  ["task", "list [--project id] | create <title> [flags] | assign <task-id> <user-id> | unassign <task-id> | move <task-id> --column <column-id> | schedule <task-id> --start date [--end date]"],
  ["sprint", "list [--project id] | create <name> | complete <sprint-id> --dispositions json"],
  ["board", "get [--project id] | move-task <task-id> --column <column-id>"],
  ["notifications", "list | read <id> | clear"],
  ["activity", "list [--project id] [--org id]"],
  ["agent", "validate-plan <file> | apply-plan <file> [--dry-run]"],
];

const aliases = {
  "anon-key": "anonKey",
  url: "apiUrl",
  token: "accessToken",
  org: "organizationId",
  project: "projectId",
};

const readConfig = () => {
  if (!existsSync(CONFIG_PATH)) return {};
  return JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
};

const readProjectEnv = () => {
  const values = {};

  for (const fileName of [".env.local", ".env"]) {
    if (!existsSync(fileName)) continue;

    const lines = readFileSync(fileName, "utf8").split(/\r?\n/);
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;

      const [key, ...valueParts] = trimmed.split("=");
      const rawValue = valueParts.join("=");
      values[key] = rawValue.replace(/^["']|["']$/g, "");
    }
  }

  return values;
};

const writeConfig = (config) => {
  mkdirSync(dirname(CONFIG_PATH), { recursive: true });
  writeFileSync(CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`);
};

const getRuntime = () => {
  const config = readConfig();
  const projectEnv = readProjectEnv();
  return {
    apiUrl:
      process.env.NEXUS_API_URL ??
      projectEnv.VITE_SUPABASE_URL ??
      projectEnv.NEXT_PUBLIC_SUPABASE_URL ??
      config.apiUrl,
    anonKey:
      process.env.NEXUS_PUBLISHABLE_KEY ??
      projectEnv.VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY ??
      projectEnv.VITE_SUPABASE_ANON_KEY ??
      projectEnv.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
      config.anonKey,
    accessToken: process.env.NEXUS_ACCESS_TOKEN ?? config.accessToken,
    organizationId: process.env.NEXUS_ORGANIZATION_ID ?? config.organizationId,
    projectId: process.env.NEXUS_PROJECT_ID ?? config.projectId,
  };
};

const parseArgs = (argv) => {
  const positionals = [];
  const flags = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }

    const key = arg.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      flags[key] = true;
    } else {
      flags[key] = next;
      index += 1;
    }
  }

  return { positionals, flags };
};

const print = (value) => {
  if (typeof value === "string") {
    console.log(value);
    return;
  }

  console.log(JSON.stringify(value, null, 2));
};

const fail = (message, code = 1) => {
  console.error(message);
  process.exit(code);
};

const redact = (value) => {
  if (!value) return null;
  if (value.length <= 14) return "***";
  return `${value.slice(0, 8)}...${value.slice(-6)}`;
};

const requireRuntime = () => {
  const runtime = getRuntime();
  const missing = [];

  if (!runtime.apiUrl) missing.push("NEXUS_API_URL or config url");
  if (!runtime.anonKey) missing.push("NEXUS_PUBLISHABLE_KEY or config anon-key");
  if (!runtime.accessToken) missing.push("NEXUS_ACCESS_TOKEN or config token");

  if (missing.length > 0) {
    fail(`Missing NexusPlanner CLI config: ${missing.join(", ")}`);
  }

  return runtime;
};

const requireConnection = () => {
  const runtime = getRuntime();
  const missing = [];

  if (!runtime.apiUrl) missing.push("NEXUS_API_URL or config url");
  if (!runtime.anonKey) missing.push("NEXUS_PUBLISHABLE_KEY or config anon-key");

  if (missing.length > 0) {
    fail(`Missing NexusPlanner CLI config: ${missing.join(", ")}`);
  }

  return runtime;
};

const requireProjectId = (flags, runtime) => {
  const projectId = flags.project ?? runtime.projectId;
  if (!projectId) fail("Missing project id. Pass --project <id> or run config set project <id>.");
  return projectId;
};

const requireOrganizationId = (flags, runtime) => {
  const organizationId = flags.org ?? runtime.organizationId;
  if (!organizationId) fail("Missing organization id. Pass --org <id> or run config set org <id>.");
  return organizationId;
};

const requestJson = async (url, options = {}) => {
  const response = await fetch(url, options);
  const text = await response.text();
  let body = null;

  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { error: text };
    }
  }

  if (!response.ok) {
    const message = body?.error ?? body?.message ?? response.statusText;
    fail(`${response.status} ${message}`);
  }

  return body;
};

const restGet = async (path) => {
  const runtime = requireRuntime();
  const url = new URL(`/rest/v1/${path}`, runtime.apiUrl);
  return requestJson(url, {
    headers: {
      apikey: runtime.anonKey,
      Authorization: `Bearer ${runtime.accessToken}`,
    },
  });
};

const restPatch = async (path, payload) => {
  const runtime = requireRuntime();
  const url = new URL(`/rest/v1/${path}`, runtime.apiUrl);
  return requestJson(url, {
    method: "PATCH",
    headers: {
      apikey: runtime.anonKey,
      Authorization: `Bearer ${runtime.accessToken}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify(payload),
  });
};

const callFunction = async (functionName, action, payload = {}, options = {}) => {
  const runtime = options.requireAuth === false ? requireConnection() : requireRuntime();
  const url = new URL(`/functions/v1/${functionName}`, runtime.apiUrl);
  const headers = {
    apikey: runtime.anonKey,
    "Content-Type": "application/json",
  };

  if (runtime.accessToken) {
    headers.Authorization = `Bearer ${runtime.accessToken}`;
  }

  return requestJson(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ action, payload }),
  });
};

const handleConfig = ([action, key, ...rest]) => {
  const config = readConfig();

  if (action === "get") {
    print({
      apiUrl: config.apiUrl ?? null,
      anonKey: redact(config.anonKey),
      accessToken: redact(config.accessToken),
      organizationId: config.organizationId ?? null,
      projectId: config.projectId ?? null,
      path: CONFIG_PATH,
    });
    return;
  }

  if (action === "set") {
    const target = aliases[key];
    if (!target) fail(`Unsupported config key: ${key}`);
    const value = rest.join(" ");
    if (!value) fail(`Missing value for config ${key}`);
    const nextConfig = { ...config, [target]: value };
    writeConfig(nextConfig);
    print({ ok: true, key, path: CONFIG_PATH });
    return;
  }

  fail("Usage: nexus config get | nexus config set <url|anon-key|token|org|project> <value>");
};

const handleAuth = async ([action]) => {
  const runtime = getRuntime();

  if (action === "status") {
    print({
      apiUrl: runtime.apiUrl ?? null,
      hasAnonKey: Boolean(runtime.anonKey),
      hasAccessToken: Boolean(runtime.accessToken),
      organizationId: runtime.organizationId ?? null,
      projectId: runtime.projectId ?? null,
    });
    return;
  }

  if (action === "token") {
    print(runtime.accessToken ?? "");
    return;
  }

  fail("Usage: nexus auth status | nexus auth token");
};

const handleOrg = async ([action, ...args], flags) => {
  if (action === "list") {
    print(await restGet("organizations?select=*&order=created_at.desc"));
    return;
  }

  if (action === "create") {
    const name = args.join(" ");
    if (!name) fail("Usage: nexus org create <name>");
    print(await callFunction("workspace-commands", "create_organization", {
      p_name: name,
      p_logo_url: flags["logo-url"] ?? null,
    }));
    return;
  }

  if (action === "delete") {
    const [organizationId] = args;
    if (!organizationId) fail("Usage: nexus org delete <id>");
    print(await callFunction("workspace-commands", "delete_organization", {
      p_organization_id: organizationId,
    }));
    return;
  }

  if (action === "switch") {
    const [organizationId] = args;
    if (!organizationId) fail("Usage: nexus org switch <id>");
    const config = readConfig();
    writeConfig({ ...config, organizationId });
    print({ ok: true, organizationId });
    return;
  }

  fail("Usage: nexus org list | create | delete | switch");
};

const handleProject = async ([action, ...args], flags) => {
  const runtime = getRuntime();

  if (action === "list") {
    const organizationId = flags.org ?? runtime.organizationId;
    const filter = organizationId ? `&organization_id=eq.${organizationId}` : "";
    print(await restGet(`projects?select=*&order=created_at.desc${filter}`));
    return;
  }

  if (action === "create") {
    const organizationId = requireOrganizationId(flags, runtime);
    const title = args.join(" ");
    if (!title || !flags.key) {
      fail("Usage: nexus project create <title> --key <KEY> [--org <id>] [--description <text>]");
    }
    print(await callFunction("workspace-commands", "create_project", {
      p_title: title,
      p_description: flags.description ?? null,
      p_project_key: flags.key,
      p_organization_id: organizationId,
      p_tags: [],
      p_visibility: flags.visibility ?? "organization",
    }));
    return;
  }

  if (action === "switch") {
    const [projectId] = args;
    if (!projectId) fail("Usage: nexus project switch <id>");
    const config = readConfig();
    writeConfig({ ...config, projectId });
    print({ ok: true, projectId });
    return;
  }

  fail("Usage: nexus project list | create | switch");
};

const handleEpic = async ([action, ...args], flags) => {
  const runtime = getRuntime();

  if (action === "list") {
    const projectId = requireProjectId(flags, runtime);
    print(await restGet(`epics?select=*&project_id=eq.${projectId}&order=created_at.asc`));
    return;
  }

  if (action === "create") {
    const projectId = requireProjectId(flags, runtime);
    const name = args.join(" ");
    if (!name) fail("Usage: nexus epic create <title>");
    print(await callFunction("epic-commands", "create_epic", {
      p_project_id: projectId,
      p_name: name,
      p_color: flags.color ?? null,
      p_owner_id: flags.owner ?? null,
      p_phase_id: flags.phase ?? null,
      p_estimated_effort: flags.effort ?? null,
      p_start_date: flags.start ?? null,
      p_end_date: flags.end ?? null,
    }));
    return;
  }

  fail("Usage: nexus epic list | create");
};

const handleTask = async ([action, ...args], flags) => {
  const runtime = getRuntime();

  if (action === "list") {
    const projectId = requireProjectId(flags, runtime);
    print(await restGet(`tasks?select=*&project_id=eq.${projectId}&order=created_at.desc`));
    return;
  }

  if (action === "create") {
    const projectId = requireProjectId(flags, runtime);
    const title = args.join(" ");
    if (!title) fail("Usage: nexus task create <title> [--destination backlog|scrum]");
    print(await callFunction("task-commands", "create_task", {
      p_project_id: projectId,
      p_title: title,
      p_subtitle: flags.subtitle ?? null,
      p_description: flags.description ?? null,
      p_destination: flags.destination ?? "backlog",
      p_column_id: flags.column ?? null,
      p_sprint_id: flags.sprint ?? null,
      p_position: Number(flags.position ?? 0),
      p_issue_type_id: flags.type ?? null,
      p_priority_id: flags.priority ?? null,
      p_story_points: flags.points ?? null,
      p_assignee_id: flags.assignee ?? null,
      p_epic_id: flags.epic ?? null,
      p_github_link: flags.github ?? null,
    }));
    return;
  }

  if (action === "assign" || action === "unassign") {
    const projectId = requireProjectId(flags, runtime);
    const [taskId, assigneeId] = args;
    if (!taskId || (action === "assign" && !assigneeId)) {
      fail("Usage: nexus task assign <task-id> <user-id> | nexus task unassign <task-id>");
    }
    print(await callFunction("task-commands", "assign_task", {
      p_project_id: projectId,
      p_task_id: taskId,
      p_assignee_id: action === "assign" ? assigneeId : null,
    }));
    return;
  }

  if (action === "move") {
    const projectId = requireProjectId(flags, runtime);
    const [taskId] = args;
    if (!taskId || !flags.column) {
      fail("Usage: nexus task move <task-id> --column <column-id> [--position <number>]");
    }
    print(await callFunction("task-commands", "move_task_column", {
      p_project_id: projectId,
      p_task_id: taskId,
      p_column_id: flags.column,
      p_position: flags.position ? Number(flags.position) : null,
    }));
    return;
  }

  if (action === "schedule") {
    const projectId = requireProjectId(flags, runtime);
    const [taskId] = args;
    if (!taskId || !flags.start) {
      fail("Usage: nexus task schedule <task-id> --start <yyyy-mm-dd> [--end <yyyy-mm-dd>]");
    }
    print(await callFunction("task-commands", "schedule_task", {
      p_project_id: projectId,
      p_task_id: taskId,
      p_planned_start_date: flags.start,
      p_planned_end_date: flags.end ?? flags.start,
    }));
    return;
  }

  fail("Usage: nexus task list | create | assign | unassign | move | schedule");
};

const handleSprint = async ([action, ...args], flags) => {
  const runtime = getRuntime();

  if (action === "list") {
    const projectId = requireProjectId(flags, runtime);
    print(await restGet(`sprints?select=*&project_id=eq.${projectId}&order=start_date.desc`));
    return;
  }

  if (action === "create") {
    const projectId = requireProjectId(flags, runtime);
    const name = args.join(" ");
    if (!name) fail("Usage: nexus sprint create <name> --duration <7d|15d|1m>");
    print(await callFunction("sprint-commands", "create_sprint", {
      p_project_id: projectId,
      p_name: name,
      p_goal: flags.goal ?? null,
      p_start_date: flags.start ?? new Date().toISOString(),
      p_duration: flags.duration ?? "7d",
      p_status: flags.status ?? "future",
    }));
    return;
  }

  if (action === "complete") {
    const projectId = requireProjectId(flags, runtime);
    const [sprintId] = args;
    if (!sprintId || !flags.dispositions) {
      fail("Usage: nexus sprint complete <sprint-id> --dispositions '<json-array>'");
    }
    print(await callFunction("sprint-commands", "complete_sprint", {
      p_project_id: projectId,
      p_sprint_id: sprintId,
      p_dispositions: JSON.parse(flags.dispositions),
    }));
    return;
  }

  fail("Usage: nexus sprint list | create | complete");
};

const handleBoard = async ([action, ...args], flags) => {
  const runtime = getRuntime();

  if (action === "get") {
    const projectId = requireProjectId(flags, runtime);
    const [columns, tasks] = await Promise.all([
      restGet(`columns?select=*&project_id=eq.${projectId}&order=position.asc`),
      restGet(`tasks?select=*&project_id=eq.${projectId}&order=position.asc`),
    ]);
    print({ columns, tasks });
    return;
  }

  if (action === "move-task") {
    await handleTask(["move", ...args], flags);
    return;
  }

  fail("Usage: nexus board get | move-task");
};

const handleNotifications = async ([action, ...args]) => {
  if (action === "list") {
    print(await restGet("user_notifications?select=*&read_at=is.null&order=created_at.desc&limit=50"));
    return;
  }

  if (action === "read") {
    const [notificationId] = args;
    if (!notificationId) fail("Usage: nexus notifications read <id>");
    print(await restPatch(`user_notifications?id=eq.${notificationId}`, {
      read_at: new Date().toISOString(),
    }));
    return;
  }

  if (action === "clear") {
    print(await callFunction("notification-commands", "mark_all_read"));
    return;
  }

  fail("Usage: nexus notifications list | read | clear");
};

const handleActivity = async ([action], flags) => {
  const runtime = getRuntime();

  if (action === "list") {
    const projectId = flags.project ?? runtime.projectId;
    const organizationId = flags.org ?? runtime.organizationId;
    const filters = [];
    if (projectId) filters.push(`project_id=eq.${projectId}`);
    if (organizationId) filters.push(`organization_id=eq.${organizationId}`);
    const query = ["activity_events?select=*", ...filters].join("&");
    print(await restGet(`${query}&order=created_at.desc&limit=50`));
    return;
  }

  fail("Usage: nexus activity list [--project <id>] [--org <id>]");
};

const handleAgent = async ([action, filePath], flags) => {
  if (!["validate-plan", "apply-plan"].includes(action) || !filePath) {
    fail("Usage: nexus agent validate-plan <file> | nexus agent apply-plan <file> [--dry-run]");
  }

  const plan = JSON.parse(readFileSync(filePath, "utf8"));
  const commandAction = action === "validate-plan" ? "validate_plan" : "apply_plan";
  print(await callFunction("agent-commands", commandAction, {
    plan,
    dry_run: Boolean(flags["dry-run"]),
  }, { requireAuth: action !== "validate-plan" }));
};

const help = () => {
  print(`NexusPlanner CLI

Usage:
  npm run cli -- <domain> <action> [args] [--flags]

Commands:
${commandMatrix.map(([domain, actions]) => `  ${domain.padEnd(15)} ${actions}`).join("\n")}
`);
};

const main = async () => {
  const { positionals, flags } = parseArgs(process.argv.slice(2));
  const [domain, ...args] = positionals;

  if (!domain || domain === "help" || domain === "--help") {
    help();
    return;
  }

  if (domain === "config") return handleConfig(args);
  if (domain === "auth") return handleAuth(args);
  if (domain === "org") return handleOrg(args, flags);
  if (domain === "project") return handleProject(args, flags);
  if (domain === "epic") return handleEpic(args, flags);
  if (domain === "task") return handleTask(args, flags);
  if (domain === "sprint") return handleSprint(args, flags);
  if (domain === "board") return handleBoard(args, flags);
  if (domain === "notifications") return handleNotifications(args, flags);
  if (domain === "activity") return handleActivity(args, flags);
  if (domain === "agent") return handleAgent(args, flags);

  fail(`Unknown domain: ${domain}`);
};

main().catch((error) => {
  fail(error instanceof Error ? error.message : String(error));
});
