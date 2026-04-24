-- ============================================================
-- Run this in Supabase SQL Editor
-- Creates the withdrawals table for MoMo payout requests
-- ============================================================

CREATE TABLE IF NOT EXISTS public.withdrawals (
  id           UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID          NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role         TEXT          NOT NULL CHECK (role IN ('agent','promoter')),
  full_name    TEXT          NOT NULL,
  email        TEXT          NOT NULL,
  network      TEXT          NOT NULL CHECK (network IN ('MTN','Telecel','AirtelTigo')),
  momo_number  TEXT          NOT NULL DEFAULT '',
  amount       NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  status       TEXT          NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  note         TEXT          NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS withdrawals_updated_at ON public.withdrawals;
CREATE TRIGGER withdrawals_updated_at
  BEFORE UPDATE ON public.withdrawals
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "withdrawals_own_read"   ON public.withdrawals;
DROP POLICY IF EXISTS "withdrawals_own_insert" ON public.withdrawals;

CREATE POLICY "withdrawals_own_read"
  ON public.withdrawals FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "withdrawals_own_insert"
  ON public.withdrawals FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- If table already exists, just add the column:
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS momo_number TEXT NOT NULL DEFAULT '';