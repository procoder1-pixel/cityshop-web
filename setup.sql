-- ============================================================
-- setup.sql — City Shop Full Database Schema
-- Run this entirely in Supabase SQL Editor (Dashboard → SQL Editor)
-- ============================================================

-- ── Extensions ────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. PROFILES — one row per authenticated user
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id                  UUID          PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name           TEXT          NOT NULL DEFAULT '',
  email               TEXT          NOT NULL DEFAULT '',
  role                TEXT          NOT NULL DEFAULT 'agent' CHECK (role IN ('agent','promoter')),
  subscription_active BOOLEAN       NOT NULL DEFAULT FALSE,
  subscription_end    TIMESTAMPTZ,
  paystack_ref        TEXT,
  avatar_url          TEXT,
  phone               TEXT,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 2. STORES — one store per agent, created on signup
-- ============================================================
CREATE TABLE IF NOT EXISTS public.stores (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id    UUID          NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name        TEXT          NOT NULL DEFAULT 'My Store',
  slug        TEXT          NOT NULL,
  description TEXT          NOT NULL DEFAULT '',
  logo_url    TEXT          NOT NULL DEFAULT '',
  phone       TEXT          NOT NULL DEFAULT '',
  whatsapp    TEXT          NOT NULL DEFAULT '',
  is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT stores_slug_unique UNIQUE (slug)
);

DROP TRIGGER IF EXISTS stores_updated_at ON public.stores;
CREATE TRIGGER stores_updated_at
  BEFORE UPDATE ON public.stores
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- 3. PRODUCTS — items listed by agents in their stores
-- ============================================================
CREATE TABLE IF NOT EXISTS public.products (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id    UUID          NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  name        TEXT          NOT NULL,
  description TEXT          NOT NULL DEFAULT '',
  price       NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  image_url   TEXT          NOT NULL DEFAULT '',
  category    TEXT          NOT NULL DEFAULT '',
  in_stock    BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS products_updated_at ON public.products;
CREATE TRIGGER products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE INDEX IF NOT EXISTS products_store_id_idx   ON public.products (store_id);
CREATE INDEX IF NOT EXISTS products_category_idx   ON public.products (category);
CREATE INDEX IF NOT EXISTS products_created_at_idx ON public.products (created_at DESC);

-- ============================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================

-- ── profiles ──────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"   ON public.profiles;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- ── stores ────────────────────────────────────────────────────
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stores_public_read"   ON public.stores;
DROP POLICY IF EXISTS "stores_owner_read"    ON public.stores;
DROP POLICY IF EXISTS "stores_owner_insert"  ON public.stores;
DROP POLICY IF EXISTS "stores_owner_update"  ON public.stores;

CREATE POLICY "stores_public_read"
  ON public.stores FOR SELECT
  USING (TRUE);

CREATE POLICY "stores_owner_insert"
  ON public.stores FOR INSERT
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "stores_owner_update"
  ON public.stores FOR UPDATE
  USING (auth.uid() = owner_id);

-- ── products ──────────────────────────────────────────────────
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "products_public_read"   ON public.products;
DROP POLICY IF EXISTS "products_owner_insert"  ON public.products;
DROP POLICY IF EXISTS "products_owner_update"  ON public.products;
DROP POLICY IF EXISTS "products_owner_delete"  ON public.products;

CREATE POLICY "products_public_read"
  ON public.products FOR SELECT
  USING (TRUE);

CREATE POLICY "products_owner_insert"
  ON public.products FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = products.store_id
        AND stores.owner_id = auth.uid()
    )
  );

CREATE POLICY "products_owner_update"
  ON public.products FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = products.store_id
        AND stores.owner_id = auth.uid()
    )
  );

CREATE POLICY "products_owner_delete"
  ON public.products FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE stores.id = products.store_id
        AND stores.owner_id = auth.uid()
    )
  );

-- ============================================================
-- 5. REALTIME — enable live updates (safe: skips if already a member)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'products'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'stores'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.stores;
  END IF;
END $$;

-- ============================================================
-- DONE. Go to Supabase Dashboard → Table Editor to verify.
-- ============================================================
