-- ============================================================
-- Run in Supabase SQL Editor
-- Creates the orders table with full tracking
-- ============================================================

CREATE TABLE IF NOT EXISTS public.orders (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  ref             TEXT          NOT NULL UNIQUE,           -- human-readable e.g. CS-20240312-A3F2
  store_id        UUID          NOT NULL REFERENCES public.stores(id)    ON DELETE CASCADE,
  product_id      UUID          NOT NULL REFERENCES public.products(id)  ON DELETE CASCADE,
  promoter_id     UUID          REFERENCES public.profiles(id)           ON DELETE SET NULL,

  -- Buyer info (guest — no account required)
  buyer_name      TEXT          NOT NULL,
  buyer_phone     TEXT          NOT NULL,
  buyer_address   TEXT          NOT NULL DEFAULT '',
  buyer_city      TEXT          NOT NULL DEFAULT '',

  -- Order details
  quantity        INTEGER       NOT NULL DEFAULT 1 CHECK (quantity > 0),
  base_price      NUMERIC(10,2) NOT NULL,
  markup          NUMERIC(10,2) NOT NULL DEFAULT 0,
  delivery_fee    NUMERIC(10,2) NOT NULL DEFAULT 0,
  total           NUMERIC(10,2) NOT NULL,
  fulfillment     TEXT          NOT NULL DEFAULT 'delivery' CHECK (fulfillment IN ('delivery','pickup')),
  payment_method  TEXT          NOT NULL DEFAULT 'whatsapp' CHECK (payment_method IN ('whatsapp','paystack')),
  paystack_ref    TEXT          NOT NULL DEFAULT '',

  -- Status
  status          TEXT          NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','confirmed','processing','shipped','delivered','cancelled')),

  note            TEXT          NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
DROP TRIGGER IF EXISTS orders_updated_at ON public.orders;
CREATE TRIGGER orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- RLS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Anyone can insert (guest checkout)
CREATE POLICY "orders_insert_anon"
  ON public.orders FOR INSERT
  WITH CHECK (true);

-- Store owner can read their orders
CREATE POLICY "orders_agent_read"
  ON public.orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = store_id AND s.owner_id = auth.uid()
    )
  );

-- Store owner can update status
CREATE POLICY "orders_agent_update"
  ON public.orders FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = store_id AND s.owner_id = auth.uid()
    )
  );

-- Promoter can read orders they referred
CREATE POLICY "orders_promoter_read"
  ON public.orders FOR SELECT
  USING (promoter_id = auth.uid());
