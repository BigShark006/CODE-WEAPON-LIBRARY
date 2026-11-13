// src/js/admin.js
// Admin CRUD operations for weapon codes

import { supabase } from './supabase-client.js';

/**
 * Validate weapon data before sending to DB
 */
function validateWeapon(weaponName, weaponCode) {
  const errors = [];
  const name = (weaponName || '').trim();
  const code = (weaponCode || '').trim();

  if (!name) errors.push('Tên súng không được để trống.');
  if (name.length > 200) errors.push('Tên súng không được vượt quá 200 ký tự.');
  if (!code) errors.push('Code súng không được để trống.');
  if (code.length > 5000) errors.push('Code súng không được vượt quá 5000 ký tự.');

  return { errors, name, code };
}

/**
 * Fetch all weapon codes for admin panel
 */
export async function adminFetchWeapons() {
  const { data, error } = await supabase
    .from('weapon_codes')
    .select('id, weapon_name, weapon_code, created_at, updated_at')
    .order('weapon_name', { ascending: true });

  if (error) throw error;
  return data || [];
}

/**
 * Insert a new weapon code
 */
export async function adminInsertWeapon(weaponName, weaponCode) {
  const { errors, name, code } = validateWeapon(weaponName, weaponCode);
  if (errors.length > 0) throw new Error(errors.join(' '));

  const { data, error } = await supabase
    .from('weapon_codes')
    .insert([{ weapon_name: name, weapon_code: code }])
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
 * Update an existing weapon code
 */
export async function adminUpdateWeapon(id, weaponName, weaponCode) {
  if (!id) throw new Error('ID không hợp lệ.');
  const { errors, name, code } = validateWeapon(weaponName, weaponCode);
  if (errors.length > 0) throw new Error(errors.join(' '));

  const { data, error } = await supabase
    .from('weapon_codes')
    .update({ weapon_name: name, weapon_code: code })
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
 * Delete a weapon code by ID
 */
export async function adminDeleteWeapon(id) {
  if (!id) throw new Error('ID không hợp lệ.');

  const { error } = await supabase
    .from('weapon_codes')
    .delete()
    .eq('id', id);

  if (error) throw new Error('Xóa thất bại: ' + error.message);
  return true;
}
