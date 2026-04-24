-- ============================================================
-- Run in Supabase SQL Editor
-- Creates the reviews table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.reviews (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id  UUID        NOT NULL REFERENCES public.products(id)  ON DELETE CASCADE,
  store_id    UUID        NOT NULL REFERENCES public.stores(id)    ON DELETE CASCADE,
  order_id    UUID        REFERENCES public.orders(id)             ON DELETE SET NULL,
  buyer_name  TEXT        NOT NULL,
  rating      SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body        TEXT        NOT NULL DEFAULT '',
  verified    BOOLEAN     NOT NULL DEFAULT FALSE,  -- TRUE if linked to a real order
  reply       TEXT        NOT NULL DEFAULT '',     -- agent reply
  replied_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast product/store lookups
CREATE INDEX IF NOT EXISTS reviews_product_id_idx ON public.reviews(product_id);
CREATE INDEX IF NOT EXISTS reviews_store_id_idx   ON public.reviews(store_id);

-- RLS
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Anyone can read reviews
CREATE POLICY "reviews_public_read"
  ON public.reviews FOR SELECT USING (true);

-- Anyone can insert (open reviews)
CREATE POLICY "reviews_public_insert"
  ON public.reviews FOR INSERT WITH CHECK (true);

-- Store owner can update (to add reply)
CREATE POLICY "reviews_agent_reply"
  ON public.reviews FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.stores s
      WHERE s.id = store_id AND s.owner_id = auth.uid()
    )
  );
