-- ============================================================
-- Run in Supabase SQL Editor
-- Adds profile picture and banner to profiles table
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_url         TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS profile_banner_url TEXT NOT NULL DEFAULT '';
