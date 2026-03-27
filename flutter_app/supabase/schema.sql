-- Safety App Database Schema for Supabase
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/_/sql
--
-- SECURITY FIXES APPLIED:
-- - Fixed SECURITY DEFINER privilege escalation
-- - Added coordinate and phone validation
-- - Added rate limiting for SOS
-- - Added missing RLS policies

-- =============================================
-- ENUM TYPES (for data integrity)
-- =============================================
DO $$ BEGIN
    CREATE TYPE sos_type_enum AS ENUM ('emergency', 'test', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE sos_status_enum AS ENUM ('active', 'resolved', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =============================================
-- HELPER FUNCTION: Auto-update updated_at
-- =============================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- PROFILES TABLE (extends auth.users)
-- =============================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT '',
    phone TEXT,
    photo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Phone validation: E.164 format (optional, can be null)
    CONSTRAINT valid_phone CHECK (phone IS NULL OR phone ~ '^\+[1-9]\d{1,14}$')
);

-- Auto-update updated_at trigger
DROP TRIGGER IF EXISTS set_updated_at_profiles ON public.profiles;
CREATE TRIGGER set_updated_at_profiles
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger to auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, name, phone)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', ''),
        NEW.phone
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create trigger
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =============================================
-- EMERGENCY CONTACTS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    relationship TEXT,
    is_primary BOOLEAN DEFAULT FALSE,
    notify_on_sos BOOLEAN DEFAULT TRUE,
    share_location BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Phone validation: E.164 format
    CONSTRAINT valid_contact_phone CHECK (phone ~ '^\+[1-9]\d{1,14}$'),
    -- Prevent duplicate contacts for same user
    CONSTRAINT unique_contact_per_user UNIQUE (user_id, phone)
);

-- Auto-update updated_at trigger
DROP TRIGGER IF EXISTS set_updated_at_emergency_contacts ON public.emergency_contacts;
CREATE TRIGGER set_updated_at_emergency_contacts
    BEFORE UPDATE ON public.emergency_contacts
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Ensure only one primary contact per user
CREATE OR REPLACE FUNCTION public.ensure_single_primary_contact()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_primary = TRUE THEN
        UPDATE public.emergency_contacts
        SET is_primary = FALSE
        WHERE user_id = NEW.user_id
        AND id != NEW.id
        AND is_primary = TRUE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_single_primary_contact ON public.emergency_contacts;
CREATE TRIGGER enforce_single_primary_contact
    BEFORE INSERT OR UPDATE ON public.emergency_contacts
    FOR EACH ROW
    WHEN (NEW.is_primary = TRUE)
    EXECUTE FUNCTION public.ensure_single_primary_contact();

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_emergency_contacts_user_id ON public.emergency_contacts(user_id);

-- =============================================
-- SOS HISTORY TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS public.sos_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    address TEXT,
    sos_type sos_type_enum DEFAULT 'emergency',
    status sos_status_enum DEFAULT 'active',
    notified_contacts UUID[] DEFAULT '{}',
    message TEXT,
    audio_url TEXT,
    video_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    -- Coordinate validation
    CONSTRAINT valid_sos_latitude CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT valid_sos_longitude CHECK (longitude >= -180 AND longitude <= 180)
);

-- Rate limiting: Prevent SOS spam (max 5 per 10 minutes)
CREATE OR REPLACE FUNCTION public.check_sos_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
    recent_count INT;
BEGIN
    SELECT COUNT(*) INTO recent_count
    FROM public.sos_history
    WHERE user_id = NEW.user_id
    AND created_at > NOW() - INTERVAL '10 minutes'
    AND sos_type = 'emergency';

    -- Allow max 5 emergency SOS per 10 minutes
    IF recent_count >= 5 THEN
        RAISE EXCEPTION 'Rate limit exceeded: Maximum 5 SOS alerts per 10 minutes. Please wait before sending another alert.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_sos_rate_limit ON public.sos_history;
CREATE TRIGGER enforce_sos_rate_limit
    BEFORE INSERT ON public.sos_history
    FOR EACH ROW
    WHEN (NEW.sos_type = 'emergency')
    EXECUTE FUNCTION public.check_sos_rate_limit();

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_sos_history_user_id ON public.sos_history(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_history_status ON public.sos_history(status);

-- =============================================
-- LOCATION HISTORY TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS public.location_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    altitude DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    address TEXT,
    is_sos_location BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    -- Coordinate validation
    CONSTRAINT valid_location_latitude CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT valid_location_longitude CHECK (longitude >= -180 AND longitude <= 180),
    CONSTRAINT valid_accuracy CHECK (accuracy IS NULL OR accuracy >= 0)
);

-- Index for faster queries (latest locations)
CREATE INDEX IF NOT EXISTS idx_location_history_user_id_created ON public.location_history(user_id, created_at DESC);

-- Index for cleanup function
CREATE INDEX IF NOT EXISTS idx_location_history_cleanup
    ON public.location_history(created_at, is_sos_location)
    WHERE is_sos_location = FALSE;

-- =============================================
-- LOCATION SHARING TABLE (who can see user's location)
-- =============================================
CREATE TABLE IF NOT EXISTS public.location_sharing (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    shared_with_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    shared_with_phone TEXT, -- For non-registered users
    is_active BOOLEAN DEFAULT TRUE,
    share_duration_minutes INT, -- NULL = indefinite
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    -- Prevent duplicate active shares
    CONSTRAINT valid_share_duration CHECK (share_duration_minutes IS NULL OR share_duration_minutes > 0),
    -- Phone validation for non-registered users
    CONSTRAINT valid_shared_phone CHECK (shared_with_phone IS NULL OR shared_with_phone ~ '^\+[1-9]\d{1,14}$')
);

-- Unique active share per user pair
CREATE UNIQUE INDEX IF NOT EXISTS idx_location_sharing_unique_active
    ON public.location_sharing(owner_id, shared_with_id)
    WHERE is_active = TRUE AND shared_with_id IS NOT NULL;

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_location_sharing_owner ON public.location_sharing(owner_id);
CREATE INDEX IF NOT EXISTS idx_location_sharing_shared_with ON public.location_sharing(shared_with_id);
CREATE INDEX IF NOT EXISTS idx_location_sharing_expires
    ON public.location_sharing(expires_at)
    WHERE expires_at IS NOT NULL AND is_active = TRUE;

-- =============================================
-- APP SETTINGS TABLE (user preferences)
-- =============================================
CREATE TABLE IF NOT EXISTS public.app_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    shake_sensitivity INT DEFAULT 3,
    shake_enabled BOOLEAN DEFAULT TRUE,
    auto_record_on_sos BOOLEAN DEFAULT TRUE,
    location_tracking_enabled BOOLEAN DEFAULT TRUE,
    location_update_interval INT DEFAULT 30, -- seconds
    emergency_message TEXT DEFAULT 'I need help! This is an emergency.',
    dark_mode BOOLEAN DEFAULT FALSE,
    notifications_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Validation
    CONSTRAINT valid_shake_sensitivity CHECK (shake_sensitivity >= 1 AND shake_sensitivity <= 5),
    CONSTRAINT valid_location_interval CHECK (location_update_interval >= 10 AND location_update_interval <= 300)
);

-- Auto-update updated_at trigger
DROP TRIGGER IF EXISTS set_updated_at_app_settings ON public.app_settings;
CREATE TRIGGER set_updated_at_app_settings
    BEFORE UPDATE ON public.app_settings
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- =============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sos_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_sharing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- PROFILES: Users can read/update/insert their own profile
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- EMERGENCY CONTACTS: Users can CRUD their own contacts
CREATE POLICY "Users can view own contacts"
    ON public.emergency_contacts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own contacts"
    ON public.emergency_contacts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own contacts"
    ON public.emergency_contacts FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own contacts"
    ON public.emergency_contacts FOR DELETE
    USING (auth.uid() = user_id);

-- SOS HISTORY: Users can view/create/update their own SOS records
CREATE POLICY "Users can view own SOS history"
    ON public.sos_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own SOS"
    ON public.sos_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own SOS"
    ON public.sos_history FOR UPDATE
    USING (auth.uid() = user_id);

-- LOCATION HISTORY: Users can manage their own location data
CREATE POLICY "Users can view own locations"
    ON public.location_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own locations"
    ON public.location_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own non-SOS locations (GDPR/DPDPA compliance)
CREATE POLICY "Users can delete own non-SOS locations"
    ON public.location_history FOR DELETE
    USING (auth.uid() = user_id AND is_sos_location = FALSE);

-- LOCATION SHARING: Users can manage their sharing settings
CREATE POLICY "Owners can view their sharing"
    ON public.location_sharing FOR SELECT
    USING (auth.uid() = owner_id);

CREATE POLICY "Owners can create sharing"
    ON public.location_sharing FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Owners can update sharing"
    ON public.location_sharing FOR UPDATE
    USING (auth.uid() = owner_id);

CREATE POLICY "Owners can delete sharing"
    ON public.location_sharing FOR DELETE
    USING (auth.uid() = owner_id);

-- Shared users can view sharing records where they have access
CREATE POLICY "Shared users can view their access"
    ON public.location_sharing FOR SELECT
    USING (auth.uid() = shared_with_id AND is_active = TRUE);

-- Location access policy: shared users can view owner's recent locations
CREATE POLICY "Shared users can view shared locations"
    ON public.location_history FOR SELECT
    USING (
        user_id IN (
            SELECT owner_id
            FROM public.location_sharing
            WHERE shared_with_id = auth.uid()
              AND is_active = TRUE
              AND (expires_at IS NULL OR expires_at > NOW())
        )
    );

-- APP SETTINGS: Users can manage their own settings
CREATE POLICY "Users can view own settings"
    ON public.app_settings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own settings"
    ON public.app_settings FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own settings"
    ON public.app_settings FOR UPDATE
    USING (auth.uid() = user_id);

-- =============================================
-- REALTIME SUBSCRIPTIONS
-- =============================================

-- Enable realtime for specific tables
-- Note: Consider using filtered subscriptions in production for better performance
ALTER PUBLICATION supabase_realtime ADD TABLE public.location_history;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_history;

-- =============================================
-- HELPER FUNCTIONS (SECURITY FIXED)
-- =============================================

-- Function to get user's latest location (WITH PERMISSION CHECK)
CREATE OR REPLACE FUNCTION public.get_latest_location(target_user_id UUID)
RETURNS TABLE (
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    address TEXT,
    created_at TIMESTAMPTZ
)
SECURITY INVOKER -- Uses caller's permissions, not creator's
AS $$
BEGIN
    -- Permission check: User can only view their own location or shared locations
    IF target_user_id != auth.uid() AND NOT EXISTS (
        SELECT 1 FROM public.location_sharing ls
        WHERE ls.owner_id = target_user_id
        AND ls.shared_with_id = auth.uid()
        AND ls.is_active = TRUE
        AND (ls.expires_at IS NULL OR ls.expires_at > NOW())
    ) THEN
        RAISE EXCEPTION 'Access denied: You do not have permission to view this location';
    END IF;

    RETURN QUERY
    SELECT
        lh.latitude,
        lh.longitude,
        lh.accuracy,
        lh.address,
        lh.created_at
    FROM public.location_history lh
    WHERE lh.user_id = target_user_id
    ORDER BY lh.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup old location data (ADMIN ONLY)
-- Note: This should be called via pg_cron or service role, not by users
CREATE OR REPLACE FUNCTION public.cleanup_old_locations()
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    -- This function uses SECURITY INVOKER so it respects RLS
    -- It should be called by service_role or via pg_cron

    DELETE FROM public.location_history
    WHERE created_at < NOW() - INTERVAL '30 days'
    AND is_sos_location = FALSE;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Function to expire old location shares (for scheduled job)
CREATE OR REPLACE FUNCTION public.expire_location_shares()
RETURNS INT AS $$
DECLARE
    updated_count INT;
BEGIN
    UPDATE public.location_sharing
    SET is_active = FALSE
    WHERE expires_at IS NOT NULL
    AND expires_at <= NOW()
    AND is_active = TRUE;

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- =============================================
-- INDEXES FOR PERFORMANCE
-- =============================================

-- Profile phone lookup
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON public.profiles(phone)
    WHERE phone IS NOT NULL;

-- Emergency contacts with notification flag
CREATE INDEX IF NOT EXISTS idx_emergency_contacts_notify
    ON public.emergency_contacts(user_id, notify_on_sos)
    WHERE notify_on_sos = TRUE;

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_emergency_contacts_primary
    ON public.emergency_contacts(user_id, is_primary) WHERE is_primary = TRUE;

CREATE INDEX IF NOT EXISTS idx_sos_active
    ON public.sos_history(user_id, status) WHERE status = 'active';

-- Active SOS with timestamp for emergency dashboard
CREATE INDEX IF NOT EXISTS idx_sos_history_active_created
    ON public.sos_history(status, created_at DESC)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_location_sharing_active
    ON public.location_sharing(shared_with_id, is_active) WHERE is_active = TRUE;

-- Optimized index for RLS policy subquery
CREATE INDEX IF NOT EXISTS idx_location_sharing_access
    ON public.location_sharing(owner_id, shared_with_id, is_active, expires_at)
    WHERE is_active = TRUE;

-- =============================================
-- SCHEDULED JOBS (requires pg_cron extension)
-- =============================================
-- Uncomment these after enabling pg_cron in Supabase dashboard:
--
-- -- Cleanup old locations daily at 2 AM
-- SELECT cron.schedule(
--     'cleanup-old-locations',
--     '0 2 * * *',
--     $$SELECT public.cleanup_old_locations()$$
-- );
--
-- -- Expire location shares every minute
-- SELECT cron.schedule(
--     'expire-location-shares',
--     '* * * * *',
--     $$SELECT public.expire_location_shares()$$
-- );
