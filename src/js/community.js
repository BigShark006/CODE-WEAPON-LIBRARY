// src/js/community.js
// Public community weapon code submission (anonymous INSERT only via RLS)

import { assertSupabaseConfigured } from './supabase-client.js';

export const VALID_GAME_MODES = ['WARFARE', 'OPERATION'];
export const VALID_PLATFORMS = ['PC', 'MOBILE'];

export function validateContributionInput({ weaponName, weaponCode, gameMode, platform }) {
  const name = String(weaponName || '').trim();
  const code = String(weaponCode || '').trim();
  const mode = String(gameMode || '').trim().toUpperCase();
  const plat = String(platform || '').trim().toUpperCase();

  if (!name) {
    throw new Error('Vui lòng nhập tên súng.');
  }
  if (name.length > 200) {
    throw new Error('Tên súng không được vượt quá 200 ký tự.');
  }
  if (!code) {
    throw new Error('Vui lòng nhập code súng.');
  }
  if (code.length > 5000) {
    throw new Error('Code súng không được vượt quá 5000 ký tự.');
  }
  if (!VALID_GAME_MODES.includes(mode)) {
    throw new Error('Vui lòng chọn một chế độ chơi: Warfare (WF) hoặc Operation (OP).');
  }
  if (!VALID_PLATFORMS.includes(plat)) {
    throw new Error('Vui lòng chọn một nền tảng: PC hoặc Mobile.');
  }

  return { name, code, mode, plat };
}

export async function submitWeaponContribution(payload) {
  const { name, code, mode, plat } = validateContributionInput(payload);
  const sb = assertSupabaseConfigured();

  // Do NOT chain .select() because public (anon) users are intentionally blocked
  // from reading weapon_submissions by Row Level Security.
  const { error } = await sb.from('weapon_submissions').insert([
    {
      weapon_name: name,
      weapon_code: code,
      game_mode: mode,
      platform: plat,
    },
  ]);

  if (error) {
    if (error.code === '42P01' || error.code === 'PGRST205') {
      throw new Error('Hệ thống đóng góp chưa được kích hoạt. Admin cần chạy migration trên Supabase.');
    }
    if (error.code === '42501') {
      throw new Error('Không đủ quyền gửi đóng góp. Vui lòng kiểm tra cấu hình RLS trên Supabase.');
    }
    throw new Error('Không gửi được đóng góp: ' + error.message);
  }

  return { success: true };
}
