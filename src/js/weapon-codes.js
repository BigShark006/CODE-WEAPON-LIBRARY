// src/js/weapon-codes.js
// Public-facing weapon codes data operations

import { supabase } from './supabase-client.js';

/**
 * Fetch all weapon codes, ordered by weapon_name
 */
export async function fetchAllWeaponCodes() {
  const { data, error } = await supabase
    .from('weapon_codes')
    .select('id, weapon_name, weapon_code, created_at')
    .order('weapon_name', { ascending: true });

  if (error) throw error;
  return data || [];
}

/**
 * Search weapon codes by name (case-insensitive)
 * Uses ilike for compatibility without requiring pg_trgm
 */
export async function searchWeaponCodes(query) {
  if (!query || query.trim() === '') {
    return fetchAllWeaponCodes();
  }

  const sanitizedQuery = query.trim();

  const { data, error } = await supabase
    .from('weapon_codes')
    .select('id, weapon_name, weapon_code, created_at')
    .ilike('weapon_name', `%${sanitizedQuery}%`)
    .order('weapon_name', { ascending: true });

  if (error) throw error;
  return data || [];
}

/**
 * Get total count of weapon codes
 */
export async function getWeaponCount() {
  const { count, error } = await supabase
    .from('weapon_codes')
    .select('*', { count: 'exact', head: true });

  if (error) throw error;
  return count || 0;
}

/**
 * Copy weapon code to clipboard
 * Returns { success: boolean, message: string }
 */
export async function copyWeaponCode(code) {
  try {
    if (!navigator.clipboard) {
      throw new Error('Clipboard API không được hỗ trợ trên trình duyệt này.');
    }
    await navigator.clipboard.writeText(code);
    return { success: true, message: 'Đã sao chép code!' };
  } catch (err) {
    // Fallback for older browsers
    try {
      const textarea = document.createElement('textarea');
      textarea.value = code;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.focus();
      textarea.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(textarea);
      if (ok) return { success: true, message: 'Đã sao chép code!' };
      throw new Error('execCommand failed');
    } catch {
      return { success: false, message: 'Không thể sao chép. Vui lòng sao chép thủ công.' };
    }
  }
}
