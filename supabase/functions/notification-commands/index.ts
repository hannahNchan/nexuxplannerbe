import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type NotificationCommandAction = "mark_all_read";

type NotificationCommandRequest = {
  action: NotificationCommandAction;
  payload?: Record<string, unknown>;
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

  if (!supabaseUrl || !supabaseAnonKey || !authorization) {
    return jsonResponse({ error: "Missing Supabase configuration or Authorization header" }, 401);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: { Authorization: authorization },
    },
  });

  try {
    const body = (await req.json()) as NotificationCommandRequest;

    if (body.action !== "mark_all_read") {
      return jsonResponse({ error: "Unsupported notification command" }, 400);
    }

    const { data, error } = await supabase
      .rpc("mark_all_notifications_read_command");

    if (error) throw error;
    return jsonResponse({ data });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Notification command failed";
    return jsonResponse({ error: message }, 400);
  }
});
