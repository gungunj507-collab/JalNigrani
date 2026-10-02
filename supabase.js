import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
// An anon/publishable key is designed for browser use; RLS protects the data.
// VITE_SUPABASE_PUBLISHABLE_KEY is retained only as a migration fallback.
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);

// A publishable/anon key is safe for browser use when Row Level Security is enabled.
// Never place a secret or service-role key in any VITE_ variable.
export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    })
  : null;
