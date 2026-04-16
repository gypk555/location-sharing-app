-- =============================================
-- Migration 002: Live Location Sharing
-- =============================================
-- Adds support for the live location sharing feature:
--   - Per-recipient share tokens (public web link)
--   - Session grouping (one UX session = N recipients)
--   - SOS auto-start tracking
--   - Heartbeat + revocation columns
--   - FCM token on profiles for push notifications
--   - Public SECURITY DEFINER RPC for the tokenized web receiver
--   - find_user_by_phone RPC for contact->user resolution
--   - pg_cron schedule to auto-expire shares
--
-- NOTE: Recipient-notification delivery is handled via a Supabase
-- Database Webhook (Dashboard -> Database -> Webhooks) instead of an
-- in-database pg_net trigger. This avoids the need to store the
-- service-role key in a database GUC.
-- =============================================

-- =============================================
-- 1. Extend location_sharing
-- =============================================
ALTER TABLE public.location_sharing
    ADD COLUMN IF NOT EXISTS share_token UUID NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS session_group_id UUID,
    ADD COLUMN IF NOT EXISTS trigger_source TEXT
        CHECK (trigger_source IN ('manual', 'sos')) DEFAULT 'manual',
    ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS shared_with_name TEXT,
    ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

-- share_token is the public URL identifier (one per recipient)
CREATE UNIQUE INDEX IF NOT EXISTS idx_location_sharing_share_token
    ON public.location_sharing(share_token);

-- session_group_id groups multiple recipient rows into one UX "session"
CREATE INDEX IF NOT EXISTS idx_location_sharing_session_group
    ON public.location_sharing(session_group_id)
    WHERE session_group_id IS NOT NULL;

-- Heartbeat age lookup (used by watchdog to detect stalled sharing)
CREATE INDEX IF NOT EXISTS idx_location_sharing_heartbeat
    ON public.location_sharing(last_heartbeat_at)
    WHERE is_active = TRUE;

-- =============================================
-- 2. FCM token on profiles (for push notifications)
-- =============================================
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS fcm_token TEXT,
    ADD COLUMN IF NOT EXISTS fcm_token_updated_at TIMESTAMPTZ;

-- =============================================
-- 3. Public RPC: get_live_share(token)
-- =============================================
-- Called by the anonymous web receiver to fetch the owner's latest
-- location for a given share token. Validates token is active and
-- not expired before returning any data. Uses SECURITY DEFINER so
-- anon role can execute it without direct RLS access to tables.
--
-- Returns: a single row with owner name + latest location.
-- Raises: 'invalid_token' (P0001) or 'share_ended' (P0002).
CREATE OR REPLACE FUNCTION public.get_live_share(p_token UUID)
RETURNS TABLE (
    owner_name TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    address TEXT,
    location_timestamp TIMESTAMPTZ,
    is_active BOOLEAN,
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_share RECORD;
BEGIN
    SELECT ls.owner_id, ls.is_active, ls.expires_at, ls.revoked_at
    INTO v_share
    FROM public.location_sharing ls
    WHERE ls.share_token = p_token
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_token' USING ERRCODE = 'P0001';
    END IF;

    IF v_share.revoked_at IS NOT NULL
       OR NOT v_share.is_active
       OR (v_share.expires_at IS NOT NULL AND v_share.expires_at < NOW()) THEN
        RAISE EXCEPTION 'share_ended' USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
    SELECT
        p.name,
        lh.latitude,
        lh.longitude,
        lh.accuracy,
        lh.speed,
        lh.heading,
        lh.address,
        lh.created_at,
        v_share.is_active,
        v_share.expires_at
    FROM public.location_history lh
    JOIN public.profiles p ON p.id = v_share.owner_id
    WHERE lh.user_id = v_share.owner_id
    ORDER BY lh.created_at DESC
    LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.get_live_share(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_live_share(UUID) TO anon, authenticated;

-- =============================================
-- 4. RPC: find_user_by_phone(phone)
-- =============================================
-- Resolves an E.164 phone number to a registered profile id, if any.
-- Called by the Flutter app when starting a live share to determine
-- whether a contact can receive in-app realtime updates or should
-- instead receive an SMS link.
--
-- SECURITY DEFINER is intentional: we want authenticated users to be
-- able to check if a phone is registered, without exposing the full
-- profiles table via RLS.
CREATE OR REPLACE FUNCTION public.find_user_by_phone(p_phone TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT id
    FROM public.profiles
    WHERE phone = p_phone
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_user_by_phone(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(TEXT) TO authenticated;

-- =============================================
-- 5. Schedule auto-expire of location shares
-- =============================================
-- Runs every minute. Marks any active share past its expires_at
-- as inactive. Idempotent — safe to run concurrently with app writes.
-- Uses pg_cron (must be enabled in Database -> Extensions).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Unschedule any previous registration so this migration is re-runnable
        PERFORM cron.unschedule('expire-location-shares')
        WHERE EXISTS (
            SELECT 1 FROM cron.job WHERE jobname = 'expire-location-shares'
        );

        PERFORM cron.schedule(
            'expire-location-shares',
            '* * * * *',
            $cron$SELECT public.expire_location_shares();$cron$
        );
    END IF;
END $$;

-- =============================================
-- 6. Backfill session_group_id for existing rows (if any)
-- =============================================
-- Any pre-existing location_sharing rows get their own session group.
-- Safe no-op if the table is empty.
UPDATE public.location_sharing
SET session_group_id = gen_random_uuid()
WHERE session_group_id IS NULL;

-- =============================================
-- 7. Realtime: publication membership + REPLICA IDENTITY
-- =============================================
-- The Flutter receiver subscribes to realtime changes on these two tables
-- so it can (a) render live position updates and (b) react when a share
-- is ended or revoked. Two things must be true for events to reach the
-- client through RLS:
--
--   1. The table must be a member of the `supabase_realtime` publication
--      (otherwise Postgres doesn't emit WAL events for it).
--   2. REPLICA IDENTITY must be FULL — RLS is evaluated against the row
--      contents and the default (primary key only) hides the columns
--      our policies rely on (shared_with_id, user_id). Without FULL,
--      UPDATE events silently fail the policy check and never fire.
--
-- Both operations are idempotent when wrapped as below.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'location_sharing'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.location_sharing;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'location_history'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.location_history;
    END IF;
END $$;

ALTER TABLE public.location_sharing REPLICA IDENTITY FULL;
ALTER TABLE public.location_history  REPLICA IDENTITY FULL;

-- =============================================
-- 8. Recipient SELECT policy (without is_active filter)
-- =============================================
-- The original policy from schema.sql ("Shared users can view their
-- access") filters SELECT on `is_active = TRUE`. That breaks realtime
-- UPDATE events: when the owner stops sharing, the event carries the
-- NEW row (is_active = FALSE) and the RLS check runs against it, so
-- recipients never see the end-of-share event and the UI stays stuck
-- on "loading".
--
-- We drop the old policy and replace it with one that only checks
-- identity — the recipient can always see rows addressed to them.
-- Active/inactive filtering is moved to application-level queries
-- where needed.
DROP POLICY IF EXISTS "Shared users can view their access"
    ON public.location_sharing;
DROP POLICY IF EXISTS "Recipients can view active shares for themselves"
    ON public.location_sharing;
CREATE POLICY "Recipients can view active shares for themselves"
    ON public.location_sharing
    FOR SELECT
    TO authenticated
    USING (shared_with_id = auth.uid());
