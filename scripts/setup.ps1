$ErrorActionPreference = "Stop"

npm install
npx supabase start
npx supabase db reset
npx supabase status

