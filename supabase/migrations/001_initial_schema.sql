-- ============================================================
-- BIGSHARK WEAPON CODES - Initial Schema
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- pgcrypto extension
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- TABLE: weapon_codes
-- ============================================================
CREATE TABLE IF NOT EXISTS public.weapon_codes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  weapon_name TEXT NOT NULL,
  weapon_code TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT weapon_name_not_empty CHECK (trim(weapon_name) <> ''),
  CONSTRAINT weapon_code_not_empty CHECK (trim(weapon_code) <> ''),
  CONSTRAINT weapon_name_max_length CHECK (char_length(weapon_name) <= 200),
  CONSTRAINT weapon_code_max_length CHECK (char_length(weapon_code) <= 5000)
);

-- Unique constraint (case-insensitive) on weapon_name
CREATE UNIQUE INDEX IF NOT EXISTS idx_weapon_codes_name_unique
  ON public.weapon_codes (lower(trim(weapon_name)));

-- Index for search
CREATE INDEX IF NOT EXISTS idx_weapon_codes_name_search
  ON public.weapon_codes USING gin (lower(weapon_name) gin_trgm_ops);

-- Fallback index nếu pg_trgm chưa sẵn sàng
CREATE INDEX IF NOT EXISTS idx_weapon_codes_created_at
  ON public.weapon_codes (created_at DESC);

-- Trigger: auto-update updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS weapon_codes_updated_at ON public.weapon_codes;
CREATE TRIGGER weapon_codes_updated_at
  BEFORE UPDATE ON public.weapon_codes
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================
-- TABLE: admin_roles
-- Dùng để xác định ai có quyền admin - server-side check
-- ============================================================
CREATE TABLE IF NOT EXISTS public.admin_roles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  granted_by TEXT NOT NULL DEFAULT 'system'
);

-- ============================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE public.weapon_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_roles ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- RLS POLICIES: weapon_codes
-- ============================================================

-- PUBLIC: Anyone can SELECT (read)
DROP POLICY IF EXISTS "weapon_codes_public_select" ON public.weapon_codes;
CREATE POLICY "weapon_codes_public_select"
  ON public.weapon_codes
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- ADMIN ONLY: INSERT
DROP POLICY IF EXISTS "weapon_codes_admin_insert" ON public.weapon_codes;
CREATE POLICY "weapon_codes_admin_insert"
  ON public.weapon_codes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_roles
      WHERE user_id = auth.uid()
    )
  );

-- ADMIN ONLY: UPDATE
DROP POLICY IF EXISTS "weapon_codes_admin_update" ON public.weapon_codes;
CREATE POLICY "weapon_codes_admin_update"
  ON public.weapon_codes
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_roles
      WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_roles
      WHERE user_id = auth.uid()
    )
  );

-- ADMIN ONLY: DELETE
DROP POLICY IF EXISTS "weapon_codes_admin_delete" ON public.weapon_codes;
CREATE POLICY "weapon_codes_admin_delete"
  ON public.weapon_codes
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_roles
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- RLS POLICIES: admin_roles
-- ============================================================

-- Chỉ admin hiện tại có thể đọc bảng admin_roles
DROP POLICY IF EXISTS "admin_roles_select" ON public.admin_roles;
CREATE POLICY "admin_roles_select"
  ON public.admin_roles
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
  );

-- Không ai được INSERT/UPDATE/DELETE admin_roles từ client
-- (chỉ dùng service_role hoặc Supabase Dashboard)

-- ============================================================
-- HELPER FUNCTION: Check if current user is admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_roles
    WHERE user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- ============================================================
-- GRANT permissions
-- ============================================================
GRANT SELECT ON public.weapon_codes TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.weapon_codes TO authenticated;
GRANT SELECT ON public.admin_roles TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
