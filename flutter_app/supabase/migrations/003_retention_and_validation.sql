-- =============================================
-- Migration 003: Retention enforcement + server-side length validation
-- =============================================
-- Addresses two findings from the 2026-04-17 security review:
--
--   M-2  The 30-day location retention advertised in CLAUDE.md was never
--        actually enforced: cleanup_old_locations() exists in schema.sql but
--        the pg_cron SELECT cron.schedule(...) call was left commented out.
--        Indefinite growth of location_history violates data-minimisation
--        under DPDPA (India) and GDPR. This migration registers the job
--        idempotently using the same DO-block pattern as
--        002_live_sharing.sql's expire-location-shares registration.
--
--   M-4  Client-side length limits in validators.dart are UX-only. A
--        modified APK / rogue API client could write arbitrarily long
--        strings into profiles.name, emergency_contacts.name, and
--        app_settings.emergency_message. This migration adds CHECK
--        constraints at the database layer so the limits survive the
--        client being bypassed.
-- =============================================

-- =============================================
-- 1. Schedule cleanup_old_locations() (M-2)
-- =============================================
-- Runs daily at 02:00 UTC (07:30 IST). cleanup_old_locations() itself
-- already filters on is_sos_location = FALSE so emergency records are
-- retained for legal / forensic reasons regardless of age.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Unschedule any prior registration so this migration is re-runnable.
        PERFORM cron.unschedule('cleanup-old-locations')
        WHERE EXISTS (
            SELECT 1 FROM cron.job WHERE jobname = 'cleanup-old-locations'
        );

        PERFORM cron.schedule(
            'cleanup-old-locations',
            '0 2 * * *',
            $cron$SELECT public.cleanup_old_locations();$cron$
        );
    END IF;
END $$;

-- =============================================
-- 2. Server-side length CHECK constraints (M-4)
-- =============================================
-- Limits chosen to match Validators in flutter_app/lib/shared/utils/
-- validators.dart so compliant clients never hit these; only tampered
-- ones do. ALTER ... ADD CONSTRAINT IF NOT EXISTS is not available for
-- CHECK constraints in Postgres, so we wrap each in a conditional DO
-- block that inspects pg_constraint first.

-- profiles.name: 100 chars (matches Validators.maxNameLength)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'profiles_name_length'
          AND conrelid = 'public.profiles'::regclass
    ) THEN
        ALTER TABLE public.profiles
            ADD CONSTRAINT profiles_name_length
            CHECK (char_length(name) <= 100);
    END IF;
END $$;

-- emergency_contacts.name: 100 chars
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'emergency_contacts_name_length'
          AND conrelid = 'public.emergency_contacts'::regclass
    ) THEN
        ALTER TABLE public.emergency_contacts
            ADD CONSTRAINT emergency_contacts_name_length
            CHECK (char_length(name) >= 1 AND char_length(name) <= 100);
    END IF;
END $$;

-- emergency_contacts.relationship: 50 chars (optional field)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'emergency_contacts_relationship_length'
          AND conrelid = 'public.emergency_contacts'::regclass
    ) THEN
        ALTER TABLE public.emergency_contacts
            ADD CONSTRAINT emergency_contacts_relationship_length
            CHECK (relationship IS NULL OR char_length(relationship) <= 50);
    END IF;
END $$;

-- app_settings.emergency_message: 500 chars. SMS concatenation caps
-- around 1600 chars but safety messages should be terse; 500 matches
-- the client's textarea max and leaves headroom for the appended
-- location URL.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'app_settings_emergency_message_length'
          AND conrelid = 'public.app_settings'::regclass
    ) THEN
        ALTER TABLE public.app_settings
            ADD CONSTRAINT app_settings_emergency_message_length
            CHECK (char_length(emergency_message) <= 500);
    END IF;
END $$;

-- sos_history.message: 1000 chars (may include user-provided context)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sos_history_message_length'
          AND conrelid = 'public.sos_history'::regclass
    ) THEN
        ALTER TABLE public.sos_history
            ADD CONSTRAINT sos_history_message_length
            CHECK (message IS NULL OR char_length(message) <= 1000);
    END IF;
END $$;

-- location_sharing.shared_with_name: 100 chars
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'location_sharing_shared_with_name_length'
          AND conrelid = 'public.location_sharing'::regclass
    ) THEN
        ALTER TABLE public.location_sharing
            ADD CONSTRAINT location_sharing_shared_with_name_length
            CHECK (shared_with_name IS NULL OR char_length(shared_with_name) <= 100);
    END IF;
END $$;
