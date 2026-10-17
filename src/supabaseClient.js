import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Copy .env.example to .env and fill them in."
  );
}

// The anon key is safe to ship to browsers because Row Level Security
// decides what each signed-in user can read and write.
export const supabase = createClient(url, anonKey);

// Dev-only: exposes the client so the two-user manual test in the README can
// be run from the browser console. Not included in production builds.
if (import.meta.env.DEV) window.supabase = supabase;
