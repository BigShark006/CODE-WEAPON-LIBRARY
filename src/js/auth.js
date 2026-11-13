// src/js/auth.js
// Authentication & authorization helpers

import { supabase } from './supabase-client.js';

/**
 * Get current session - null if not logged in
 */
export async function getSession() {
  const { data: { session }, error } = await supabase.auth.getSession();
  if (error) return null;
  return session;
}

/**
 * Check if current user is admin by querying admin_roles table
 * Server-side check via RLS - cannot be spoofed by client
 */
export async function isAdmin() {
  try {
    const { data, error } = await supabase.rpc('is_admin');
    if (error) return false;
    return data === true;
  } catch {
    return false;
  }
}

/**
 * Sign in with email/password
 */
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
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
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

/**
 * Require admin access - redirect if not admin
 * Call this at the top of admin pages
 */
export async function requireAdmin(redirectUrl = '/admin/login.html') {
  const session = await getSession();
  if (!session) {
    window.location.href = redirectUrl;
    return false;
  }
  const admin = await isAdmin();
  if (!admin) {
    await signOut();
    window.location.href = redirectUrl + '?error=unauthorized';
    return false;
  }
  return true;
}

/**
 * Listen for auth state changes
 */
export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange(callback);
}
