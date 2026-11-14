-- CertiVault database repair
-- Run this complete script once in Supabase SQL Editor.
-- Preserves existing certificate rows and aligns the schema with index.html.

BEGIN;

-- Ensure every field used by the current CertiVault app exists.
ALTER TABLE public.certificates
  ADD COLUMN IF NOT EXISTS certificate_title text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS course_name text,
  ADD COLUMN IF NOT EXISTS issue_date date,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS verification_token uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS recipient_photo_path text,
  ADD COLUMN IF NOT EXISTS certificate_data jsonb NOT NULL DEFAULT '{}'::jsonb;

-- Remove the old status rule first so legacy rows can be normalized.
ALTER TABLE public.certificates
  DROP CONSTRAINT IF EXISTS certificates_status_check;

-- Make sure old rows have a valid status and token.
UPDATE public.certificates
SET status = CASE
  WHEN lower(coalesce(status, '')) = 'revoked' THEN 'revoked'
  ELSE 'active'
END
WHERE status IS NULL OR lower(status) NOT IN ('active', 'revoked');

UPDATE public.certificates
SET verification_token = gen_random_uuid()
WHERE verification_token IS NULL;

ALTER TABLE public.certificates
  ALTER COLUMN status SET DEFAULT 'active',
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN verification_token SET DEFAULT gen_random_uuid();

-- The app uses exactly these two status values.
ALTER TABLE public.certificates
  ADD CONSTRAINT certificates_status_check
  CHECK (status IN ('active', 'revoked'));

-- Allow an authenticated institution admin to issue certificates
-- only for the institution linked to their own profile.
DROP POLICY IF EXISTS certificates_admin_insert_own ON public.certificates;
CREATE POLICY certificates_admin_insert_own
ON public.certificates
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.user_id = auth.uid()
      AND p.institution_id = certificates.institution_id
      AND p.role = 'admin'
  )
);

-- Allow that institution's admin to upload its own recipient photos and logos.
DROP POLICY IF EXISTS certivault_admin_upload_own_files ON storage.objects;
CREATE POLICY certivault_admin_upload_own_files
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'certificate-photos'
  AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.user_id = auth.uid()
      AND p.institution_id::text = (storage.foldername(name))[1]
      AND p.role = 'admin'
  )
);

COMMIT;

-- Refresh the API schema cache after the transaction.
NOTIFY pgrst, 'reload schema';
