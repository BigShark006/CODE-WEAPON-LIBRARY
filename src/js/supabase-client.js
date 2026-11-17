// src/js/supabase-client.js
// Supabase client initialization
// Only uses publishable (anon) key - NEVER service_role key

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = (import.meta.env.VITE_SUPABASE_URL || '').trim();
const SUPABASE_ANON_KEY = (import.meta.env.VITE_SUPABASE_ANON_KEY || '').trim();

export const CONFIG_ERROR_MESSAGE =
  'Supabase chưa được cấu hình. Vui lòng kiểm tra file .env và đảm bảo đã đặt VITE_SUPABASE_URL và VITE_SUPABASE_ANON_KEY.';

export const isSupabaseConfigured = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

export const supabase = isSupabaseConfigured
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;

export function assertSupabaseConfigured() {
  if (!isSupabaseConfigured || !supabase) {
    throw new Error(CONFIG_ERROR_MESSAGE);
  }
  return supabase;
}
