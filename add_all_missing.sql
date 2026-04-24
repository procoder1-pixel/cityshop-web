-- ============================================================
-- CityShop — Master migration (safe to run multiple times)
-- Run this in Supabase SQL Editor
-- ============================================================

-- ── 1. stores: add is_verified + is_active ───────────────────
ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_active   BOOLEAN NOT NULL DEFAULT true;

-- ── 2. profiles: add is_suspended ────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT false;

-- ── 3. products: add wholesale_price ─────────────────────────
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS wholesale_price NUMERIC(10,2) DEFAULT NULL;

-- ── 4. link_clicks table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.link_clicks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promoter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.link_clicks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='link_clicks' AND policyname='anon insert clicks') THEN
    CREATE POLICY "anon insert clicks" ON public.link_clicks FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='link_clicks' AND policyname='promoters read own clicks') THEN
    CREATE POLICY "promoters read own clicks" ON public.link_clicks FOR SELECT USING (auth.uid() = promoter_id);
  END IF;
END $$;

-- ── 5. announcements table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.announcements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message     TEXT NOT NULL,
  type        TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info','warning','success','error')),
  target_role TEXT NOT NULL DEFAULT 'all' CHECK (target_role IN ('all','agents','promoters')),
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='announcements' AND policyname='public reads active announcements') THEN
    CREATE POLICY "public reads active announcements" ON public.announcements FOR SELECT USING (is_active = true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='announcements' AND policyname='admins manage announcements') THEN
    CREATE POLICY "admins manage announcements" ON public.announcements FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));
  END IF;
END $$;

-- ── 6. audit_logs table ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id       UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  action         TEXT NOT NULL,
  target_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  detail         TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='audit_logs' AND policyname='admins manage audit logs') THEN
    CREATE POLICY "admins manage audit logs" ON public.audit_logs FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true))
      WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));
  END IF;
END $$;

-- ── 7. Core RLS policies ──────────────────────────────────────

-- profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='users read own profile') THEN
    CREATE POLICY "users read own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='users update own profile') THEN
    CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='profiles' AND policyname='admins read all profiles') THEN
    CREATE POLICY "admins read all profiles" ON public.profiles FOR SELECT
      USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
  END IF;
END $$;

-- stores
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='stores' AND policyname='public reads stores') THEN
    CREATE POLICY "public reads stores" ON public.stores FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='stores' AND policyname='owners update stores') THEN
    CREATE POLICY "owners update stores" ON public.stores FOR UPDATE USING (auth.uid() = owner_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='stores' AND policyname='agents insert stores') THEN
    CREATE POLICY "agents insert stores" ON public.stores FOR INSERT WITH CHECK (auth.uid() = owner_id);
  END IF;
END $$;

-- products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='products' AND policyname='public reads products') THEN
    CREATE POLICY "public reads products" ON public.products FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='products' AND policyname='store owners manage products') THEN
    CREATE POLICY "store owners manage products" ON public.products FOR ALL
      USING (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()))
      WITH CHECK (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));
  END IF;
END $$;

-- orders
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='orders' AND policyname='anon places orders') THEN
    CREATE POLICY "anon places orders" ON public.orders FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='orders' AND policyname='store owners read orders') THEN
    CREATE POLICY "store owners read orders" ON public.orders FOR SELECT
      USING (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='orders' AND policyname='store owners update orders') THEN
    CREATE POLICY "store owners update orders" ON public.orders FOR UPDATE
      USING (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='orders' AND policyname='promoters read own orders') THEN
    CREATE POLICY "promoters read own orders" ON public.orders FOR SELECT
      USING (auth.uid() = promoter_id);
  END IF;
END $$;

-- reviews
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='reviews' AND policyname='public reads reviews') THEN
    CREATE POLICY "public reads reviews" ON public.reviews FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='reviews' AND policyname='anon inserts reviews') THEN
    CREATE POLICY "anon inserts reviews" ON public.reviews FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='reviews' AND policyname='store owners reply reviews') THEN
    CREATE POLICY "store owners reply reviews" ON public.reviews FOR UPDATE
      USING (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));
  END IF;
END $$;

-- withdrawals
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='withdrawals' AND policyname='users manage own withdrawals') THEN
    CREATE POLICY "users manage own withdrawals" ON public.withdrawals FOR ALL USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='withdrawals' AND policyname='admins manage withdrawals') THEN
    CREATE POLICY "admins manage withdrawals" ON public.withdrawals FOR ALL
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));
  END IF;
END $$;

SELECT 'Migration complete ✓' AS status;
