// src/js/admin.js
// Admin CRUD operations for weapon codes, submission moderation & Owner role management

import { assertSupabaseConfigured } from './supabase-client.js';
import { getAdminRole, ADMIN_ROLES } from './auth.js';

const VALID_MODES = ['WARFARE', 'OPERATION'];
const VALID_PLATFORMS = ['PC', 'MOBILE'];

/**
 * Validate weapon data before sending to DB
 */
function validateWeapon(weaponName, weaponCode, gameMode = null, platform = null) {
  const errors = [];
  const name = (weaponName || '').trim();
  const code = (weaponCode || '').trim();
  const normalizedMode = gameMode ? String(gameMode).trim().toUpperCase() : null;
  const normalizedPlatform = platform ? String(platform).trim().toUpperCase() : null;

  if (!name) errors.push('Tên súng không được để trống.');
  if (name.length > 200) errors.push('Tên súng không được vượt quá 200 ký tự.');
  if (!code) errors.push('Code súng không được để trống.');
  if (code.length > 5000) errors.push('Code súng không được vượt quá 5000 ký tự.');
  if (normalizedMode && !VALID_MODES.includes(normalizedMode)) {
    errors.push('Chế độ chơi không hợp lệ.');
  }
  if (normalizedPlatform && !VALID_PLATFORMS.includes(normalizedPlatform)) {
    errors.push('Nền tảng không hợp lệ.');
  }

  return {
    errors,
    name,
    code,
    gameMode: normalizedMode,
    platform: normalizedPlatform,
  };
}

/**
 * Fetch all weapon codes for admin panel (OWNER & MODERATOR)
 */
export async function adminFetchWeapons() {
  const sb = assertSupabaseConfigured();
  const { data, error } = await sb
    .from('weapon_codes')
    .select('id, weapon_name, weapon_code, game_mode, platform, created_at, updated_at')
    .order('weapon_name', { ascending: true });

  if (error) throw error;
  return data || [];
}

/**
 * Insert a new weapon code (OWNER & MODERATOR)
 */
export async function adminInsertWeapon(weaponName, weaponCode, gameMode = null, platform = null) {
  const { errors, name, code, gameMode: mode, platform: plat } = validateWeapon(
    weaponName,
    weaponCode,
    gameMode,
    platform
  );
  if (errors.length > 0) throw new Error(errors.join(' '));

  const sb = assertSupabaseConfigured();
  const payload = { weapon_name: name, weapon_code: code };
  if (mode) payload.game_mode = mode;
  if (plat) payload.platform = plat;

  const { data, error } = await sb
    .from('weapon_codes')
    .insert([payload])
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new Error(`Tên súng "${name}" đã tồn tại. Vui lòng dùng tên khác.`);
    }
    throw new Error('Thêm súng thất bại: ' + error.message);
  }
  return data;
}

/**
 * Update an existing weapon code (OWNER & MODERATOR)
 */
export async function adminUpdateWeapon(id, weaponName, weaponCode, gameMode = null, platform = null) {
  if (!id) throw new Error('ID không hợp lệ.');
  const { errors, name, code, gameMode: mode, platform: plat } = validateWeapon(
    weaponName,
    weaponCode,
    gameMode,
    platform
  );
  if (errors.length > 0) throw new Error(errors.join(' '));

  const sb = assertSupabaseConfigured();
  const { data, error } = await sb
    .from('weapon_codes')
    .update({
      weapon_name: name,
      weapon_code: code,
      game_mode: mode,
      platform: plat,
    })
    .eq('id', id)
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new Error(`Tên súng "${name}" đã tồn tại. Vui lòng dùng tên khác.`);
    }
    throw new Error('Cập nhật thất bại: ' + error.message);
  }
  return data;
}

/**
 * Delete a weapon code by ID — STRICTLY OWNER ONLY (enforced by both client check & DB RLS)
 */
export async function adminDeleteWeapon(id) {
  if (!id) throw new Error('ID không hợp lệ.');
  const role = await getAdminRole();
  if (role !== ADMIN_ROLES.OWNER) {
    throw new Error('Chỉ tài khoản OWNER mới có quyền xóa code súng.');
  }

  const sb = assertSupabaseConfigured();
  const { data, error } = await sb
    .from('weapon_codes')
    .delete()
    .eq('id', id)
    .select('id');

  if (error) throw new Error('Xóa thất bại: ' + error.message);
  if (!data || data.length === 0) {
    throw new Error('Không thể xóa code súng. Thao tác bị chặn bởi phân quyền RLS hoặc bản ghi không tồn tại.');
  }
  return true;
}

/**
 * Fetch community submissions (OWNER & MODERATOR via RLS)
 * @param {'PENDING'|'APPROVED'|'REJECTED'|'ALL'} statusFilter
 */
export async function adminFetchSubmissions(statusFilter = 'PENDING') {
  const sb = assertSupabaseConfigured();
  let query = sb
    .from('weapon_submissions')
    .select('id, weapon_name, weapon_code, game_mode, platform, status, created_at, reviewed_at')
    .order('created_at', { ascending: false });

  if (statusFilter && statusFilter !== 'ALL') {
    query = query.eq('status', statusFilter);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

/**
 * Fetch pending submission count for badge indicator
 */
export async function adminGetPendingSubmissionCount() {
  const sb = assertSupabaseConfigured();
  const { count, error } = await sb
    .from('weapon_submissions')
    .select('*', { count: 'exact', head: true })
    .eq('status', 'PENDING');

  if (error) throw error;
  return count || 0;
}

/**
 * Atomically approve or reject a community submission via server-side SECURITY DEFINER RPC
 * (Allowed for both OWNER and MODERATOR)
 */
export async function adminReviewSubmission(id, decision) {
  if (!id || !['APPROVED', 'REJECTED'].includes(decision)) {
    throw new Error('Yêu cầu kiểm duyệt không hợp lệ.');
  }
  const sb = assertSupabaseConfigured();
  const { data, error } = await sb.rpc('review_weapon_submission', {
    p_submission_id: id,
    p_decision: decision,
  });
  if (error) throw new Error('Kiểm duyệt thất bại: ' + error.message);
  return data;
}

/**
 * OWNER ONLY: List all OWNER and MODERATOR accounts
 */
export async function adminFetchRoles() {
  const sb = assertSupabaseConfigured();
  const { data, error } = await sb.rpc('admin_list_roles');
  if (error) throw new Error('Không tải được danh sách phân quyền: ' + error.message);
  return data || [];
}

/**
 * OWNER ONLY: Assign or update a user's role ('OWNER' | 'MODERATOR') by Email or User UID
 */
export async function adminSetUserRole(identifier, role) {
  const cleanId = String(identifier || '').trim();
  const cleanRole = String(role || '').trim().toUpperCase();
  if (!cleanId) throw new Error('Vui lòng nhập Email hoặc User UID.');
  if (!['OWNER', 'MODERATOR'].includes(cleanRole)) {
    throw new Error('Vai trò không hợp lệ.');
  }

  const sb = assertSupabaseConfigured();
  const { data, error } = await sb.rpc('admin_set_user_role', {
    p_identifier: cleanId,
    p_role: cleanRole,
  });
  if (error) throw new Error(error.message);
  return data;
}

/**
 * OWNER ONLY: Revoke admin/moderator privileges from a user
 */
export async function adminRemoveUserRole(targetUserId) {
  if (!targetUserId) throw new Error('User ID không hợp lệ.');
  const sb = assertSupabaseConfigured();
  const { data, error } = await sb.rpc('admin_remove_user_role', {
    p_target_user_id: targetUserId,
  });
  if (error) throw new Error(error.message);
  return data;
}
