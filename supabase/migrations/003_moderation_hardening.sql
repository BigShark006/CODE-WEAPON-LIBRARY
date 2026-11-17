-- ============================================================
-- BIGSHARK WEAPON CODES - Migration 003: Moderation Hardening & Status Filtering
-- Safe, idempotent migration. Does NOT modify or re-run 001/002.
-- ============================================================

-- 1. Index for filtering submissions by status and created_at in Admin panel
CREATE INDEX IF NOT EXISTS idx_weapon_submissions_status_created
  ON public.weapon_submissions (status, created_at DESC);

-- 2. Harden table-level privileges on weapon_submissions
-- Public (anon) can ONLY INSERT pending rows; cannot SELECT, UPDATE, or DELETE.
-- Authenticated users can only SELECT if in admin_roles (enforced by RLS);
-- direct UPDATE/DELETE is revoked so all moderation goes through review_weapon_submission().
REVOKE ALL ON public.weapon_submissions FROM anon;
REVOKE ALL ON public.weapon_submissions FROM authenticated;

GRANT INSERT ON public.weapon_submissions TO anon, authenticated;
GRANT SELECT ON public.weapon_submissions TO authenticated;

-- Re-verify insert policy strictly enforces PENDING state and clean review columns
DROP POLICY IF EXISTS "weapon_submissions_public_insert" ON public.weapon_submissions;
CREATE POLICY "weapon_submissions_public_insert"
  ON public.weapon_submissions
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    status = 'PENDING'
    AND reviewed_at IS NULL
    AND reviewed_by IS NULL
    AND game_mode IN ('WARFARE', 'OPERATION')
    AND platform IN ('PC', 'MOBILE')
    AND char_length(trim(weapon_name)) BETWEEN 1 AND 200
    AND char_length(trim(weapon_code)) BETWEEN 1 AND 5000
  );

-- Re-verify admin-only select policy
DROP POLICY IF EXISTS "weapon_submissions_admin_select" ON public.weapon_submissions;
CREATE POLICY "weapon_submissions_admin_select"
  ON public.weapon_submissions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_roles
      WHERE user_id = auth.uid()
    )
  );

-- 3. Upgrade review_weapon_submission RPC to prevent duplicate weapon_codes entries
-- and guarantee atomic, admin-only moderation.
CREATE OR REPLACE FUNCTION public.review_weapon_submission(
  p_submission_id UUID,
  p_decision TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  submission_row public.weapon_submissions%ROWTYPE;
  target_weapon_id UUID;
  clean_name TEXT;
  clean_code TEXT;
BEGIN
  -- Server-side Admin authorization check
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
    RAISE EXCEPTION 'Invalid decision';
  END IF;

  -- Lock the pending submission row to prevent concurrent double-approval
  SELECT * INTO submission_row
  FROM public.weapon_submissions
  WHERE id = p_submission_id
    AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Submission not found or already reviewed';
  END IF;

  IF p_decision = 'APPROVED' THEN
    clean_name := trim(submission_row.weapon_name);
    clean_code := trim(submission_row.weapon_code);

    IF clean_name = '' OR char_length(clean_name) > 200 THEN
      RAISE EXCEPTION 'Invalid weapon name in submission';
    END IF;

    IF clean_code = '' OR char_length(clean_code) > 5000 THEN
      RAISE EXCEPTION 'Invalid weapon code in submission';
    END IF;

    -- Prevent duplicate identical weapon code entry in public catalog
    SELECT id INTO target_weapon_id
    FROM public.weapon_codes
    WHERE lower(trim(weapon_name)) = lower(clean_name)
      AND trim(weapon_code) = clean_code
      AND COALESCE(game_mode, '') = COALESCE(submission_row.game_mode, '')
      AND COALESCE(platform, '') = COALESCE(submission_row.platform, '')
    LIMIT 1;

    IF target_weapon_id IS NULL THEN
      INSERT INTO public.weapon_codes (weapon_name, weapon_code, game_mode, platform)
      VALUES (
        clean_name,
        clean_code,
        submission_row.game_mode,
        submission_row.platform
      )
      RETURNING id INTO target_weapon_id;
    END IF;
  END IF;

  UPDATE public.weapon_submissions
  SET
    status = p_decision,
    reviewed_at = NOW(),
    reviewed_by = auth.uid()
  WHERE id = p_submission_id;

  RETURN target_weapon_id;
END;
$$;

REVOKE ALL ON FUNCTION public.review_weapon_submission(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_weapon_submission(UUID, TEXT) TO authenticated;
