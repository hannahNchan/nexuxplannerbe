#!/usr/bin/env bash
set -euo pipefail

npm install
npx supabase start
npx supabase db reset
npx supabase status

