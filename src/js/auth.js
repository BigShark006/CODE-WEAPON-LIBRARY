// src/js/auth.js
// Authentication & role-based authorization helpers (OWNER & MODERATOR)

import { supabase, isSupabaseConfigured, assertSupabaseConfigured } from './supabase-client.js';

export const ADMIN_ROLES = {
  OWNER: 'OWNER',
  MODERATOR: 'MODERATOR',
};

/**
 * Get current session - null if not logged in
 */
export async function getSession() {
  if (!isSupabaseConfigured || !supabase) return null;
  const { data: { session }, error } = await supabase.auth.getSession();
  if (error) return null;
  return session;
}

/**
 * Get current user's admin role ('OWNER' | 'MODERATOR' | null)
 * Server-side verified via SECURITY DEFINER RPC
 */
export async function getAdminRole() {
  if (!isSupabaseConfigured || !supabase) return null;
  try {
    const { data, error } = await supabase.rpc('get_my_admin_role');
    if (!error) {
      if (data === ADMIN_ROLES.OWNER || data === ADMIN_ROLES.MODERATOR) {
        return data;
      }
      return null;
    }

    // Fallback compatibility if migration 004 has not been applied yet
    const { data: legacyAdmin, error: legacyErr } = await supabase.rpc('is_admin');
    if (!legacyErr && legacyAdmin === true) {
      return ADMIN_ROLES.OWNER;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Check if current user has any admin role (OWNER or MODERATOR)
 */
export async function isAdmin() {
  const role = await getAdminRole();
  return role === ADMIN_ROLES.OWNER || role === ADMIN_ROLES.MODERATOR;
}

/**
 * Check if current user is specifically OWNER
 */
export async function isOwner() {
  const role = await getAdminRole();
  return role === ADMIN_ROLES.OWNER;
}

/**
 * Sign in with email/password
 */
export async function signIn(email, password) {
  const sb = assertSupabaseConfigured();
  const { data, error } = await sb.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw error;
  return data;
}

/**
 * Sign out
 */
export async function signOut() {
  if (!isSupabaseConfigured || !supabase) return;
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

/**
 * Require admin access (OWNER or MODERATOR) - redirect if unauthorized.
 * Returns the resolved role ('OWNER' | 'MODERATOR') or null if redirected.
 */
export async function requireAdmin(redirectUrl = '/admin/login.html') {
  const session = await getSession();
  if (!session) {
    window.location.href = redirectUrl;
    return null;
  }
  const role = await getAdminRole();
  if (!role) {
    await signOut();
    window.location.href = redirectUrl + '?error=unauthorized';
    return null;
  }
  return role;
}

/**
 * Listen for auth state changes
 */
export function onAuthStateChange(callback) {
  if (!isSupabaseConfigured || !supabase) {
    return { data: { subscription: { unsubscribe() {} } } };
  }
  return supabase.auth.onAuthStateChange(callback);
}
