-- CertiVault upgrade
-- Run this once in Supabase SQL Editor.
-- Stores certificate design and signatory metadata as JSONB.
ALTER TABLE public.certificates
ADD COLUMN IF NOT EXISTS certificate_data jsonb NOT NULL DEFAULT '{}'::jsonb;
