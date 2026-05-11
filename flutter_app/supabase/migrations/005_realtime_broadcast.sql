-- =============================================
-- Migration 005: Realtime broadcast for public web viewer
-- =============================================
-- Purpose: push owner location updates to anonymous browser sessions
-- holding a share_token, so non-app users can view a live share via
-- the /functions/v1/live-share/<token> Edge Function.
--
-- Why broadcast and not Postgres-changes:
--   The natural shape — subscribe to location_history changes on the
--   client — does not work for anonymous viewers. The RLS policy on
--   location_history requires auth.uid() = shared_with_id; a browser
--   session opened from an SMS link has no auth.uid(), so every
--   change event is filtered to zero. Instead, this migration adds a
--   trigger that publishes via realtime.send() to a token-scoped
--   broadcast channel 'share:<token>'. Broadcast does not enforce the
--   same RLS path; security comes from the unguessable UUID in the
--   topic name (same threat model as the get_live_share RPC).
--
-- Includes:
--   1. broadcast_location_to_shares()  — AFTER INSERT on location_history
--   2. broadcast_share_state_change()  — AFTER UPDATE on location_sharing
--   3. RLS policy on realtime.messages — anon SELECT for 'share:*' topics
--   4. get_live_share() amendment      — LEFT JOIN so brand-new shares
--      return a sentinel row instead of looking like 'invalid_token'
--      before the first GPS fix arrives.
-- =============================================

-- =============================================
-- 1. Trigger: broadcast each new location_history row to active shares
-- =============================================
-- AFTER INSERT trigger that fans out a 'position' broadcast to every
-- active, non-revoked, non-expired share owned by NEW.user_id.
--
-- SECURITY DEFINER is required because realtime.send() writes to
-- realtime.messages, which the anon/authenticated roles cannot write
-- to directly. The function runs as the table owner (postgres) so it
-- has the necessary write privilege without exposing realtime.messages
-- via RLS for INSERT.
--
-- Each individual realtime.send() call is wrapped in its own
-- BEGIN/EXCEPTION block: a broadcast hiccup must NEVER abort the
-- location_history insert, since that insert is the safety primitive
-- the entire app depends on (SOS, sharing, history retention all read
-- from this table).
--
-- Payload shape mirrors get_live_share() exactly so the browser has a
-- single render path for both the initial RPC fetch and the broadcast
-- updates. The reverse-geocoded `address` is intentionally omitted —
-- the same doxxing-risk reasoning as get_live_share applies (share URLs
-- live in SMS/WhatsApp logs and a precise street address would make
-- every leaked link a doxxing vector).
CREATE OR REPLACE FUNCTION public.broadcast_location_to_shares()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    r RECORD;
    payload JSONB;
BEGIN
    payload := jsonb_build_object(
        'latitude',           NEW.latitude,
        'longitude',          NEW.longitude,
        'accuracy',           NEW.accuracy,
        'speed',              NEW.speed,
        'heading',            NEW.heading,
        'location_timestamp', NEW.created_at
    );

    FOR r IN
        SELECT share_token
        FROM public.location_sharing
        WHERE owner_id   = NEW.user_id
          AND is_active  = TRUE
          AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > NOW())
    LOOP
        BEGIN
            PERFORM realtime.send(
                payload,
                'position',
                'share:' || r.share_token::text,
                true   -- private; subscribers gated by RLS on realtime.messages
            );
        EXCEPTION WHEN OTHERS THEN
            -- Never let broadcast failure abort the location insert.
            RAISE WARNING 'broadcast_location_to_shares failed for token %: %',
                r.share_token, SQLERRM;
        END;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_broadcast_location_to_shares
    ON public.location_history;

CREATE TRIGGER trg_broadcast_location_to_shares
    AFTER INSERT ON public.location_history
    FOR EACH ROW
    EXECUTE FUNCTION public.broadcast_location_to_shares();

-- =============================================
-- 2. Trigger: broadcast share end-of-life events
-- =============================================
-- Without this, the browser only learns that a share has ended when its
-- next polling tick (5s) hits get_live_share() and gets P0002. The
-- broadcast path makes the transition near-instant, which matters for
-- UX: when the sharer taps "Stop sharing" they expect the recipient to
-- see "Sharing has ended" right away, not 5 seconds later.
CREATE OR REPLACE FUNCTION public.broadcast_share_state_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF (OLD.is_active = TRUE AND NEW.is_active = FALSE)
       OR (OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL) THEN
        BEGIN
            PERFORM realtime.send(
                jsonb_build_object(
                    'is_active', false,
                    'reason', CASE
                        WHEN NEW.revoked_at IS NOT NULL THEN 'revoked'
                        ELSE 'expired'
                    END
                ),
                'share_ended',
                'share:' || NEW.share_token::text,
                true
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'broadcast_share_state_change failed for token %: %',
                NEW.share_token, SQLERRM;
        END;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_broadcast_share_state_change
    ON public.location_sharing;

CREATE TRIGGER trg_broadcast_share_state_change
    AFTER UPDATE ON public.location_sharing
    FOR EACH ROW
    EXECUTE FUNCTION public.broadcast_share_state_change();

-- =============================================
-- 3. RLS: anon can subscribe to 'share:*' topics
-- =============================================
-- realtime.messages ships with RLS enabled and no default permissive
-- policies, so anonymous subscribers receive nothing unless we add an
-- explicit SELECT policy. We allow SELECT for ANY 'share:*' topic — the
-- security model is that the topic name itself contains the unguessable
-- UUID share_token (122 bits of entropy). Same model as get_live_share.
--
-- Writes remain SECURITY DEFINER from the triggers above, so the anon
-- role cannot publish into the channel — only subscribe.
--
-- Wrapped in DO so the migration is safe to run on a project that
-- doesn't have realtime.messages (extremely old self-hosted instance).
-- In that case the migration completes and the trigger functions will
-- log warnings at runtime.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'realtime' AND c.relname = 'messages'
    ) THEN
        DROP POLICY IF EXISTS "Anon can read share:* topics"
            ON realtime.messages;
        EXECUTE $policy$
            CREATE POLICY "Anon can read share:* topics"
                ON realtime.messages
                FOR SELECT
                TO anon, authenticated
                USING (realtime.topic() LIKE 'share:%')
        $policy$;
    END IF;
END $$;

-- =============================================
-- 4. get_live_share() — LEFT JOIN amendment
-- =============================================
-- The original definition (migration 002) INNER JOINs location_history.
-- That breaks a thin race window: when a user starts a share, the
-- location_sharing row is inserted ~immediately, but the first
-- location_history row only arrives after the next position tick (up
-- to 30s on the normal tier, 5s on emergency). Until then,
-- get_live_share returns 0 rows, the client treats that as
-- 'invalid_token', and the recipient sees a confusing error.
--
-- LEFT JOIN + COALESCE on the join key keeps a sentinel row alive: the
-- function always returns a single row with valid is_active/expires_at
-- and the lat/lng/etc fields are NULL until the first fix lands. The
-- viewer page renders this as "Waiting for first GPS fix…".
--
-- DROP first: Postgres refuses CREATE OR REPLACE FUNCTION when the
-- return type (OUT parameters / RETURNS TABLE columns) differs from
-- the existing definition (error 42P13). We can't assume the deployed
-- version matches migration 002 exactly — earlier prod deploys may
-- have had different column orderings or types. Dropping makes this
-- migration robust to whatever shape currently exists.
DROP FUNCTION IF EXISTS public.get_live_share(uuid);

CREATE OR REPLACE FUNCTION public.get_live_share(p_token UUID)
RETURNS TABLE (
    owner_name         TEXT,
    latitude           DOUBLE PRECISION,
    longitude          DOUBLE PRECISION,
    accuracy           DOUBLE PRECISION,
    speed              DOUBLE PRECISION,
    heading            DOUBLE PRECISION,
    location_timestamp TIMESTAMPTZ,
    is_active          BOOLEAN,
    expires_at         TIMESTAMPTZ
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

    -- Always return exactly one row. The latest-position subquery
    -- yields NULLs when no location_history exists yet for this owner;
    -- the viewer page renders that as "Waiting for first GPS fix…".
    RETURN QUERY
    SELECT
        p.name,
        lh.latitude,
        lh.longitude,
        lh.accuracy,
        lh.speed,
        lh.heading,
        lh.created_at,
        v_share.is_active,
        v_share.expires_at
    FROM public.profiles p
    LEFT JOIN LATERAL (
        SELECT latitude, longitude, accuracy, speed, heading, created_at
        FROM public.location_history
        WHERE user_id = v_share.owner_id
        ORDER BY created_at DESC
        LIMIT 1
    ) lh ON TRUE
    WHERE p.id = v_share.owner_id;
END;
$$;

-- Grant stays the same as in migration 002, but re-stating it here so
-- a fresh DB applied straight from migrations gets it consistently.
REVOKE ALL ON FUNCTION public.get_live_share(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_live_share(UUID) TO anon, authenticated;
