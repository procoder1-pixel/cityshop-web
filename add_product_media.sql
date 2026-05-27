-- Add images array and video_url to products table
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS images    TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS video_url TEXT DEFAULT NULL;
