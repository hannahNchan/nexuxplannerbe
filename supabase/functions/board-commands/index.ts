import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type BoardCommandRequest = {
  action?:
    | "set_scope"
    | "move_task_to_backlog"
    | "move_task_to_kanban"
    | "move_task_to_sprint";
  payload?: Record<string, unknown>;
};

const rpcByAction = {
  set_scope: "set_project_board_scope_command",
  move_task_to_backlog: "move_task_to_backlog_command",
  move_task_to_kanban: "move_task_to_kanban_command",
  move_task_to_sprint: "move_task_to_sprint_command",
} as const;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !supabaseAnonKey || !authorization) {
    return jsonResponse({
      error: "Missing Supabase configuration or Authorization header",
    }, 401);
  }

  try {
    const body = (await req.json()) as BoardCommandRequest;

    if (!body.action || !(body.action in rpcByAction)) {
      return jsonResponse({ error: "Unsupported board command" }, 400);
    }

    if (!body.payload || typeof body.payload !== "object") {
      return jsonResponse({ error: "Command payload is required" }, 400);
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authorization },
      },
    });

    const command = supabase.rpc(rpcByAction[body.action], body.payload);
    const { data, error } = body.action === "set_scope"
      ? await command
      : await command.single();

    if (error) throw error;
    return jsonResponse({ data });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Board command failed";
    return jsonResponse({ error: message }, 400);
  }
});
