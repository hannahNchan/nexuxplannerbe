import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type SprintCommandRequest = {
  action: "create_sprint" | "complete_sprint";
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
    const body = (await req.json()) as SprintCommandRequest;

    if (body.action === "create_sprint") {
      const { data, error } = await supabase
        .rpc("create_sprint_command", body.payload)
        .single();

      if (error) throw error;
      return jsonResponse({ data });
    }

    if (body.action === "complete_sprint") {
      const { data, error } = await supabase
        .rpc("complete_sprint_command", body.payload)
        .single();

      if (error) throw error;
      return jsonResponse({ data });
    }

    return jsonResponse({ error: "Unsupported sprint command" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Sprint command failed";
    return jsonResponse({ error: message }, 400);
  }
});
