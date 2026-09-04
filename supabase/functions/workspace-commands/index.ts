import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type WorkspaceAction =
  | "create_organization"
  | "create_project"
  | "create_organization_invitation"
  | "create_organization_invitation_for_user"
  | "accept_organization_invitation"
  | "decline_organization_invitation"
  | "update_organization_member_role"
  | "remove_organization_member"
  | "delete_organization"
  | "add_project_member"
  | "remove_project_member"
  | "create_project_invitation"
  | "accept_project_invitation"
  | "decline_project_invitation";

type CommandBody = {
  action?: WorkspaceAction;
  payload?: Record<string, unknown>;
};

const rpcByAction: Record<WorkspaceAction, string> = {
  create_organization: "create_organization_command",
  create_project: "create_project_command",
  create_organization_invitation: "create_organization_invitation_command",
  create_organization_invitation_for_user: "create_organization_invitation_for_user_command",
  accept_organization_invitation: "accept_organization_invitation_command",
  decline_organization_invitation: "decline_organization_invitation_command",
  update_organization_member_role: "update_organization_member_role_command",
  remove_organization_member: "remove_organization_member_command",
  delete_organization: "delete_organization_command",
  add_project_member: "add_project_member_command",
  remove_project_member: "remove_project_member_command",
  create_project_invitation: "create_project_invitation_command",
  accept_project_invitation: "accept_project_invitation_command",
  decline_project_invitation: "decline_project_invitation_command",
};

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

  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: "Supabase environment is not configured" }, 500);
  }

  if (!authorization) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  const body = (await req.json()) as CommandBody;

  if (!body.action || !(body.action in rpcByAction)) {
    return jsonResponse({ error: "Unsupported workspace command" }, 400);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });

  const { data, error } = await supabase.rpc(
    rpcByAction[body.action],
    body.payload ?? {}
  );

  if (error) {
    return jsonResponse({ error: error.message, details: error }, 400);
  }

  return jsonResponse({ data });
});
