-- BIGSHARK community submissions + mode/platform metadata
-- Multiple community loadouts may share the same weapon name.
DROP INDEX IF EXISTS public.idx_weapon_codes_name_unique;
ALTER TABLE public.weapon_codes
  ADD COLUMN IF NOT EXISTS game_mode TEXT,
  ADD COLUMN IF NOT EXISTS platform TEXT;

ALTER TABLE public.weapon_codes
  DROP CONSTRAINT IF EXISTS weapon_codes_game_mode_check,
  ADD CONSTRAINT weapon_codes_game_mode_check
    CHECK (game_mode IS NULL OR game_mode IN ('WARFARE', 'OPERATION')),
  DROP CONSTRAINT IF EXISTS weapon_codes_platform_check,
  ADD CONSTRAINT weapon_codes_platform_check
    CHECK (platform IS NULL OR platform IN ('PC', 'MOBILE'));

CREATE TABLE IF NOT EXISTS public.weapon_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  weapon_name TEXT NOT NULL CHECK (char_length(trim(weapon_name)) BETWEEN 1 AND 200),
  weapon_code TEXT NOT NULL CHECK (char_length(trim(weapon_code)) BETWEEN 1 AND 5000),
  game_mode TEXT NOT NULL CHECK (game_mode IN ('WARFARE', 'OPERATION')),
  platform TEXT NOT NULL CHECK (platform IN ('PC', 'MOBILE')),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_weapon_submissions_pending
  ON public.weapon_submissions (created_at DESC) WHERE status = 'PENDING';

ALTER TABLE public.weapon_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "weapon_submissions_public_insert" ON public.weapon_submissions;
CREATE POLICY "weapon_submissions_public_insert"
  ON public.weapon_submissions FOR INSERT TO anon, authenticated
  WITH CHECK (
    status = 'PENDING'
    AND reviewed_at IS NULL
    AND reviewed_by IS NULL
    AND char_length(trim(weapon_name)) BETWEEN 1 AND 200
    AND char_length(trim(weapon_code)) BETWEEN 1 AND 5000
  );

DROP POLICY IF EXISTS "weapon_submissions_admin_select" ON public.weapon_submissions;
CREATE POLICY "weapon_submissions_admin_select"
  ON public.weapon_submissions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid()));

GRANT INSERT ON public.weapon_submissions TO anon, authenticated;
GRANT SELECT ON public.weapon_submissions TO authenticated;

-- Review actions are atomic and can only be performed by an authenticated admin.
CREATE OR REPLACE FUNCTION public.review_weapon_submission(p_submission_id UUID, p_decision TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  submission_row public.weapon_submissions%ROWTYPE;
  inserted_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_roles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
    RAISE EXCEPTION 'Invalid decision';
  END IF;

  SELECT * INTO submission_row
  FROM public.weapon_submissions
  WHERE id = p_submission_id AND status = 'PENDING'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Submission not found or already reviewed';
  END IF;

  IF p_decision = 'APPROVED' THEN
    INSERT INTO public.weapon_codes (weapon_name, weapon_code, game_mode, platform)
    VALUES (submission_row.weapon_name, submission_row.weapon_code,
            submission_row.game_mode, submission_row.platform)
    RETURNING id INTO inserted_id;
  END IF;

  UPDATE public.weapon_submissions
  SET status = p_decision, reviewed_at = NOW(), reviewed_by = auth.uid()
  WHERE id = p_submission_id;

  RETURN inserted_id;
END;
$$;

REVOKE ALL ON FUNCTION public.review_weapon_submission(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_weapon_submission(UUID, TEXT) TO authenticated;
