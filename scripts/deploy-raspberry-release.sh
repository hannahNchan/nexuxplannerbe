#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="${BACKEND_DIR:-/home/hannah/nexusplannerbe}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/hannah/nexusplanner-supabase}"
EDGE_CONTAINER="${EDGE_CONTAINER:-supabase_edge_runtime_nexusplanner-supabase}"
API_URL="${API_URL:-http://127.0.0.1:54321}"

if [[ -n "$(git -C "$BACKEND_DIR" status --short)" ]]; then
  echo "Backend checkout is not clean; refusing to deploy." >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR/supabase/migrations" "$RUNTIME_DIR/supabase/functions"
rsync -a "$BACKEND_DIR/supabase/migrations/" "$RUNTIME_DIR/supabase/migrations/"
rsync -a --delete "$BACKEND_DIR/supabase/functions/" "$RUNTIME_DIR/supabase/functions/"

(
  cd "$RUNTIME_DIR"
  npx supabase migration up --local
)

if ! docker inspect "$EDGE_CONTAINER" >/dev/null 2>&1; then
  echo "Edge Runtime container is missing; run Supabase start before deploying." >&2
  exit 1
fi

docker restart "$EDGE_CONTAINER" >/dev/null

for _ in $(seq 1 30); do
  status="$(curl -sS -o /dev/null -w '%{http_code}' \
    "$API_URL/functions/v1/board-view" || true)"
  if [[ "$status" != "000" && "$status" != "502" && "$status" != "503" ]]; then
    break
  fi
  sleep 1
done

if [[ "$status" == "000" || "$status" == "502" || "$status" == "503" ]]; then
  docker logs --tail 100 "$EDGE_CONTAINER" >&2
  echo "Edge Runtime did not become healthy." >&2
  exit 1
fi

docker exec supabase_db_nexusplanner-supabase psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -Atc \
  "select count(*) from public.audit_task_placement_consistency(null);"

printf 'backend_commit=%s\n' "$(git -C "$BACKEND_DIR" rev-parse HEAD)"
printf 'board_view_http_status=%s\n' "$status"
