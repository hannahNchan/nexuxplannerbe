import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type BoardViewRequest = {
  projectId?: string;
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
    return jsonResponse({
      error: "Missing Supabase configuration or Authorization header",
    }, 401);
  }

  try {
    const body = (await req.json()) as BoardViewRequest;

    if (!body.projectId) {
      return jsonResponse({ error: "projectId is required" }, 400);
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authorization },
      },
    });

    const { data, error } = await supabase.rpc("get_project_board_view", {
      p_project_id: body.projectId,
    });

    if (error) throw error;
    return jsonResponse({ data });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Board view request failed";
    return jsonResponse({ error: message }, 400);
  }
});
