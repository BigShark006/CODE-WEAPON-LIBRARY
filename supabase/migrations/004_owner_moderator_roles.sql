-- ============================================================
-- BIGSHARK WEAPON CODES - Migration 004: Owner & Moderator Role-Based Access Control
-- Safe, idempotent migration. Preserves all existing data & Owner accounts.
-- ============================================================

-- 1. Add role column to admin_roles (existing admins default to OWNER)
ALTER TABLE public.admin_roles
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'OWNER';

ALTER TABLE public.admin_roles
  DROP CONSTRAINT IF EXISTS admin_roles_role_check,
  ADD CONSTRAINT admin_roles_role_check CHECK (role IN ('OWNER', 'MODERATOR'));

CREATE INDEX IF NOT EXISTS idx_admin_roles_role
  ON public.admin_roles (role);

-- 2. Server-side role lookup helpers (SECURITY DEFINER, locked search_path)
CREATE OR REPLACE FUNCTION public.get_my_admin_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM public.admin_roles
  WHERE user_id = auth.uid()
    AND role IN ('OWNER', 'MODERATOR')
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_roles
    WHERE user_id = auth.uid()
      AND role IN ('OWNER', 'MODERATOR')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_roles
    WHERE user_id = auth.uid()
      AND role = 'OWNER'
  );
$$;

REVOKE ALL ON FUNCTION public.get_my_admin_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_owner() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_my_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_owner() TO authenticated;

-- 3. Enforce role-based RLS policies on weapon_codes
-- Public: SELECT
-- OWNER & MODERATOR: INSERT, UPDATE
-- OWNER ONLY: DELETE (MODERATOR is strictly blocked at DB level)

DROP POLICY IF EXISTS "weapon_codes_admin_insert" ON public.weapon_codes;
CREATE POLICY "weapon_codes_admin_insert"
  ON public.weapon_codes
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "weapon_codes_admin_update" ON public.weapon_codes;
CREATE POLICY "weapon_codes_admin_update"
  ON public.weapon_codes
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "weapon_codes_admin_delete" ON public.weapon_codes;
DROP POLICY IF EXISTS "weapon_codes_owner_delete" ON public.weapon_codes;
CREATE POLICY "weapon_codes_owner_delete"
  ON public.weapon_codes
  FOR DELETE
  TO authenticated
  USING (public.is_owner());

-- 4. Enforce role-based RLS on weapon_submissions
-- Both OWNER & MODERATOR can view submissions and call review_weapon_submission()
DROP POLICY IF EXISTS "weapon_submissions_admin_select" ON public.weapon_submissions;
CREATE POLICY "weapon_submissions_admin_select"
  ON public.weapon_submissions
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- 5. Lock down admin_roles table so Moderators CANNOT read other roles or escalate privileges
REVOKE ALL ON public.admin_roles FROM anon;
REVOKE ALL ON public.admin_roles FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_roles TO authenticated;

DROP POLICY IF EXISTS "admin_roles_select" ON public.admin_roles;
CREATE POLICY "admin_roles_select"
  ON public.admin_roles
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_owner()
  );

DROP POLICY IF EXISTS "admin_roles_owner_insert" ON public.admin_roles;
CREATE POLICY "admin_roles_owner_insert"
  ON public.admin_roles
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_owner()
    AND role IN ('OWNER', 'MODERATOR')
  );

DROP POLICY IF EXISTS "admin_roles_owner_update" ON public.admin_roles;
CREATE POLICY "admin_roles_owner_update"
  ON public.admin_roles
  FOR UPDATE
  TO authenticated
  USING (
    public.is_owner()
    AND user_id <> auth.uid()
  )
  WITH CHECK (
    public.is_owner()
    AND role IN ('OWNER', 'MODERATOR')
    AND user_id <> auth.uid()
  );

DROP POLICY IF EXISTS "admin_roles_owner_delete" ON public.admin_roles;
CREATE POLICY "admin_roles_owner_delete"
  ON public.admin_roles
  FOR DELETE
  TO authenticated
  USING (
    public.is_owner()
    AND user_id <> auth.uid()
  );

-- 6. Owner-only RPCs for managing Moderator / Owner accounts safely
CREATE OR REPLACE FUNCTION public.admin_list_roles()
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  role TEXT,
  granted_by TEXT,
  granted_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_owner() THEN
    RAISE EXCEPTION 'Not authorized: OWNER role required';
  END IF;

  RETURN QUERY
  SELECT
    ar.user_id,
    COALESCE(u.email::TEXT, '(unknown)'),
    ar.role,
    ar.granted_by,
    ar.granted_at
  FROM public.admin_roles ar
  LEFT JOIN auth.users u ON u.id = ar.user_id
  ORDER BY
    CASE WHEN ar.role = 'OWNER' THEN 0 ELSE 1 END,
    ar.granted_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_user_role(
  p_identifier TEXT,
  p_role TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  clean_id TEXT;
  clean_role TEXT;
  target_uid UUID;
  actor_email TEXT;
BEGIN
  IF NOT public.is_owner() THEN
    RAISE EXCEPTION 'Not authorized: OWNER role required';
  END IF;

  clean_id := trim(COALESCE(p_identifier, ''));
  clean_role := upper(trim(COALESCE(p_role, '')));

  IF clean_id = '' THEN
    RAISE EXCEPTION 'Vui lòng nhập Email hoặc User UID.';
  END IF;

  IF clean_role NOT IN ('OWNER', 'MODERATOR') THEN
    RAISE EXCEPTION 'Vai trò không hợp lệ. Chỉ chấp nhận OWNER hoặc MODERATOR.';
  END IF;

  IF position('@' IN clean_id) > 0 THEN
    SELECT id INTO target_uid
    FROM auth.users
    WHERE lower(email) = lower(clean_id)
    LIMIT 1;
  ELSE
    BEGIN
      SELECT id INTO target_uid
      FROM auth.users
      WHERE id = clean_id::UUID
      LIMIT 1;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Định dạng Email hoặc User UID không hợp lệ.';
    END;
  END IF;

  IF target_uid IS NULL THEN
    RAISE EXCEPTION 'Không tìm thấy tài khoản trong Supabase Authentication. Hãy tạo user trước.';
  END IF;

  IF target_uid = auth.uid() THEN
    RAISE EXCEPTION 'Không thể tự thay đổi quyền của chính tài khoản Owner đang đăng nhập.';
  END IF;

  SELECT COALESCE(email::TEXT, auth.uid()::TEXT) INTO actor_email
  FROM auth.users
  WHERE id = auth.uid();

  INSERT INTO public.admin_roles (user_id, role, granted_by, granted_at)
  VALUES (target_uid, clean_role, COALESCE(actor_email, 'owner'), NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET role = EXCLUDED.role,
        granted_by = EXCLUDED.granted_by,
        granted_at = NOW();

  RETURN target_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_user_role(
  p_target_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_owner() THEN
    RAISE EXCEPTION 'Not authorized: OWNER role required';
  END IF;

  IF p_target_user_id IS NULL OR p_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Không thể tự thu hồi quyền của chính tài khoản Owner đang đăng nhập.';
  END IF;

  DELETE FROM public.admin_roles
  WHERE user_id = p_target_user_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_roles() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_user_role(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_remove_user_role(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_roles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_user_role(UUID) TO authenticated;
