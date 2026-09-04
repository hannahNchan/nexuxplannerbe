import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type EpicCommandAction = "create_epic";

type EpicCommandRequest = {
  action: EpicCommandAction;
  payload: Record<string, unknown>;
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
    const body = (await req.json()) as EpicCommandRequest;

    if (body.action !== "create_epic") {
      return jsonResponse({ error: "Unsupported epic command" }, 400);
    }

    const { data, error } = await supabase
      .rpc("create_epic_command", body.payload)
      .single();

    if (error) throw error;
    return jsonResponse({ data });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Epic command failed";
    return jsonResponse({ error: message }, 400);
  }
});
