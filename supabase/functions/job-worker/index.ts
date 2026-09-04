import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.7";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type CommandJob = {
  id: string;
  queue_name: string;
  job_type: string;
  payload: Record<string, unknown>;
  attempts: number;
};

type WorkerRequest = {
  queueName?: string;
  limit?: number;
  workerId?: string;
};

const DEFAULT_QUEUE = "nexusplanner-events";
const KNOWN_JOB_TYPES = new Set([
  "activity.task_created",
  "activity.task_assigned",
  "activity.task_moved",
  "activity.sprint_completed",
  "metrics.sprint_completed",
  "notification.task_assigned",
  "notification.organization_invitation_created",
  "notification.project_invitation_created",
  "workspace.organization_created",
  "workspace.project_created",
  "workspace.organization_invitation_created",
  "workspace.organization_invitation_accepted",
  "workspace.organization_invitation_declined",
  "workspace.project_member_added",
  "workspace.project_invitation_created",
  "workspace.project_invitation_accepted",
  "workspace.project_invitation_declined",
  "report.sprint_completed",
  "automation.email",
  "automation.webhook",
  "email.organization_invitation",
  "email.project_invitation",
]);

const retryDelaySeconds = (attempts: number) =>
  Math.min(3600, Math.max(30, 2 ** Math.max(attempts - 1, 0) * 30));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const workerSecret = Deno.env.get("JOB_WORKER_SECRET");
  const providedSecret = req.headers.get("x-job-worker-secret");

  if (!workerSecret) {
    return jsonResponse({ error: "Worker secret is not configured" }, 500);
  }

  if (providedSecret !== workerSecret) {
    return jsonResponse({ error: "Unauthorized worker request" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Worker Supabase environment is not configured" }, 500);
  }

  const body = (await req.json().catch(() => ({}))) as WorkerRequest;
  const queueName = (body.queueName ?? DEFAULT_QUEUE).trim() || DEFAULT_QUEUE;
  const limit = Math.min(Math.max(body.limit ?? 10, 1), 50);
  const workerId = (body.workerId ?? crypto.randomUUID()).trim();

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { error: resetError } = await supabase.rpc("reset_stale_command_jobs", {
    p_timeout_seconds: 300,
  });

  if (resetError) {
    return jsonResponse({ error: resetError.message }, 500);
  }

  const { data: jobs, error: claimError } = await supabase.rpc("claim_command_jobs", {
    p_queue_name: queueName,
    p_limit: limit,
    p_worker_id: workerId,
  });

  if (claimError) {
    return jsonResponse({ error: claimError.message }, 500);
  }

  const results = [];

  for (const job of (jobs ?? []) as CommandJob[]) {
    try {
      await processJob(job);

      const { error: completeError } = await supabase.rpc("complete_command_job", {
        p_job_id: job.id,
        p_worker_id: workerId,
      });

      if (completeError) {
        throw completeError;
      }

      results.push({ id: job.id, jobType: job.job_type, status: "done" });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Command job failed";

      await supabase.rpc("fail_command_job", {
        p_job_id: job.id,
        p_error: message,
        p_retry_delay_seconds: retryDelaySeconds(job.attempts),
        p_worker_id: workerId,
      });

      results.push({ id: job.id, jobType: job.job_type, status: "failed", error: message });
    }
  }

  return jsonResponse({
    workerId,
    queueName,
    processed: results.length,
    results,
  });
});

const processJob = async (job: CommandJob) => {
  if (!KNOWN_JOB_TYPES.has(job.job_type)) {
    throw new Error(`Unsupported command job type: ${job.job_type}`);
  }

  if (job.job_type.startsWith("email.")) {
    if (Deno.env.get("EMAIL_PROVIDER_ENABLED") !== "true") {
      return;
    }

    throw new Error("Email provider worker is not configured.");
  }

  if (job.job_type.startsWith("report.")) {
    return;
  }

  if (job.job_type.startsWith("automation.")) {
    return;
  }
};
