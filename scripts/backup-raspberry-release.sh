#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="${BACKEND_DIR:-/home/hannah/nexusplannerbe}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/hannah/nexusplanner-supabase}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/hannah/nexusplanner-backups}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_nexusplanner-supabase}"
STORAGE_CONTAINER="${STORAGE_CONTAINER:-supabase_storage_nexusplanner-supabase}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$BACKUP_ROOT/$timestamp"
storage_tmp="/tmp/nexusplanner-storage-$timestamp.tar.gz"

umask 077
mkdir -p "$backup_dir"
chmod 700 "$BACKUP_ROOT" "$backup_dir"

cleanup() {
  docker exec "$STORAGE_CONTAINER" rm -f "$storage_tmp" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker exec "$DB_CONTAINER" pg_dump -U postgres -d postgres --format=custom \
  > "$backup_dir/database.dump"
docker exec -i "$DB_CONTAINER" pg_restore --list \
  < "$backup_dir/database.dump" > "$backup_dir/database.contents.txt"

docker exec "$STORAGE_CONTAINER" sh -c \
  "tar -czf '$storage_tmp' -C /mnt ."
docker cp "$STORAGE_CONTAINER:$storage_tmp" "$backup_dir/storage.tar.gz" >/dev/null

tar -czf "$backup_dir/runtime-functions.tar.gz" \
  -C "$RUNTIME_DIR" supabase/functions supabase/config.toml

{
  printf 'created_at=%s\n' "$(date -Is)"
  printf 'host=%s\n' "$(hostname)"
  printf 'backend_commit=%s\n' "$(git -C "$BACKEND_DIR" rev-parse HEAD)"
  printf 'database_container=%s\n' "$DB_CONTAINER"
  printf 'storage_container=%s\n' "$STORAGE_CONTAINER"
} > "$backup_dir/release-manifest.txt"

test -s "$backup_dir/database.dump"
test -s "$backup_dir/database.contents.txt"
test -s "$backup_dir/storage.tar.gz"
test -s "$backup_dir/runtime-functions.tar.gz"

(
  cd "$backup_dir"
  sha256sum database.dump storage.tar.gz runtime-functions.tar.gz \
    > SHA256SUMS
  sha256sum --check SHA256SUMS
)

chmod 600 "$backup_dir"/*
printf '%s\n' "$backup_dir"
