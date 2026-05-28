-- ============================================================
-- Migration: Add product media support (5 images + 1 video)
-- ============================================================

-- Option 1: Add columns to products table (simpler, but less flexible)
-- ALTER TABLE public.products
--   ADD COLUMN IF NOT EXISTS image_url2 TEXT NOT NULL DEFAULT '',
--   ADD COLUMN IF NOT EXISTS image_url3 TEXT NOT NULL DEFAULT '',
--   ADD COLUMN IF NOT EXISTS image_url4 TEXT NOT NULL DEFAULT '',
--   ADD COLUMN IF NOT EXISTS image_url5 TEXT NOT NULL DEFAULT '',
--   ADD COLUMN IF NOT EXISTS video_url TEXT NOT NULL DEFAULT '';

-- Option 2: Create separate product_media table (more flexible, recommended)
CREATE TABLE IF NOT EXISTS public.product_media (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id  UUID          NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  media_type  TEXT          NOT NULL CHECK (media_type IN ('image','video')),
  media_url   TEXT          NOT NULL,
  sort_order  INT           NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_product_media_product_id ON public.product_media(product_id);

-- Enable RLS
ALTER TABLE public.product_media ENABLE ROW LEVEL SECURITY;

-- Policy: anyone can view product media
CREATE POLICY "Product media public read"
  ON public.product_media FOR SELECT
  USING (true);

-- Policy: only product owner can insert/update/delete
CREATE POLICY "Product media owner write"
  ON public.product_media FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      JOIN public.stores s ON p.store_id = s.id
      WHERE p.id = product_media.product_id
      AND s.owner_id = auth.uid()
    )
  );
